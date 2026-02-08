{
  pkgs,
  containerName,
  containerDomain,
  containerPort,
  ...
}:
{
  config = {
    networking.hostName = containerName;

    services.host-proxy = {
      enable = true;
      domain = containerDomain;
      port = containerPort;
    };

    systemd.services.test-server = {
      description = "Simple Test Web Server";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 ];
      script = ''
        mkdir -p /tmp/web
        echo "<h1>NixOS Container is Working!</h1><p>Host: $(hostname)</p><p>IP: $(ip -4 addr show eth0 2>/dev/null | grep -oP 'inet \K[\d.]+')</p><p>Date: $(date)</p>" > /tmp/web/index.html
        cd /tmp/web
        ${pkgs.python3}/bin/python3 -m http.server 8080 --bind 0.0.0.0
      '';
      serviceConfig.Restart = "always";
    };
  };
}
