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
      useSystemdActivation = true;
      secrets.bgs_env = { };
    };

    services.bgs-backend = {
      enable = true;
      envFile = config.sops.secrets.bgs_env.path;
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [ "bgs_db" ];
      ensureUsers = [
        {
          name = "bgs_db";
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

    systemd.services.bgs-backend = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
      serviceConfig = {
        StateDirectory = "bgs-backend/data";
      };
      environment = {
        SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/bgs_db";
        SPRING_DATASOURCE_USERNAME = "bgs_db";
        SPRING_DATASOURCE_PASSWORD = "";
        PG_HOST = "localhost";
        PG_PORT = "5432";
        PG_DATABASE = "bgs_db";
        DATA_DIR = "/var/lib/bgs-backend/data";
      };
    };
  };
}
