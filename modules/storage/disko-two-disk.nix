{ lib, config, ... }:
{
  options."disko-second-disk" = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Stable by-id device for the optional bulk-storage disk (e.g. \"/dev/disk/by-id/...\"). Null disables the storage disk.";
  };

  options."disko-esp-size" = lib.mkOption {
    type = lib.types.str;
    default = "512M";
    description = "Size for the EFI system partition (e.g. \"512M\", \"4G\").";
  };

  options."disko-storage-size" = lib.mkOption {
    type = lib.types.str;
    default = "100%";
    description = "Size for the bulk-storage partition (e.g. \"100%\", \"2T\").";
  };

  options."disko-storage-mountpoint" = lib.mkOption {
    type = lib.types.str;
    default = "/srv/storage";
    description = "Mount point for the bulk-storage filesystem.";
  };

  config.disko.devices.disk.main = {
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = lib.mkDefault config.disko-esp-size;
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "rootfs"
            ];
            mountpoint = "/";
          };
        };
      };
    };
  };

  config.disko.devices.disk.storage = lib.mkIf (config.disko-second-disk != null) {
    type = "disk";
    device = config.disko-second-disk;
    content = {
      type = "gpt";
      partitions = {
        storage = {
          size = config.disko-storage-size;
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "srv-storage"
            ];
            mountpoint = config.disko-storage-mountpoint;
            mountOptions = [
              "nofail"
              "x-systemd.device-timeout=10s"
            ];
          };
        };
      };
    };
  };

  # Root-backed directories for service-state and the Nix store on the root
  # filesystem, matching the established tmpfiles pattern (no partitions).
  config.systemd.tmpfiles.rules = [
    "d /srv/data 0755 root root - -"
    "d /nix 0755 root root - -"
  ];
}
