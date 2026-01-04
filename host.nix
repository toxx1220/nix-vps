{ config, pkgs, lib, inputs, ... }:
let
  user = "toxx";
  sshPort = 6969;

  # --- SERVICE TOGGLES ---
  enableNannuoBot = true;
  enableBgsBackend = true;

  # Helper to define a MicroVM with standard boilerplate
  mkVm = { name, module, packageArg, package }: {
    autostart = true;
    config = {
      imports = [ module inputs.sops-nix.nixosModules.sops ];
      _module.args = {
        inherit inputs;
        ${packageArg} = package;
      };
    };
  };

in {
  networking.hostName = "nixos-vps";
  time.timeZone = "Europe/Berlin";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # User configuration
  users.users = {
    ${user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO"
      ];
    };
    root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO" # TODO: replace?
    ];
  };

  # SSH configuration
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
    ignoreIP = [
      "127.0.0.1/8" # localhost
      "::1"
    ];
    # Initial ban duration: 1 hour
    bantime = "1h";
    # Exponential backoff for repeat offenders
    bantime-increment = {
      enable = true;
      factor = "2"; # Double the ban time each time
      maxtime = "168h"; # Cap at 1 week
    };
  };

  # Networking
  networking = {
    networkmanager.enable = false;
    firewall = {
      enable = true;
      allowedTCPPorts = [ sshPort 443 ];
    };
  };

  networking.bridges."br0".interfaces = [ ];
  networking.interfaces."br0".ipv4.addresses = [{
    address = "10.0.0.1";
    prefixLength = 24;
  }];

  networking.nat = {
    enable = true;
    internalInterfaces = [ "br0" ];
    externalInterface = "eth0";
  };

  # MicroVM Host Configuration, toggle-able inside the module
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
        vm.config.services ? host-proxy && vm.config.services.host-proxy.enable)
        config.microvm.vms;

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

  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # --- CLEAN TMPFILES RULES ---
  # Automatically create data directories for any VM that defines a 'shares' path
  systemd.tmpfiles.rules = let
    # Extract all share sources from all enabled VMs
    allShares = lib.concatMap (vm: map (s: s.source) vm.config.microvm.shares)
      (lib.attrValues config.microvm.vms);
    # Filter only those that are in /var/lib/microvms (to avoid touching system paths)
    vmDataPaths =
      lib.filter (path: lib.hasPrefix "/var/lib/microvms" path) allShares;
    # Create a rule for each path.
    # Note: Use 0755 and root:root by default, but Postgres paths might need 0700 and UID 71.
    mkRule = path: "d ${path} 0755 root root -";
  in map mkRule vmDataPaths ++ [
    # Specific override for Postgres data (needs strict permissions)
    "d /var/lib/microvms/bgs-backend/data 0700 71 71 -"
  ];

  environment.systemPackages = with pkgs; [ micro btop tree git ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
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

  system.stateVersion = "25.11";
}
