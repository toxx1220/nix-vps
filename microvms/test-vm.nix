{ pkgs, hostBridgeName, ... }: {
  config = {
    networking.hostName = "test-vm";

    services.host-proxy = {
      enable = true;
      domain = "test.local";
      port = 8080;
    };

    microvm = {
      interfaces = [{
        type = "bridge";
        id = "vm-test";
        bridge = hostBridgeName;
        mac = "02:00:00:00:00:02";
      }];
    };

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

    networking.interfaces.eth0.ipv4.addresses = [{
      address = "10.0.0.20";
      prefixLength = 24;
    }];
  };
}
