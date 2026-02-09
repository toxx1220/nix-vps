{
  config,
  inputs,
  containerName,
  ...
}:
{
  imports = [
    inputs.nannuo-bot.nixosModules.default
  ];

  config = {
    networking.hostName = containerName;

    sops = {
      defaultSopsFile = ../secrets.yaml;
      secrets.discord_token = {
        owner = "nannuo";
      };
    };

    services.nannuo-bot = {
      enable = true;
      tokenFile = config.sops.secrets.discord_token.path;
    };
  };
}
