{ lib, hostBridgeName, hostGatewayIp, ... }: {
  # Shared options
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
    };
  };

  # Shared configuration
  config = {
    system.stateVersion = "25.11";

    networking.nameservers = [ "1.1.1.1" ];
    networking.defaultGateway = {
      address = hostGatewayIp;
      interface = "eth0";
    };

    microvm = {
      vcpu = lib.mkDefault 1; # Can be overridden.
      mem = lib.mkDefault 512;
      hypervisor = "qemu";
      # Shared SOPS key
      shares = [{
        source = "/var/lib/microvms/sops-shared";
        mountPoint = "/var/lib/sops-nix";
        tag = "sops-key";
        proto = "virtiofs";
      }];
    };
  };
}
