{
  pkgs,
  config,
  containerName,
  containerDomain,
  containerPort,
  ...
}:
let
  user = "toxx";
  envFile = "${containerName}.env";
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
      defaultSopsFile = ../secrets.yaml;
      useSystemdActivation = true;
      secrets.ntfy-password-hash = { };
      secrets.ntfy-app-token = { };
      templates.${envFile} = {
        mode = "0444";
        content = ''
          NTFY_AUTH_USERS=${user}:${config.sops.placeholder.ntfy-password-hash}:admin
          NTFY_AUTH_TOKENS=${user}:${config.sops.placeholder.ntfy-app-token}:app
        '';
      };
    };

    services.ntfy-sh = {
      enable = true;
      environmentFile = config.sops.templates.${envFile}.path;
      settings = {
        base-url = "https://${containerDomain}";
        listen-http = "0.0.0.0:${toString containerPort}";
        behind-proxy = true;
        auth-default-access = "deny-all";
        enable-signup = false;
        enable-login = true;
      };
    };

    systemd.services.ntfy-sh = {
      after = [ "sops-install-secrets.service" ];
      requires = [ "sops-install-secrets.service" ];
    };
  };
}
