{ lib, hostGatewayIp, ... }: {
  # Shared options for host reverse proxy
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Guest / VM port, where service is running";
    };
    hostPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Port on host for user-mode networking (SLIRP). If set, Caddy proxies to 127.0.0.1:hostPort.";
    };
  };

  # Shared configuration
  config = {
    system.stateVersion = "25.11";

    networking.nameservers = [ "1.1.1.1" ];
    # Default gateway for bridge/tap networking; user-mode VMs override with mkForce null
    networking.defaultGateway = lib.mkDefault {
      address = hostGatewayIp;
      interface = "eth0";
    };

    microvm = {
      vcpu = lib.mkDefault 1; # Can be overridden.
      mem = lib.mkDefault 512;
      hypervisor = "qemu";
      # TCG (software emulation) for VPS without nested virtualization
      cpu = "max";
      qemu.machineOpts = {
        accel = "tcg";
        gic-version = "max";  # Required for aarch64
      };
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
