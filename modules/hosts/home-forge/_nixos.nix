# Host-private NixOS composition for home-forge: ./default.nix imports it as the
# record's deferred composition, and the underscore prefix keeps it (and every
# sibling fragment) out of discovery.
{
  lib,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../../secrets/hosts/home-forge/system.yaml;

  # Host-owned physical music root; the music aspect derives the storage
  # library contract from it.
  musicStorageRoot = "/srv/storage/media/music";
  # Playlist-sync state lives outside the media library so state and input files
  # never surface as music.
  traktorStateDir = "/srv/data/traktor-m3u-sync";
in
{
  imports = [
    ./_disko-two-disk.nix
  ];

  fleet.foundation = {
    bootLoader = "systemd-boot";
    buildTmpfsSize = "50%";
  };

  # The always-on br0 bridge presents the pinned NIC MAC so the router's DHCP
  # reservation survives; DNS is pinned because there is no split-horizon here.
  fleet.networking = {
    uplink.interface = "eno1";
    bridge = {
      name = "br0";
      macAddress = "84:a9:3e:6b:94:44";
    };
    dns.servers = [
      "1.1.1.1"
      "8.8.8.8"
    ];
  };

  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-000H1_S4GRNX0RA26985";
  # Oversized ESP: room for future boot entries and an ESP backup copy.
  disko-esp-size = "4G";
  disko-second-disk = "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN19040F";

  # Authentication activates only once host secrets exist (two-step sops
  # bootstrap); the tailnet posture comes from the operator-provided auth key.
  sops.defaultSopsFile = ../../../secrets/common.yaml;

  # The physical console is the primary break-glass path; the rescue operator is
  # defense-in-depth and activates once host secrets exist.
  services.hostRecovery = lib.mkIf hasHostSecrets {
    enable = true;
    secretFile = ../../../secrets/hosts/home-forge/system.yaml;
    rescueUser.name = "rescue";
    reboot.onCalendar = "weekly";
  };
  # The backups aspect owns enablement, the secret path, and the bucket; this
  # host declares only the non-default staging root and its own core paths.
  services.state-backups = {
    stagingRoot = "/srv/data/state-backups";
    services.host-core.paths = [ "/etc/ssh" ];
  };

  # Wired but inert until a facter report is captured, so evaluation converges
  # without the file.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;

  services.notification-daemon = {
    secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
    secretFiles.hostSystem = ../../../secrets/hosts/home-forge/system.yaml;
    ntfy.enable = true;
  };

  applications.dj = {
    engine = {
      enable = true;
      inherit traktorStateDir;
      secretFiles.navidrome = ../../../secrets/applications/music.yaml;
    };
  };

  # AudioMuse's database is co-located with its compute: the container reaches
  # this cluster over the Podman bridge, so no cross-host transport is involved
  # and both sides read the password from the music secrets file.
  services.postgres.instances.forge = {
    port = 5432;
    dataDir = "/srv/data/postgres";
  };

  applications.music = {
    dataRoot = "/srv/data";
    storageRoot = musicStorageRoot;
    secretFiles.host = ../../../secrets/applications/music.yaml;
    navidrome.enable = true;
    audiomuse.enable = true;
  };

  services.syncthing.openDefaultPorts = lib.mkForce true;

  system.stateVersion = "25.11";
}
