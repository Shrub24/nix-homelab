# Host-private composition; the underscore prefix keeps it out of discovery.
{
  config,
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

  services.notify = {
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

  # AudioMuse's database is co-located: the container reaches it over the Podman bridge.
  services.postgres.instances.forge = {
    port = 5432;
    dataDir = "/srv/data/postgres";
  };

  # One cluster serves AudioMuse, Hindsight, Langfuse, Latitude and Temporal; Temporal alone
  # holds ~30 connections, so the 40-connection default starved Langfuse at startup.
  services.postgresql.settings.max_connections = "200";

  applications.music = {
    dataRoot = "/srv/data";
    storageRoot = musicStorageRoot;
    secretFiles.host = ../../../secrets/applications/music.yaml;
    navidrome.enable = true;
    audiomuse.enable = true;
  };

  services.syncthing.openDefaultPorts = lib.mkForce true;

  services.degoog = {
    secretFiles.host = ../../../secrets/services/degoog.yaml;
  };

  services.bookorbit.secretFiles.host = ../../../secrets/services/bookorbit.yaml;
  services.torrents.secretFiles.host = ../../../secrets/hosts/home-forge/system.yaml;

  services.hindsight = {
    secretFiles.host = ../../../secrets/services/hindsight.yaml;
    # Defaults: LLM dials this host's gateway (bifrost runs here); embeddings dial Voyage
    # directly, where the voyage/ prefix sets input_type per side.
  };

  # Grafana SSO via the fleet identity provider (admins only); the secret is host-scoped.
  services.victoria = {
    oidc.enable = true;
    secretFiles.oidc = ../../../secrets/hosts/home-forge/oidc.yaml;
  };

  # LLM observability backends; their OIDC secrets live in this host's oidc file.
  services.langfuse = {
    secretFiles.host = ../../../secrets/services/langfuse.yaml;
    secretFiles.oidc = ../../../secrets/hosts/home-forge/oidc.yaml;
    oidc.enable = config.repo.web.catalog.langfuse.access.oidc.enabled;
  };

  # Provider credentials are service-scoped: both gateway hosts read one encrypted file.
  # Each host runs its own process and state; no gateway dials another.
  services.bifrost.secretFiles.host = ../../../secrets/services/bifrost.yaml;

  services.latitude = {
    secretFiles.host = ../../../secrets/services/latitude.yaml;
  };

  # Gateway role: producers push OTLP to this host's tailnet endpoint, so every export leg is
  # a loopback dial. Admission is explicit — a signal with no admission has no route.
  services.telemetry.otlp = {
    signals = [
      "traces"
      "metrics"
    ];
    ingress.host = "100.126.123.74";
  };

  # AI lane: route pipelines inherit nothing, hence VictoriaTraces is named explicitly.
  # Routing separation only — the listener authenticates nothing.
  services.telemetry.routes.ai = {
    signals = [
      "traces"
      "metrics"
      "logs"
    ];
    pipelines = {
      traces = [
        "victoriatraces"
        "langfuse"
        "latitude"
      ];
      metrics = [ "victoriametrics" ];
      logs = [ "victorialogs" ];
    };
    ingress = {
      host = "100.126.123.74";
      httpPort = 4319;
      grpcPort = null;
    };
  };

  # The tailnet address exists only once tailscaled is up, so the collector orders
  # behind it and retries rather than failing the bind on a cold boot.
  systemd.services.opentelemetry-collector = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig = {
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault "5s";
    };
  };

  system.stateVersion = "25.11";
}
