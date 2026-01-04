{ pkgs, backend-package, lib, inputs, ... }: {

  # --- 1. INTERFACE (Options) ---
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption { type = lib.types.port; default = 8080; };
  };

  # --- 2. IMPLEMENTATION (Config) ---
  config = {
    services.host-proxy = {
      enable = true;
      domain = "api.yourdomain.com";
      port = 8080;
    };

    networking.hostName = "bgs-backend";
    system.stateVersion = "25.11";

    # Hybrid Secrets Setup
    sops = {
      # Pull secrets from the service's own repository!
      defaultSopsFile = "${inputs.bgs-backend}/secrets.yaml";
      # Use the host's key (shared via microvm.shares below)
      age.keyFile = "/var/lib/sops-nix/key.txt";
      
      secrets.bgs_env = {
        # This secret should contain the entire EnvironmentFile content
        # or you can define individual secrets.
      };
    };

    microvm = {
      vcpu = 2;
      mem = 2048;
      hypervisor = "qemu";
      interfaces = [ {
        type = "bridge";
        id = "br0";
        mac = "02:00:00:00:00:02";
      } ];
      shares = [
        {
          source = "/var/lib/microvms/bgs-backend/data";
          mountPoint = "/var/lib/postgresql";
          tag = "db-data";
          proto = "virtiofs";
        }
        # SHARE THE HOST KEY: This allows the VM to decrypt its secrets
        {
          source = "/var/lib/sops-nix/key.txt";
          mountPoint = "/var/lib/sops-nix/key.txt";
          tag = "sops-key";
          proto = "virtiofs";
        }
      ];
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [ "bgs_db" ];
      ensureUsers = [ { name = "bgs_user"; ensureDBOwnership = true; } ];
      authentication = pkgs.lib.mkForce ''
        local all all trust
        host all all 127.0.0.1/32 trust
      '';
    };

    systemd.services.bgs-backend = {
      description = "BGS Kotlin Backend";
      after = [ "postgresql.service" "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${backend-package}/bin/bgs-backend";
        User = "bgs-app";
        Restart = "always";
        # Use the decrypted secret as an environment file
        EnvironmentFile = config.sops.secrets.bgs_env.path;
        Environment = [
          "SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/bgs_db"
          "SPRING_DATASOURCE_USERNAME=bgs_user"
          "PG_HOST=localhost"
          "PG_PORT=5432"
          "PG_DATABASE=bgs_db"
        ];
      };
    };

    users.users.bgs-app = { isSystemUser = true; group = "bgs-app"; };
    users.groups.bgs-app = {};

    networking.interfaces.eth0.ipv4.addresses = [ {
      address = "10.0.0.11";
      prefixLength = 24;
    } ];
    networking.defaultGateway = "10.0.0.1";
    networking.nameservers = [ "1.1.1.1" ];
  };
}