{ config, pkgs, lib, inputs, ... }:
let
  user = "toxx";
  sshPort = 6969;
in {
  networking.hostName = "nixos-vps";
  time.timeZone = "Europe/Berlin";

  # ... (SSH and Bootloader config omitted for brevity, keeping them in the actual file)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  users.users.${user} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEdkWwiBoThxsipUqiK6hPXLn4KxI5GstfLJaE4nbjMO"
    ];
  };

  services.openssh = {
    enable = true;
    ports = [ sshPort ];
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 sshPort ];
  
  networking.bridges."br0".interfaces = [ ];
  networking.interfaces."br0".ipv4.addresses = [ {
    address = "10.0.0.1";
    prefixLength = 24;
  } ];

  networking.nat = {
    enable = true;
    internalInterfaces = [ "br0" ];
    externalInterface = "eth0";
  };

  microvm.vms = {
    nannuo-bot = {
      autostart = true;
      config = {
        imports = [ ./microvms/nannuo-bot.nix ];
        _module.args.bot-package = inputs.nannuo-bot.packages.${pkgs.system}.default;
      };
    };
    bgs-backend = {
      autostart = true;
      config = {
        imports = [ ./microvms/bgs-backend.nix ];
        _module.args.backend-package = inputs.bgs-backend.packages.${pkgs.system}.default;
      };
    };
  };

  # --- DYNAMIC CADDY CONFIGURATION ---
  services.caddy = {
    enable = true;
    
    # We generate the 'virtualHosts' attribute set dynamically
    virtualHosts = let
      # 1. Filter the list of all MicroVMs.
      # 'lib.filterAttrs' takes a function that returns true/false.
      # '?' is the "has attribute" operator. We check if 'host-proxy' exists in the VM config.
      proxyEnabledVms = lib.filterAttrs (name: vm:
        vm.config.services ? host-proxy && vm.config.services.host-proxy.enable
      ) config.microvm.vms;

      # 2. Map the filtered VMs into Caddy virtualHost entries.
      # 'lib.mapAttrs'' (note the prime ') allows us to change both the KEY and the VALUE.
      # We want the KEY to be the domain name, and the VALUE to be the proxy config.
      mkCaddyEntry = name: vm: {
        name = vm.config.services.host-proxy.domain; # New Key: e.g. "api.example.com"
        value = {                                    # New Value: Caddy config
          extraConfig = let
            # Get the first IP address defined in the VM
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

  sops = {
    defaultSopsFile = ./secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/microvms/bgs-backend/data 0700 71 71 -"
  ];

  environment.systemPackages = with pkgs; [ micro btop tree git ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "24.11";
}