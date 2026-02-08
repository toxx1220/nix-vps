{
  config,
  bot-package,
  containerName,
  containerDomain,
  containerPort,
  ...
}:
let
  userName = "nannuo";
in
{
  config = {
    networking.hostName = containerName;

    # Bot doesn't need a public port/proxy usually,
    # but we keep the structure for consistency.
    services.host-proxy = {
      enable = false; # Disabled by default unless you need a dashboard
      domain = containerDomain;
      port = containerPort;
    };

    sops = {
      # Use the secrets from the host repo
      defaultSopsFile = ../secrets.yaml;
      secrets.discord_token = {
        owner = userName;
      };
    };

    users.users.${userName} = {
      isSystemUser = true;
      group = userName;
      description = "${containerName} Service User";
      home = "/var/lib/${containerName}";
      createHome = true;
    };
    users.groups.${userName} = { };

    systemd.services.${containerName} = {
      description = "Nannuoshan Discord Bot";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = userName;
        Group = userName;
        WorkingDirectory = "/var/lib/${containerName}";
        ExecStart = "${bot-package}/bin/${containerName}";

        # Pass the token path to the bot
        Environment = [ "DISCORD_TOKEN_PATH=${config.sops.secrets.discord_token.path}" ];

        Restart = "on-failure";
        RestartSec = "10s";

        # Hardening
        ProtectSystem = "full";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
