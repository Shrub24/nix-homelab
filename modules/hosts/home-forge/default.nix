{
  lib,
  config,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../../secrets/hosts/home-forge/system.yaml;

  # Host-owned physical music root; the DJ application injects it as the
  # guest's M: share.
  musicStorageRoot = "/srv/storage/media/music";
  # Playlist-sync worker state (SQLite store + inbound M3U drop), outside the
  # media library so state/input files never surface as music.
  traktorStateDir = "/srv/data/traktor-m3u-sync";
in
{
  imports = [
    # Deferred raw leaves (FND-6): explicit host composition until each focused
    # ownership change; the foundation aspects above arrive via the registry.
    ../../../modules/shared/niks3-post-deploy.nix
    ../../../modules/shared/niks3-upload-client.nix
    ../../../modules/shared/nixbuild-ssh.nix
    ../../../modules/services/beszel-agent-auth.nix
    ../../../modules/services/state-backups.nix
    ../../../modules/shared/web-policy.nix
    ../../../modules/services/omniroute.nix
    ./disko-two-disk.nix
    ../../../modules/applications/music
  ];

  networking.hostName = "home-forge";

  # Base aspect host facts (FND-2): systemd-boot loader and 50% /build tmpfs.
  fleet.foundation = {
    bootLoader = "systemd-boot";
    buildTmpfsSize = "50%";
  };

  # Deferred leaf enablement (FND-6 row 10): explicit host declarations until
  # the focused builder-access ownership change.
  fleet.nixbuild-ssh.enable = true;

  # Locally-managed physical host: plain LAN DHCP via native systemd-networkd
  # (fleet networking aspect), no static addresses and no public ingress. The
  # always-on br0 bridge over eno1 presents the pinned NIC MAC so the router
  # reservation survives; DNS is pinned to public resolvers for a private
  # network with no local split-horizon.
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

  # UEFI + systemd-boot rendered by the base aspect from the typed
  # fleet.foundation.bootLoader fact (FND-2); EFI policy stays
  # canTouchEfiVariables = false — do not touch NVRAM.
  disko.devices.disk.main.device = "/dev/disk/by-id/nvme-SAMSUNG_MZVLB1T0HBLR-000H1_S4GRNX0RA26985";
  # Oversized ESP: room for future boot entries plus a backup copy of the
  # existing ESP contents.
  disko-esp-size = "4G";
  disko-second-disk = "/dev/disk/by-id/ata-ST1000DM010-2EP102_ZN19040F";

  # Tailscale is enabled by the tailscale foundation aspect (FND-4). The leaf
  # owns auth-key registration and MTU rendering: authentication only activates
  # once host secrets exist (two-step sops bootstrap). The tag:homelab posture
  # comes from the operator-provided auth key at the secret gate; the host does
  # not advertise a per-host tag.
  sops.defaultSopsFile = ../../../secrets/common.yaml;

  # Host-scoped recovery baseline (HFG-7): rescue operator + recurring reboot
  # exercise. The physical/supplier console is the PRIMARY break-glass path;
  # the rescue operator is defense-in-depth. Activates once host secrets exist.
  services.hostRecovery = lib.mkIf hasHostSecrets {
    enable = true;
    secretFile = ../../../secrets/hosts/home-forge/system.yaml;
    rescueUser.name = "rescue";
    reboot.onCalendar = "weekly";
  };
  # Host-scoped R2/restic backup (HFG-6): core/high-level system state only
  # (config, host identity, recovery material); workload-specific paths are
  # added as workloads are introduced, not speculatively. Credentials resolve
  # from the host system secret. Activates once host secrets exist.
  services.state-backups = lib.mkIf hasHostSecrets {
    enable = true;
    secretFile = ../../../secrets/hosts/home-forge/system.yaml;
    bucket = "shrublab-backup-home-forge";
    stagingRoot = "/srv/data/state-backups";
    # Baseline-only host: no workload modules contribute backup contracts
    # yet, so back up the persistent host identity directly. Workload paths
    # are added as workloads are introduced.
    services.host-core.paths = [ "/etc/ssh" ];
  };

  # Deferred leaf enablement (FND-6 row 10): explicit host declarations until
  # the focused Beszel/backup ownership changes.
  services.beszel-agent-auth = lib.mkIf hasHostSecrets {
    enable = true;
    secretFiles.host = ../../../secrets/hosts/home-forge/system.yaml;
  };

  services.niks3-post-deploy.enable = true;

  # nixos-facter facts replace a hand-written hardware-configuration.nix. The
  # report was captured from the live ISO (operator gate 8.3); until then keep
  # facter wired but inert so base-install eval converges without the file.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;

  services.notification-daemon = {
    secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
    secretFiles.hostSystem = ../../../secrets/hosts/home-forge/system.yaml;
    ntfy.enable = true;
  };

  # Providers/routing/tunnels are dashboard-managed state under /srv/data/omniroute;
  # gated on the encrypted secret existing (two-step bootstrap).
  services.omniroute = lib.mkIf (builtins.pathExists ../../../secrets/services/omniroute.yaml) {
    enable = true;
    secretFiles.host = ../../../secrets/services/omniroute.yaml;
  };

  services.notification-daemon.monitor.services =
    lib.optionals (builtins.pathExists ../../../secrets/services/omniroute.yaml)
      [ "podman-omniroute" ];

  applications.dj = {
    enable = true;
    engine = {
      enable = true;
      sharePath = musicStorageRoot;
      musicStorageRoot = musicStorageRoot;
      traktorStateDir = traktorStateDir;
      secretFiles.navidrome = ../../../secrets/applications/music.yaml;
    };
  };

  applications.music = {
    enable = true;
    dataRoot = "/srv/data";
    storageRoot = musicStorageRoot;
    secretFiles.host = ../../../secrets/applications/music.yaml;
    navidrome.enable = true;
    audiomuse.enable = true;
    # AudioMuse DB lives in oci-melb-1's shared Postgres over Tailscale.
    audiomuse.postgresHost = "oci-melb-1";
  };

  services.syncthing.openDefaultPorts = lib.mkForce true;

  system.stateVersion = "25.11";
}
