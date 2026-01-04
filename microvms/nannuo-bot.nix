{ pkgs, bot-package, config, inputs, hostBridgeName, ... }: {
  config = {
    networking.hostName = "nannuo-bot";

    # Hybrid Secrets Setup
    sops = {
      defaultSopsFile = "${inputs.nannuo-bot}/secrets.yaml";
      age.keyFile = "/var/lib/sops-nix/key.txt";
      secrets.bot_env = { };
    };

    microvm = {
      # Default vCPU and memory from common.nix
      interfaces = [{
        type = "bridge";
        id = "vm-nannuo";
        bridge = hostBridgeName;
        mac = "02:00:00:00:00:01";
      }];
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

    users.users.nannuo = {
      isSystemUser = true;
      group = "nannuo";
    };
    users.groups.nannuo = { };

    networking.interfaces.eth0.ipv4.addresses = [{
      address = "10.0.0.10";
      prefixLength = 24;
    }];
  };
}
