{ config, pkgs, lib, inputs, ... }:
let
  user = "toxx";
  sshPort = 22; # TODO: change?
  hostName = "oracle-vps";

  # --- SERVICE TOGGLES ---
  enableNannuoBot = false;
  enableBgsBackend = false;
  enableTestVm = true;

  networkBridgeName = "br0";
  gatewayIp = "10.0.0.1";

  # Helper to define a MicroVM with standard boilerplate
  mkVm = { name, module, packageArg ? null, package ? null }: {
    autostart = true;
    config = {
      imports =
        [ ./microvms/common.nix module inputs.sops-nix.nixosModules.sops ];
      _module.args = {
        inherit inputs;
        hostBridgeName = networkBridgeName;
        hostGatewayIp = gatewayIp;
      } // (lib.optionalAttrs (packageArg != null) {
        ${packageArg} = package;
      });
    };
  };

in {
  networking.hostName = hostName;
  time.timeZone = "Europe/Berlin";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" "virtio_scsi" "virtio_net" ];
  boot.kernelParams = [ "console=ttyS0" ];
  # Force permissions on persistent keys before the root fs is even mounted
  boot.initrd.postMountCommands = ''
    mkdir -p /mnt-root/persistent/etc/ssh
    chmod 600 /mnt-root/persistent/etc/ssh/ssh_host_ed25519_key
  '';

  environment.systemPackages = with pkgs; [ micro btop tree git uwufetch ];

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
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
    # Look in both paths to ensure the first boot works even if
    # the bind-mount hasn't initialized yet.
    age.sshKeyPaths = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/persistent/etc/ssh/ssh_host_ed25519_key"
    ];
    secrets = {
      user-password.neededForUsers = true;
      root-password.neededForUsers = true;
    };
  };

  # This stays persistent
  fileSystems."/persistent".neededForBoot = true;
  environment.persistence."/persistent" = {
    hideMounts = true;
    directories = [
      "/var/log"               # System logs
      "/var/lib/nixos"         # UID/GID maps (prevents permission issues)
      "/var/lib/systemd/coredump"
      "/var/lib/microvms"      # VM disk images and shared data
      "/var/lib/caddy"         # SSL certificates
      "/var/lib/fail2ban"      # Ban history
      {
        directory = "/etc/ssh";
        mode = "0755";
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
      AllowUsers = [ "root" user ];
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    ignoreIP = [ # ignore localhost
      "127.0.0.1/8"
      "::1"
    ];
    bantime = "1h"; # initial
    bantime-increment = {
      enable = true;
      factor = "2"; # Doubline -> exponential
      maxtime = "168h"; # Cap at 1 week
    };
  };

  networking = {
    useDHCP = true;
    networkmanager.enable = false;
    firewall = {
      enable = true;
      allowedTCPPorts = [ sshPort 80 443 ];
    };

    # microVM setup
    bridges.${networkBridgeName}.interfaces = [ ];
    interfaces.${networkBridgeName}.ipv4.addresses = [{
      address = "10.0.0.1";
      prefixLength = 24;
    }];
    nat = {
      enable = true;
      internalInterfaces = [ networkBridgeName ];
      externalInterface =
        "enp0s6"; # TODO: Can differ depending on the VPS provider
    };
  };

  # MicroVM Host Configuration, toggle-able via the flags at the top
  microvm.vms = (lib.optionalAttrs enableNannuoBot {
    nannuo-bot = mkVm {
      name = "nannuo-bot";
      module = ./microvms/nannuo-bot.nix;
      packageArg = "bot-package";
      package = inputs.nannuo-bot.packages.${pkgs.system}.default;
    };
  }) // (lib.optionalAttrs enableBgsBackend {
    bgs-backend = mkVm {
      name = "bgs-backend";
      module = ./microvms/bgs-backend.nix;
      packageArg = "backend-package";
      package = inputs.bgs-backend.packages.${pkgs.system}.default;
    };
  }) // (lib.optionalAttrs enableTestVm {
    test-vm = mkVm {
      name = "test-vm";
      module = ./microvms/test-vm.nix;
    };
  });

  # Dynamic Caddy Configuration
  services.caddy = {
    enable = true;
    # Generate 'virtualHosts' attribute set dynamically
    virtualHosts = let
      # 1. Filter the list of all MicroVMs.
      # 'lib.filterAttrs' takes a function that returns true/false.
      # '?' is the "has attribute" operator. We check if 'host-proxy' exists in the VM config.
      proxyEnabledVms = lib.filterAttrs (name: vm:
        (vm.config.services or { }) ? host-proxy
        && (vm.config.services.host-proxy.enable or false)) config.microvm.vms;

      # 2. Map the filtered VMs into Caddy virtualHost entries.
      # 'lib.mapAttrs'' (note the prime ') allows to change both the KEY and the VALUE.
      # KEY = domain name, VALUE = proxy config.
      mkCaddyEntry = name: vm: {
        name =
          vm.config.services.host-proxy.domain; # New Key: e.g. "api.example.com"
        value = { # New Value: Caddy config
          # Get the first IP address defined in the VM
          extraConfig = let
            vmIp = (lib.head
              vm.config.networking.interfaces.eth0.ipv4.addresses).address;
            vmPort = toString vm.config.services.host-proxy.port;
          in ''
            log {
              output file /var/log/caddy/${name}.log
            }
            reverse_proxy ${vmIp}:${vmPort}
          '';
        };
      };
    in lib.mapAttrs' mkCaddyEntry proxyEnabledVms;
  };

  # --- CLEAN TMPFILES RULES ---
  # Automatically create data directories for any VM that defines a 'shares' path
  systemd.tmpfiles.rules = let
    # Extract all share sources from all enabled VMs
    allShares = lib.concatMap (vm:
      if vm.config ? microvm then
        map (s: s.source) vm.config.microvm.shares
      else [ ]) (lib.attrValues config.microvm.vms);
    # Filter only those that are in /var/lib/microvms (to avoid touching system paths)
    vmDataPaths =
      lib.filter (path: lib.hasPrefix "/var/lib/microvms" path) allShares;
    # Create a rule for each path.
    # Note: Use 0755 and root:root by default, but Postgres paths might need 0700 and UID 71.
    mkRule = path: "d ${path} 0755 root root -";
  in [
    "d /var/lib/microvms/sops-shared 0755 root root -"
    "L+ /var/lib/microvms/sops-shared/key.txt - - - - /etc/ssh/ssh_host_ed25519_key"
  ] ++ map mkRule vmDataPaths ++ [
    # Specific override for Postgres data (needs strict permissions) # TODO: remove?
    "d /var/lib/microvms/bgs-backend/data 0700 71 71 -"
  ];

  system.stateVersion = "25.11";
}
