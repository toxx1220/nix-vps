{
  config,
  containerName,
  containerDomain,
  containerPort,
  ...
}:
let
  admin = "toxx-admin";
  user1 = "toxx";
  user2 = "user";
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
      secrets.ntfy-admin-password-hash = { };
      secrets.ntfy-user1-password-hash = { };
      secrets.ntfy-user2-password-hash = { };
      secrets.ntfy-user1-token = { };
      templates.${envFile} = {
        mode = "0444";
        content = ''
          NTFY_AUTH_USERS=${admin}:${config.sops.placeholder.ntfy-admin-password-hash}:admin,${user1}:${config.sops.placeholder.ntfy-user1-password-hash}:user,${user2}:${config.sops.placeholder.ntfy-user2-password-hash}:user
          NTFY_AUTH_TOKENS=${user1}:${config.sops.placeholder.ntfy-user1-token}:user1
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
        auth-access = [
          "${user1}:*:rw"
          "${user2}:*:rw"
        ];
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
