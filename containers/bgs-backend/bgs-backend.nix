{
  pkgs,
  config,
  containerName,
  containerDomain,
  containerPort,
  ...
}:
let
  bgs-env = "bgs.env";
  db-env = "db.env";
  db-name = "bgs_db";
  db-user = "bgs_db";
in
{
  config = {
    networking.hostName = containerName;

    services.host-proxy = {
      enable = true;
      domain = containerDomain;
      port = containerPort;
    };

    sops = {
      defaultSopsFile = ./secrets.yaml;
      useSystemdActivation = true;
      secrets.git-token = { };
      secrets.bgg-api-key = { };
      secrets.postgres-password = { owner = "postgres"; mode = "0400"; };
      templates.${bgs-env} = {
        mode = "0400";
        content = ''
          GIT_TOKEN=${config.sops.placeholder.git-token}
          BGG_API_KEY=${config.sops.placeholder.bgg-api-key}
        '';
      };
      templates.${db-env} = {
          mode = "0400";
          content = "SPRING_DATASOURCE_PASSWORD=${config.sops.placeholder.postgres-password}\n";
      };
    };

    services.bgs-backend = {
      enable = true;
      envFiles = [
        config.sops.templates.${bgs-env}.path
        config.sops.templates.${db-env}.path
      ];
    };

    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_16;
      ensureDatabases = [ db-name ];
      ensureUsers = [
        {
          name = db-name;
          ensureDBOwnership = true;
        }
      ];
      authentication = pkgs.lib.mkForce ''
        #type     database    DBuser      auth-method [options]
        local     all         all         peer # OS allowed
        host      ${db-name}  ${db-user}  127.0.0.1/32 scram-sha-256
        host      ${db-name}  ${db-user}  ::1/128 scram-sha-256
        host      all         all         127.0.0.1/32 reject
        host      all         all         ::1/128 reject
      '';
    };

    systemd.services.postgresql-setup.postStart = ''
      psql -v ON_ERROR_STOP=1 -v pw="$(cat ${config.sops.secrets.postgres-password.path})" <<'SQL'
        ALTER ROLE ${db-user} WITH PASSWORD :'pw';
      SQL
    '';

    services.postgresqlBackup = {
      enable = true;
      databases = [ db-name ];
      location = "/var/lib/postgresql/backups";
    };

    systemd.services.bgs-backend = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
      serviceConfig = {
        StateDirectory = "bgs-backend/data";
      };
      environment = {
        SPRING_DATASOURCE_URL = "jdbc:postgresql://localhost:5432/${db-name}";
        SPRING_DATASOURCE_USERNAME = db-user;
        PG_HOST = "localhost";
        PG_PORT = "5432";
        PG_DATABASE = db-name;
        DATA_DIR = "/var/lib/bgs-backend/data";
      };
    };
  };
}
