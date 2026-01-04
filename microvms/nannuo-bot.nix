{ pkgs, bot-package, ... }: {
  networking.hostName = "nannuo-bot";
  system.stateVersion = "24.11";

  # MicroVM specific settings
  microvm = {
    vcpu = 1;
    mem = 512;
    hypervisor = "qemu";
    interfaces = [ {
      type = "bridge";
      id = "br0";
      mac = "02:00:00:00:00:01";
    } ];
  };

  # Use the package built by the bot's flake
  systemd.services.nannuo-bot = {
    description = "Nannuo Discord Bot";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      # The package provides a binary in /bin/nannuo-bot
      ExecStart = "${bot-package}/bin/nannuo-bot";
      Restart = "always";
      User = "nannuo";
    };
  };

  users.users.nannuo = {
    isSystemUser = true;
    group = "nannuo";
  };
  users.groups.nannuo = {};

  networking.interfaces.eth0.ipv4.addresses = [ {
    address = "10.0.0.10";
    prefixLength = 24;
  } ];
  networking.defaultGateway = "10.0.0.1";
  networking.nameservers = [ "1.1.1.1" ];
}
