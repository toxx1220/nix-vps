{
  device ? "/dev/sda",
  ...
}:
{
  disko.devices = {
    # nodev defines filesystems that aren't tied to a physical partition.
    # Mount root (/) as a tmpfs (RAM disk).
    # Everything not explicitly persisted is wiped on every reboot.
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=1G"
        "mode=755"
      ];
    };
    disk.main = {
      inherit device;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          # Nix store needs to be kept
          nix = {
            size = "80G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/nix";
            };
          };
          # Other data that needs to survive reboot
          persistent = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/persistent";
            };
          };
        };
      };
    };
  };
}
