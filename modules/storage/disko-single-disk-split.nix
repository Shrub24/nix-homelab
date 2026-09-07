{ lib, config, ... }:
{
  options = {
    "disko-root-extra" = lib.mkOption {
      type = lib.types.str;
      default = "20G";
      description = "Size for the root partition on single-disk split hosts.";
    };

    "disko-data-size" = lib.mkOption {
      type = lib.types.str;
      default = "28G";
      description = "Size for the /srv/data partition on single-disk split hosts.";
    };

    "disko-nix-size" = lib.mkOption {
      type = lib.types.str;
      default = "45G";
      description = "Size for the /nix partition on single-disk split hosts.";
    };
  };

  config.disko.devices.disk.main = {
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        bios_grub = {
          size = "1M";
          type = "EF02";
        };

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

        root = {
          size = lib.mkDefault config.disko-root-extra;
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

        data = {
          size = lib.mkDefault config.disko-data-size;
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "srv-data"
            ];
            mountpoint = "/srv/data";
            mountOptions = [
              "nofail"
              "x-systemd.device-timeout=10s"
            ];
          };
        };

        nix = {
          size = lib.mkDefault config.disko-nix-size;
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "nix"
            ];
            mountpoint = "/nix";
          };
        };

        media = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "srv-media"
            ];
            mountpoint = "/srv/media";
            mountOptions = [
              "nofail"
              "x-systemd.device-timeout=10s"
            ];
          };
        };
      };
    };
  };
}
