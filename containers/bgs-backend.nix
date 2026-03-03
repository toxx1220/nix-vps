{
  pkgs,
  config,
  containerName,
  containerDomain,
  containerPort,
  ...
}:

{
  config = {
    networking.hostName = containerName;

    services.host-proxy = {
      enable = true;
      domain = containerDomain;
      port = containerPort;
    };

    sops = {
      defaultSopsFile = ../secrets.yaml;
      secrets.bgs_env = { };
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [ "bgs_db" ];
      ensureUsers = [
        {
          name = "bgs_user";
          ensureDBOwnership = true;
        }
      ];
      authentication = pkgs.lib.mkForce ''
        local all all trust
        host all all 127.0.0.1/32 trust
      '';
    };

    services.postgresqlBackup = {
      enable = true;
      databases = [ "bgs_db" ];
      location = "/var/lib/postgresql/backups";
    };

    services.bgs-backend = {
      enable = true;
      envFile = config.sops.secrets.bgs_env.path;
    };

    systemd.services.bgs-backend = {
      environment = {
        SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/bgs_db";
        SPRING_DATASOURCE_USERNAME = "bgs_user";
        PG_HOST = "localhost";
        PG_PORT = "5432";
        PG_DATABASE = "bgs_db";
        DATA_DIR = "/var/lib/bgs-backend";
      };
    };
  };
}
