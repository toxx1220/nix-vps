{ pkgs, backend-package, lib, ... }: {

  # --- 1. INTERFACE (Options) ---
  # This defines NEW settings that this file can accept.
  # It's like defining a "schema" for this MicroVM.
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    
    domain = lib.mkOption {
      type = lib.types.str;
      description = "The public domain name (e.g. api.example.com)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "The internal port the app listens on";
    };
  };

  # --- 2. IMPLEMENTATION (Config) ---
  # This is where we actually set the values and define the system.
  config = {
    # We enable our own custom option here
    services.host-proxy = {
      enable = true;
      domain = "api.yourdomain.com";
      port = 8080;
    };

    networking.hostName = "bgs-backend";
    system.stateVersion = "24.11";

    microvm = {
      vcpu = 2;
      mem = 2048;
      hypervisor = "qemu";
      interfaces = [ {
        type = "bridge";
        id = "br0";
        mac = "02:00:00:00:00:02";
      } ];
      shares = [ {
        source = "/var/lib/microvms/bgs-backend/data";
        mountPoint = "/var/lib/postgresql";
        tag = "db-data";
        proto = "virtiofs";
      } ];
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
