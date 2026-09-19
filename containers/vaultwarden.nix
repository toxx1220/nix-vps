{
  pkgs,
  config,
  containerName,
  containerDomain,
  containerPort,
  ...
}:
let
  vaultwarden-path = "/var/lib/vaultwarden";
  backup-file = "${vaultwarden-path}/backups/db-latest.sqlite3";
in
{
  config = {
    networking.hostName = containerName;

    services.host-proxy = {
      enable = true;
      enableAuth = true;
      skipAuthRoutes = [
        "/api/*"
        "/identity/*"
        "/notifications/hub*"
        "/vw_sync"
      ];
      domain = containerDomain;
      port = containerPort;
    };

    sops = {
      defaultSopsFile = ../secrets.yaml;
      useSystemdActivation = true;
      secrets.vault-admin-token = { };
      templates."vaultwarden.env" = {
        owner = "vaultwarden";
        group = "vaultwarden";
        content = ''
          ADMIN_TOKEN=${config.sops.placeholder."vault-admin-token"}
        '';
      };
      secrets.borgbase-ssh-key = { };
      secrets.borgbase-enc-key = { };
    };

    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite";
      environmentFile = config.sops.templates."vaultwarden.env".path;
      config = {
        DOMAIN = "https://${containerDomain}";
        SIGNUPS_ALLOWED = false;
        INVITATIONS_ALLOWED = false;
        ROCKET_ADDRESS = "0.0.0.0";
        ROCKET_PORT = containerPort;
      };
    };

    systemd.services = {
      vaultwarden = {
        after = [ "sops-install-secrets.service" ];
        requires = [ "sops-install-secrets.service" ];
      };
      borgbackup-job-borgbase.path = [ pkgs.sqlite ];
    };

    programs.ssh.knownHosts."ok3apsyr.repo.borgbase.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMS3185JdDy7ffnr0nLWqVy8FaAQeVh1QYUSiNpW5ESq";

    services.borgbackup.jobs.borgbase = {
      repo = "ssh://ok3apsyr@ok3apsyr.repo.borgbase.com/./repo";
      paths = [
        vaultwarden-path
      ];
      exclude = [
        "*/db.sqlite3*"
        "*/tmp"
        "*/icon_cache"
      ];
      preHook = ''
        mkdir -p ${vaultwarden-path}/backups
        rm -f ${backup-file}
        sqlite3 ${vaultwarden-path}/db.sqlite3 \
        "VACUUM INTO '${backup-file}'"
      '';
      postHook = "rm -f ${backup-file}";
      readWritePaths = [ vaultwarden-path ];
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.sops.secrets.borgbase-enc-key.path}";
      };
      environment.BORG_RSH = "ssh -i ${config.sops.secrets.borgbase-ssh-key.path}";
      compression = "auto,zstd";
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };
      startAt = "daily";
      persistentTimer = true;
      doInit = true;
    };
  };
}
