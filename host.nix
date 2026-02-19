{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
let
  user = "toxx";
  sshPort = 22;
  hostName = "oracle-vps";
  flakeName = "vps-arm";

  # Local persistent clone of this repo — used by the deploy script
  localRepoPath = "/persistent/nix-vps";

  # Deploy script: pull latest main and rebuild
  # This is the ONLY thing the CI deploy key can execute (via SSH forced command)
  deploy-script = pkgs.writeShellApplication {
    name = "vps-deploy";
    runtimeInputs = with pkgs; [
      git
      nix
      nixos-rebuild
      coreutils
      cacert
    ];
    text = ''
      set -euo pipefail

      LOG="/var/log/nix-deploy.log"
      log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

      log "=== Starting NixOS Deployment ==="

      if [ ! -d "${localRepoPath}" ]; then
        log "Initializing repository at ${localRepoPath}..."
        git clone https://github.com/toxx1220/nix-vps.git "${localRepoPath}"
      fi

      cd ${localRepoPath}

      log "Fetching latest main..."
      git fetch origin main

      log "Resetting to origin/main..."
      git reset --hard origin/main

      log "Starting NixOS rebuild..."
      nixos-rebuild switch --flake ".#${flakeName}" --accept-flake-config -L 2>&1 | tee -a "$LOG"

      log "=== Deployment Complete ==="
    '';
  };

  # --- DOMAIN CONFIGURATION ---
  domains = {
    bgsBackend = "bgsearch.toxx.dev";
    testContainer = "oracle.toxx.dev";
  };

  # --- CONTAINER NAMES ---
  containerNames = {
    nannuoBot = "nannuo-bot";
    bgsBackend = "bgs-backend";
    testContainer = "test-container";
  };

  # --- SERVICE TOGGLES ---
  enableNannuoBot = true;
  enableBgsBackend = false;
  enableTestContainer = true;

  # --- NETWORK CONFIGURATION ---
  networkBridgeName = "br0";
  gatewayIp = "10.0.0.1";

  # --- CONTAINER REGISTRY ---
  containerRegistry = {
    ${containerNames.nannuoBot} = {
      ip = "10.0.0.11";
      proxyDomain = "";
      proxyPort = 0;
    };
    ${containerNames.bgsBackend} = {
      ip = "10.0.0.12";
      proxyDomain = domains.bgsBackend;
      proxyPort = 8080;
    };
    ${containerNames.testContainer} = {
      ip = "10.0.0.10";
      proxyDomain = domains.testContainer;
      proxyPort = 8080;
    };
  };

  # Helper to define a NixOS Container with standard boilerplate
  mkContainer =
    {
      name,
      address, # e.g., "10.0.0.10"
      module,
      packageArg ? null,
      package ? null,
      proxyDomain ? "",
      proxyPort ? 0,
      extraImports ? [ ],
    }:
    {
      autoStart = true;
      privateNetwork = true;
      hostBridge = networkBridgeName;
      localAddress = "${address}/24";

      config =
        { ... }:
        {
          imports = [
            ./containers/common.nix
            module
            inputs.sops-nix.nixosModules.sops
          ]
          ++ extraImports;

          networking.defaultGateway = {
            address = gatewayIp;
            interface = "eth0";
          };

          _module.args = {
            inherit inputs;
            containerName = name;
            containerDomain = proxyDomain;
            containerPort = proxyPort;
          }
          // (lib.optionalAttrs (packageArg != null) { ${packageArg} = package; });
        };

      bindMounts = {
        "sops-key" = {
          hostPath = "/persistent/etc/ssh/ssh_host_ed25519_key";
          mountPoint = "/var/lib/sops-nix/key.txt";
          isReadOnly = true;
        };
      };
    };

in
{
  networking.hostName = hostName;
  time.timeZone = "Europe/Berlin";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
    "virtio_scsi"
    "virtio_net"
  ];
  boot.kernelParams = [ "console=ttyS0" ];

  environment.systemPackages = with pkgs; [
    micro
    btop
    tree
    git
    uwufetch
  ];

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep 3 --keep-since 3d";
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      auto-optimise-store = true;

      # Garnix CI binary cache
      extra-substituters = [
        "https://cache.garnix.io"
      ];
      extra-trusted-public-keys = [
        "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
      ];
      trusted-users = [
        "root"
        user
      ];

      # Netrc file for private Garnix cache access
      netrc-file = config.sops.secrets.garnix-netrc.path;
      narinfo-cache-positive-ttl = 3600;
    };
  };

  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.sshKeyPaths = [
      "/persistent/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key"
    ];
    secrets = {
      user-password.neededForUsers = true;
      root-password.neededForUsers = true;
      garnix-netrc = { };
      impressum-email = { };
      impressum-phone = { };
      impressum-name = { };
    };
  };

  # Persistent storage - neededForBoot ensures mounts happen in initrd
  fileSystems."/persistent".neededForBoot = true;

  environment.persistence."/persistent" = {
    hideMounts = true;
    enableWarnings = false;
    directories = [
      "/var/log" # System logs
      "/var/lib/nixos" # UID/GID maps (prevents permission issues)
      "/var/lib/systemd/coredump"
      "/var/lib/containers" # Persist all container root filesystems
      "/var/lib/caddy" # SSL certificates
      "/var/lib/fail2ban" # Ban history
      {
        directory = "/etc/ssh";
        mode = "u=rwx,g=rx,o=rx";
        user = "root";
      }
    ];
    files = [
      "/etc/machine-id" # Stable identifier for logs and networking
    ];
  };

  users = {
    mutableUsers = false; # recommended when managing passwords via sops & nix
    users = {
      ${user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        hashedPasswordFile = config.sops.secrets.user-password.path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO"
        ];
      };
      root = {
        hashedPasswordFile = config.sops.secrets.root-password.path;
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO"

          # CI deploy key — can ONLY execute the deploy script
          # https://man.openbsd.org/sshd#restrict
          ''command="${deploy-script}/bin/vps-deploy",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPJtzHWaOeBmkkKFtvS0i/WKBphdxFF0ZDOBKNNuLjxL ci-deploy''
        ];
      };
    };
  };

  services.openssh = {
    enable = true;
    ports = [ sshPort ];
    settings = {
      AllowUsers = [
        "root"
        user
      ];
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
    hostKeys = [
      {
        path = "/persistent/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  systemd.services.sshd.preStart = lib.mkBefore ''
    mkdir -p /persistent/etc/ssh
    chmod 755 /persistent/etc/ssh
    if [ -f /persistent/etc/ssh/ssh_host_ed25519_key ]; then
      chmod 600 /persistent/etc/ssh/ssh_host_ed25519_key
    fi
  '';

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    ignoreIP = [
      "127.0.0.1/8"
      "::1"
      "10.0.0.0/24" # Trust the internal bridge
    ];
    bantime = "1h";
    bantime-increment = {
      enable = true;
      factor = "2";
      maxtime = "168h";
    };
  };

  networking = {
    useDHCP = true;
    networkmanager.enable = false;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        sshPort
        80
        443
      ];
    };

    # Bridge for Containers
    bridges.${networkBridgeName}.interfaces = [ ];
    interfaces.${networkBridgeName}.ipv4.addresses = [
      {
        address = gatewayIp;
        prefixLength = 24;
      }
    ];
    nat = {
      enable = true;
      internalInterfaces = [ networkBridgeName ];
      externalInterface = "enp0s6";
    };
  };

  # Native NixOS Containers
  containers =
    (lib.optionalAttrs enableNannuoBot {
      ${containerNames.nannuoBot} = mkContainer {
        name = containerNames.nannuoBot;
        address = containerRegistry.${containerNames.nannuoBot}.ip;
        module = ./containers/nannuo-bot.nix;
        extraImports = [ inputs.nannuo-bot.nixosModules.default ];
      };
    })
    // (lib.optionalAttrs enableBgsBackend {
      ${containerNames.bgsBackend} = mkContainer {
        name = containerNames.bgsBackend;
        address = containerRegistry.${containerNames.bgsBackend}.ip;
        module = ./containers/bgs-backend.nix;
        packageArg = "backend-package";
        package = inputs.bgs-backend.packages.${pkgs.system}.default;
        proxyDomain = containerRegistry.${containerNames.bgsBackend}.proxyDomain;
        proxyPort = containerRegistry.${containerNames.bgsBackend}.proxyPort;
      };
    })
    // (lib.optionalAttrs enableTestContainer {
      ${containerNames.testContainer} = mkContainer {
        name = containerNames.testContainer;
        address = containerRegistry.${containerNames.testContainer}.ip;
        module = ./containers/test-container.nix;
        proxyDomain = containerRegistry.${containerNames.testContainer}.proxyDomain;
        proxyPort = containerRegistry.${containerNames.testContainer}.proxyPort;
      };
    });

  # Dynamic Caddy Configuration for Containers
  services.caddy = {
    enable = true;
    virtualHosts =
      let
        # Filter containers with host-proxy enabled
        proxyEnabledContainers = lib.filterAttrs (
          name: container:
          (container.config.services or { }) ? host-proxy
          && (container.config.services.host-proxy.enable or false)
        ) config.containers;

        mkCaddyEntry = name: container: {
          name = container.config.services.host-proxy.domain;
          value = {
            extraConfig =
              let
                containerIp = lib.head (lib.splitString "/" container.localAddress);
                containerPort = toString container.config.services.host-proxy.port;
              in
              ''
                log {
                  output file /var/log/caddy/${name}.log
                }
                reverse_proxy ${containerIp}:${containerPort}
              '';
          };
        };
      in
      lib.mapAttrs' mkCaddyEntry proxyEnabledContainers
      // {
        "toxx.dev" = {
          extraConfig = ''
            # Set the root directory for this domain to the runtime directory generated by systemd.
            # This directory contains the obfuscated 'impressum.html'.
            root * /run/impressum

            # Enable the file server to serve static files from the root.
            file_server

            # If a file exists at the requested path, serve it.
            # If not, try appending '.html' and serve that.
            # Example: requests to /impressum will serve impressum.html
            try_files {path} {path}.html
          '';
        };
      };
  };

  systemd.services.impressum-generator = {
    description = "Generate impressum from secrets";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      # This creates /run/impressum owned by root:root with mode 0755
      RuntimeDirectory = "impressum";
      RuntimeDirectoryPreserve = "yes";
      User = "root";
      ExecStart = "${pkgs.writers.writeRust "generate-impressum" { } (
        builtins.readFile ./scripts/generate-impressum.rs
      )}";
      Environment = [
        "IMPRESSUM_EMAIL_FILE=${config.sops.secrets.impressum-email.path}"
        "IMPRESSUM_PHONE_FILE=${config.sops.secrets.impressum-phone.path}"
        "IMPRESSUM_NAME_FILE=${config.sops.secrets.impressum-name.path}"
        "IMPRESSUM_TEMPLATE_FILE=${./static/impressum.template.html}"
        "IMPRESSUM_OUTPUT_FILE=/run/impressum/impressum.html"
      ];
    };
  };

  system.stateVersion = "25.11";
}
