{
  pkgs,
  backend-package,
  config,
  inputs,
  containerName,
  containerDomain,
  containerPort,
  ...
}:

# TODO: ONLY A DRAFT
{
  config = {
    networking.hostName = containerName;

    services.host-proxy = {
      enable = true;
      domain = containerDomain;
      port = containerPort;
    };

    sops = {
      defaultSopsFile = "${inputs.bgs-backend}/secrets.yaml";
      age.keyFile = "/var/lib/sops-nix/key.txt";
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

    systemd.services.bgs-backend = {
      description = "BGS Kotlin Backend";
      after = [
        "postgresql.service"
        "network.target"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${backend-package}/bin/bgs-backend";
        User = "bgs-app";
        Restart = "always";
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

    users.users.bgs-app = {
      isSystemUser = true;
      group = "bgs-app";
    };
    users.groups.bgs-app = { };
  };
}
