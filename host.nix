{ config, pkgs, lib, inputs, ... }:
let
  user = "toxx";
  sshPort = 6969;

  # --- SERVICE TOGGLES ---
  # Set these to false to temporarily disable a service
  enableNannuoBot = true;
  enableBgsBackend = true;
in {
  networking.hostName = "nixos-vps";
  time.timeZone = "Europe/Berlin";

  # Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # User configuration
  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO"
    ];
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    ports = [ sshPort ];
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Networking
  networking.firewall.allowedTCPPorts = [ 80 443 sshPort ];
  
  # Bridge for MicroVMs
  networking.bridges."br0".interfaces = [ ];
  networking.interfaces."br0".ipv4.addresses = [ {
    address = "10.0.0.1";
    prefixLength = 24;
  } ];

  # Enable NAT for MicroVMs to access internet
  networking.nat = {
    enable = true;
    internalInterfaces = [ "br0" ];
    externalInterface = "eth0";
  };

  # MicroVM Host Configuration
  microvm.vms = 
    (lib.optionalAttrs enableNannuoBot {
      nannuo-bot = {
        autostart = true;
        config = {
          imports = [ ./microvms/nannuo-bot.nix ];
          _module.args.bot-package = inputs.nannuo-bot.packages.${pkgs.system}.default;
        };
      };
    }) // 
    (lib.optionalAttrs enableBgsBackend {
      bgs-backend = {
        autostart = true;
        config = {
          imports = [ ./microvms/bgs-backend.nix ];
          _module.args.backend-package = inputs.bgs-backend.packages.${pkgs.system}.default;
        };
      };
    });

  # Dynamic Caddy Configuration
  services.caddy = {
    enable = true;
    virtualHosts = let
      proxyEnabledVms = lib.filterAttrs (name: vm:
        vm.config.services ? host-proxy && vm.config.services.host-proxy.enable
      ) config.microvm.vms;

      mkCaddyEntry = name: vm: {
        name = vm.config.services.host-proxy.domain;
        value = {
          extraConfig = let
            vmIp = (lib.head vm.config.networking.interfaces.eth0.ipv4.addresses).address;
            vmPort = toString vm.config.services.host-proxy.port;
          in ''
            reverse_proxy ${vmIp}:${vmPort}
          '';
        };
      };
    in
      lib.mapAttrs' mkCaddyEntry proxyEnabledVms;
  };

  # Sops configuration
  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # Ensure MicroVM data directories exist
  systemd.tmpfiles.rules = [
    "d /var/lib/microvms/bgs-backend/data 0700 71 71 -"
  ];

  environment.systemPackages = with pkgs; [ micro btop tree git ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.11";
}
