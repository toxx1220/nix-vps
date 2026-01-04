{ pkgs, bot-package, lib, inputs, hostBridgeName, hostGatewayIp, ... }: {

  # --- 1. INTERFACE (Options) ---
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption { type = lib.types.port; default = 8080; };
  };

  # --- 2. IMPLEMENTATION (Config) ---
  config = {
    # Disable proxy by default for the bot unless you need a dashboard/webhook
    services.host-proxy.enable = false;

    networking.hostName = "nannuo-bot";
    system.stateVersion = "25.11";

    # Hybrid Secrets Setup
    sops = {
      defaultSopsFile = "${inputs.nannuo-bot}/secrets.yaml";
      age.keyFile = "/var/lib/sops-nix/key.txt";
      secrets.bot_env = {};
    };

    microvm = {
      vcpu = 1;
      mem = 512;
      hypervisor = "qemu";
      interfaces = [ {
        type = "bridge";
        id = "vm-nannuo";
        bridge = hostBridgeName;
        mac = "02:00:00:00:00:01";
      } ];
      shares = [
        # SHARE THE HOST KEY
        {
          source = "/var/lib/sops-nix/key.txt";
          mountPoint = "/var/lib/sops-nix/key.txt";
          tag = "sops-key";
          proto = "virtiofs";
        }
      ];
    };

    systemd.services.nannuo-bot = {
      description = "Nannuo Discord Bot";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${bot-package}/bin/nannuo-bot";
        Restart = "always";
        User = "nannuo";
        EnvironmentFile = config.sops.secrets.bot_env.path;
      };
    };

    users.users.nannuo = { isSystemUser = true; group = "nannuo"; };
    users.groups.nannuo = {};

    networking.interfaces.eth0.ipv4.addresses = [ {
      address = "10.0.0.10";
      prefixLength = 24;
    } ];
    networking.defaultGateway = {
      address = hostGatewayIp;
      interface = "eth0";
    };
    networking.nameservers = [ "1.1.1.1" ];
  };
}