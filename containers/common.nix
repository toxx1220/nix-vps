{
  lib,
  containerPort,
  containerGateway,
  ...
}:
{
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    enableAuth = lib.mkEnableOption "OAuth2 Proxy Authentication";
    skipAuthRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of path patterns to bypass authentication for.";
    };
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };
  };

  config = {
    system.stateVersion = "25.11";

    networking = {
      nameservers = [ "1.1.1.1" ];

      nftables.enable = true;
      firewall = {
        enable = true;
        extraInputRules = lib.optionalString (containerPort != 0) ''
          ip saddr ${containerGateway} tcp dport ${toString containerPort} accept
        '';
      };
    };
  };
}
