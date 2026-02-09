{
  config,
  pkgs,
  lib,
  inputs,
  flakeName,
  ...
}:
let
  user = "toxx";
  sshPort = 22;
  hostName = "oracle-vps";

  repoUrl = "github:toxx1220/nix-vps";
  updateCommand = "${pkgs.nh}/bin/nh os switch --update ${repoUrl} --hostname ${flakeName} -- -L";
  flakeUpdateServiceName = "flake-update";

  # --- DOMAIN CONFIGURATION ---
  domains = {
    webhook = "deploy.toxx.dev";
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

  webhookPort = 9000;

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

          # Pass inputs and other args to the container
          _module.args = {
            inherit inputs;
            containerName = name;
            containerDomain = proxyDomain;
            containerPort = proxyPort;
          }
          // (lib.optionalAttrs (packageArg != null) { ${packageArg} = package; });
        };

      # Host-side container configuration: Bind Mounts
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
    nh
  ];

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep 3 --keep-since 3d";
    flake = repoUrl;
  };

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      # Store optimization - hard-links identical files to save disk space
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
      webhook-secret = {
        owner = "webhook";
      };
      garnix-netrc = { };
    };
  };

  services.webhook = {
    enable = true;
    port = webhookPort;
    hooks = {
      redeploy = {
        execute-command = "${
          pkgs.writeShellApplication {
            name = "redeploy";
            runtimeInputs = with pkgs; [
              git
              nh
              nixos-rebuild
            ];
            text = ''
              sudo ${updateCommand}
            '';
          }
        }/bin/redeploy";
        command-working-directory = "/tmp";
        response-message = "Redeploy triggered";
        incoming-payload-content-type = "application/json";
        http-methods = [ "POST" ];
        trigger-rule = {
          match = {
            type = "payload-hmac-sha256";
            secret-key-path = config.sops.secrets.webhook-secret.path;
            parameter = {
              source = "header";
              name = "X-Hub-Signature-256";
            };
          };
        };
      };
    };
  };

  security.sudo.extraRules = [
    {
      users = [ "webhook" ];
      commands = [
        {
          command = "${pkgs.nh}/bin/nh";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

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
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO" # TODO: replace?
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

        containerHosts = lib.mapAttrs' mkCaddyEntry proxyEnabledContainers;

        staticHosts = {
          ${domains.webhook} = {
            extraConfig = ''
              log {
                output file /var/log/caddy/webhook.log
              }
              reverse_proxy localhost:${toString webhookPort}
            '';
          };
        };
      in
      containerHosts // staticHosts;
  };

  # Weekly system update
  systemd.services.${flakeUpdateServiceName} = {
    description = "Update nix flake inputs and switch to latest configuration";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = updateCommand;
    };
    path = with pkgs; [
      git
      nix
      nh
      nixos-rebuild
    ];
  };

  systemd.timers.${flakeUpdateServiceName} = {
    description = "Timer for weekly flake update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00:00";
      Persistent = true;
    };
  };

  system.stateVersion = "25.11";
}
