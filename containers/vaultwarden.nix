{
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
      secrets.vault-admin-token = { };
      templates."vaultwarden.env" = {
        owner = "vaultwarden";
        group = "vaultwarden";
        content = ''
          ADMIN_TOKEN=${config.sops.placeholder."vault-admin-token"}
        '';
      };
    };

    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite";
      environmentFile = config.sops.templates."vaultwarden.env".path;
      config = {
        DOMAIN = "https://${containerDomain}";
        SIGNUPS_ALLOWED = false;
        INVITATIONS_ALLOWED = false;
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = containerPort;
      };
    };

    systemd.services.vaultwarden = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
    };

  };
}
