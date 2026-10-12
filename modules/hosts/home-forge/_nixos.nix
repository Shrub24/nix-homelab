# Host-private NixOS composition for home-forge: ./default.nix imports it as the
# record's deferred composition, and the underscore prefix keeps it (and every
# sibling fragment) out of discovery.
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

  # AudioMuse's database is co-located with its compute: the container reaches
  # this cluster over the Podman bridge, so no cross-host transport is involved
  # and both sides read the password from the music secrets file.
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

  services.hindsight = {
    secretFiles.host = ../../../secrets/services/hindsight.yaml;
    # LLM calls go to the fleet gateway (module default: this host's gateway
    # listener, since bifrost runs here; the fleet text alias names the model).
    # The per-operation knobs (llm.retainModel / reflectModel / consolidationModel)
    # stay null until the gateway aliases exist.
    # Embeddings dial Voyage directly (module default): the voyage/ prefix
    # gives hindsight's litellm-sdk client input_type query/document per side.
  };

  # Grafana sign-in through the fleet's Kanidm provider (admins only). The
  # client's secret lives in this host's oidc file — the provider reads it from
  # the file of the host that runs the client.
  services.victoria = {
    oidc.enable = true;
    secretFiles.oidc = ../../../secrets/hosts/home-forge/oidc.yaml;
  };

  # LLM observability backends colocated with the telemetry stores. Langfuse's
  # OIDC client secret lives in this host's oidc file — the provider reads it
  # from the file of the host that runs the client.
  services.langfuse = {
    secretFiles.host = ../../../secrets/services/langfuse.yaml;
    secretFiles.oidc = ../../../secrets/hosts/home-forge/oidc.yaml;
    oidc.enable = config.repo.web.catalog.langfuse.access.oidc.enabled;
  };

  # The gateway's provider credentials are service-scoped and shared with the
  # oci-melb-1 instance: one encrypted file that both hosts may read, so the
  # provider keys are not duplicated per host. Each host runs its own gateway
  # process with its own state; no gateway dials another.
  services.bifrost.secretFiles.host = ../../../secrets/services/bifrost.yaml;

  services.latitude = {
    secretFiles.host = ../../../secrets/services/latitude.yaml;
    # Same Resend relay and verified sending domain as Vaultwarden; sign-in is a
    # magic link, so this address has to be one Resend may send from.
    smtp.from = "latitude@send.shrublab.xyz";
  };

  # Gateway role of the host-local telemetry contract, colocated with the
  # stores and the LLM-observability backends so every export leg is a loopback
  # dial. Producers elsewhere in the fleet (and instrumented workstation
  # clients) push OTLP to this host's canonical tailnet endpoint; the
  # network-facing listener binds the tailnet address explicitly. Admission is
  # explicit: a signal with no admission has no route.
  services.telemetry.otlp = {
    signals = [
      "traces"
      "metrics"
    ];
    ingress.host = "100.126.123.74";
  };

  # The AI lane: a second, explicitly selected OTLP input for agent harnesses
  # and future AI producers. The general ingress above reaches the trace store
  # only, so the LLM-observability backends are reachable exclusively from this
  # listener. Route pipelines inherit nothing, hence VictoriaTraces is named
  # explicitly: an enrolled session belongs in the fleet store too. This is
  # routing separation only — the listener carries no authentication, and a
  # tailnet peer that can reach it can publish to both backends.
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
