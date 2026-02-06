{
  lib,
  ...
}:
{
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };
  };

  config = {
    system.stateVersion = "25.11";

    networking.nameservers = [ "1.1.1.1" ];
    networking.firewall.enable = false;

    # Shared SOPS key setup for containers
    # We bind mount the key from the host to this specific path
    sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  };
}
