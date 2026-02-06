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

  # --- SERVICE TOGGLES ---
  enableNannuoBot = false;
  enableBgsBackend = false;
  enableTestContainer = true;

  networkBridgeName = "br0";
  gatewayIp = "10.0.0.1";

  # Helper to define a NixOS Container with standard boilerplate
  mkContainer =
    {
      name,
      address, # e.g., "10.0.0.10"
      module,
      packageArg ? null,
      package ? null,
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
          ];

          networking.defaultGateway = {
            address = gatewayIp;
            interface = "eth0";
          };

          # Pass inputs and other args to the container
          _module.args = {
            inherit inputs;
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
  ];

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  system.autoUpgrade = {
    enable = true;
    flake = "github:toxx1220/nix-vps"; # TODO: adjust
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # print build logs
    ];
    dates = "02:00";
    randomizedDelaySec = "45min";
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
    };
  };

  # Persistent storage - neededForBoot ensures mounts happen in initrd
  fileSystems."/persistent".neededForBoot = true;
  fileSystems."/etc/ssh".neededForBoot = true;

  environment.persistence."/persistent" = {
    hideMounts = true;
    enableWarnings = false;
    directories = [
      "/var/log"               # System logs
      "/var/lib/nixos"         # UID/GID maps (prevents permission issues)
      "/var/lib/systemd/coredump"
      "/var/lib/containers" # Persist all container root filesystems
      "/var/lib/caddy"  # SSL certificates
      "/var/lib/fail2ban" # Ban history
      {
        directory = "/etc/ssh";
        mode = "u=rwx,g=rx,o=rx";
        user = "root";
      }
    ];
    files = [
      "/etc/machine-id"        # Stable identifier for logs and networking
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
      nannuo-bot = mkContainer {
        name = "nannuo-bot";
        address = "10.0.0.11";
        module = ./containers/nannuo-bot.nix; # Assuming migrated later or existing
        packageArg = "bot-package";
        package = inputs.nannuo-bot.packages.${pkgs.system}.default;
      };
    })
    // (lib.optionalAttrs enableBgsBackend {
      bgs-backend = mkContainer {
        name = "bgs-backend";
        address = "10.0.0.12";
        module = ./containers/bgs-backend.nix; # Assuming migrated later or existing
        packageArg = "backend-package";
        package = inputs.bgs-backend.packages.${pkgs.system}.default;
      };
    })
    // (lib.optionalAttrs enableTestContainer {
      test-container = mkContainer {
        name = "test-container";
        address = "10.0.0.10";
        module = ./containers/test-container.nix;
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
      lib.mapAttrs' mkCaddyEntry proxyEnabledContainers;
  };

  system.stateVersion = "25.11";
}
