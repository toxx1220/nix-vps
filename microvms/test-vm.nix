{ pkgs, lib, ... }: {
  config = {
    networking.hostName = "test-vm";

    services.host-proxy = {
      enable = true;
      domain = "oracle.toxx.dev";
      port = 8080;
      hostPort = 10020;
    };

    microvm = {
      # User-mode (SLIRP) networking - works with QEMU TCG without KVM
      interfaces = [{
        type = "user";
        id = "usernet";
        mac = "02:00:00:00:00:02";
      }];

      forwardPorts = [{
        from = "host";
        host.port = 10020;
        guest.port = 8080;
      }];

      socket = "control.socket";
    };

    # Simple test web server
    systemd.services.test-server = {
      description = "Simple Test Web Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 ];  # For ip command
      script = ''
        mkdir -p /tmp/web
        echo "<h1>MicroVM is Working!</h1><p>Host: $(hostname)</p><p>IP: $(ip -4 addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+')</p><p>Date: $(date)</p>" > /tmp/web/index.html
        cd /tmp/web
        ${pkgs.python3}/bin/python3 -m http.server 8080 --bind 0.0.0.0
      '';
      serviceConfig.Restart = "always";
    };

    # User-mode networking uses DHCP from SLIRP
    networking.useDHCP = true;
    networking.defaultGateway = lib.mkForce null;
    networking.firewall.enable = false;
  };
}
