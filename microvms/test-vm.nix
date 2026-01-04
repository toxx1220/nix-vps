{ pkgs, lib, hostBridgeName, hostGatewayIp, ... }: {

  # --- 1. INTERFACE (Options) ---
  options.services.host-proxy = {
    enable = lib.mkEnableOption "host reverse proxy";
    domain = lib.mkOption { type = lib.types.str; };
    port = lib.mkOption { type = lib.types.port; default = 8080; };
  };

  # --- 2. IMPLEMENTATION (Config) ---
  config = {
    services.host-proxy = {
      enable = true;
      domain = "test.local"; # You can change this to your actual domain or test IP
      port = 8080;
    };

    networking.hostName = "test-vm";
    system.stateVersion = "25.11";

    microvm = {
      vcpu = 1;
      mem = 256;
      hypervisor = "qemu";
      interfaces = [ {
        type = "bridge";
        id = "vm-test";
        bridge = hostBridgeName;
        mac = "02:00:00:00:00:02";
      } ];
    };

    # Simple Python Web Server
    systemd.services.test-server = {
      description = "Simple Test Web Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /tmp/web
        echo "<h1>MicroVM is Working!</h1><p>Host: $(hostname)</p><p>IP: $(ip addr show eth0 | grep 'inet ')</p>" > /tmp/web/index.html
        cd /tmp/web
        ${pkgs.python3}/bin/python3 -m http.server 8080
      '';
      serviceConfig = {
        Restart = "always";
        User = "nobody";
      };
    };

    networking.interfaces.eth0.ipv4.addresses = [ {
      address = "10.0.0.20";
      prefixLength = 24;
    } ];
    networking.defaultGateway = {
      address = hostGatewayIp;
      interface = "eth0";
    };
    networking.nameservers = [ "1.1.1.1" ];
  };
}
