# Host-private NixOS composition for home-forge (Stage 8 HIC-2, task 2.2). The
# canonical typed record lives in ./default.nix and imports this fragment as its
# deferred composition; underscore-named siblings keep every host-private
# fragment out of discovery.
{
  lib,
  config,
  ...
}:
let
  hasHostSecrets = builtins.pathExists ../../../secrets/hosts/home-forge/system.yaml;

  # Host-owned physical music root; the music aspect derives the storage
  # library contract from it and the DJ application consumes that contract.
  musicStorageRoot = "/srv/storage/media/music";
  # Playlist-sync worker state (SQLite store + inbound M3U drop), outside the
  # media library so state/input files never surface as music.
  traktorStateDir = "/srv/data/traktor-m3u-sync";
in
{
  imports = [
    # Every deployed product arrives via the placement aspects selected in this
    # host's canonical record (Stage 8 HIC-1/HIC-2); this fragment keeps only
    # machine facts, explicit variants, and its host-local disk layout.
    ./_disko-two-disk.nix
  ];

  # Base aspect host facts (FND-2): systemd-boot loader and 50% /build tmpfs.
  fleet.foundation = {
    bootLoader = "systemd-boot";
    buildTmpfsSize = "50%";
  };

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
  # from the host system secret. The backups aspect owns enablement, the
  # derived secret path, and the derived bucket (OPS-3); the host keeps only
  # its real variants: the non-default staging root and the host-core backup
  # contract.
  services.state-backups = {
    stagingRoot = "/srv/data/state-backups";
    # Baseline-only host: no workload modules contribute backup contracts
    # yet, so back up the persistent host identity directly. Workload paths
    # are added as workloads are introduced.
    services.host-core.paths = [ "/etc/ssh" ];
  };

  # nixos-facter facts replace a hand-written hardware-configuration.nix. The
  # report was captured from the live ISO (operator gate 8.3); until then keep
  # facter wired but inert so base-install eval converges without the file.
  hardware.facter.reportPath = lib.mkIf (builtins.pathExists ./facter.json) ./facter.json;

  services.notification-daemon = {
    secretFiles.host = ../../../secrets/services/notification-daemon.yaml;
    secretFiles.hostSystem = ../../../secrets/hosts/home-forge/system.yaml;
    ntfy.enable = true;
  };

  applications.dj = {
    engine = {
      enable = true;
      traktorStateDir = traktorStateDir;
      secretFiles.navidrome = ../../../secrets/applications/music.yaml;
    };
  };

  # Music composition is provided by the `music` deployment aspect (selected
  # in the registry); the host keeps only its real variants.
  # Home-forge runs its own PostgreSQL cluster (D-058): AudioMuse's database is
  # co-located with its compute, so the container reaches it over the Podman
  # bridge and no cross-host transport is involved. The password lives in the
  # music secrets file, which both this cluster and the AudioMuse container read.
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
    # AudioMuse's database endpoint resolves to this host's own cluster when one
    # is declared (services.postgres.localEndpoint) and to the internal contract
    # otherwise, so the host names no provider either way.
  };

  services.syncthing.openDefaultPorts = lib.mkForce true;

  system.stateVersion = "25.11";
}
