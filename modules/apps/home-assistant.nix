# Home Assistant deployment aspect: the container installation the project
# supports, bound to the host network so discovery works, and with a
# configuration directory the operator owns rather than one Nix renders.
#
# The option namespace is `services.hass`, not `services.home-assistant`:
# nixpkgs already owns that path for its native Core module, and one option name
# meaning two different installations depending on which module a host imported
# is a trap. This module never imports the native one.
_: {
  flake.modules.nixos.home-assistant =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.hass;
      route = config.repo.web.catalog.home-assistant or null;
      exportDir = "${config.services.state-backups.stagingRoot}/home-assistant";
      # The recorder database is a live SQLite file: it is exported through the
      # online backup API, never copied raw.
      databaseFile = "${cfg.dataDir}/home-assistant_v2.db";
    in
    {
      # Declaration-only contract: the registration below evaluates on a host
      # that does not run the backup mechanism.
      imports = [ ../backups/state-backups/_consumer.nix ];

      options.services.hass = {
        enable = lib.mkEnableOption "Home Assistant (container)";

        image = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.homeAssistant;
          description = "Home Assistant container image reference (tag + digest).";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data/home-assistant";
          description = "Host directory mounted at /config; Home Assistant's own state.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8123;
          description = ''
            Port Home Assistant listens on, on every interface because the
            container shares the host network namespace. The web policy's origin
            must declare the same port, and an assertion holds the two together;
            changing it means editing configuration.yaml's `http.server_port` and
            the policy route together.
          '';
        };

        timeZone = lib.mkOption {
          type = lib.types.str;
          default = config.time.timeZone;
          description = "Timezone passed to the container (also mounted as /etc/localtime).";
        };
      };

      config = lib.mkMerge [
        { services.hass.enable = true; }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = route != null;
              message = "services.hass: canonical web-policy route 'repo.web.catalog.home-assistant' is missing; declare the home-assistant route in policy/web-services.nix.";
            }
            {
              # The catalog carries the published upstream shape, not the raw
              # `origin` record: `upstreamPort` is that origin's port.
              assertion = route == null || route.upstreamPort == cfg.port;
              message = "services.hass: the route's upstream port must match services.hass.port, or the edge dials a port nothing listens on.";
            }
            {
              # A host-networked container shares the host's port space, so a
              # native listener on the same port wins the bind and Home Assistant
              # falls into recovery mode with no frontend. ClickHouse's HTTP
              # interface was the first collision: 8123 is its default and
              # home-forge runs both (D-102). Fail closed here rather than at
              # activation, where the symptom is a bare recovery page.
              assertion =
                !(config.services ? clickhouse)
                || !(config.services.clickhouse.enable or false)
                || (config.services.clickhouse.serverConfig.http_port or 0) != cfg.port;
              message = "services.hass: port ${toString cfg.port} is also ClickHouse's HTTP port on this host; a host-networked Home Assistant cannot bind it. Move one of the two, as policy/globals.nix does for ClickHouse.";
            }
          ];

          # Host networking, not a published port: discovery integrations
          # (HomeKit, Chromecast, Hue, Matter, ESPHome) need the container on the
          # LAN's own namespace, and this is the shape upstream and the nixpkgs
          # wiki both document. Nothing is published, so the listener is whatever
          # Home Assistant binds — 8123 by default.
          virtualisation.oci-containers.containers.home-assistant = {
            inherit (cfg) image;
            autoStart = true;
            extraOptions = [ "--network=host" ];
            volumes = [
              "${cfg.dataDir}:/config"
              "/etc/localtime:/etc/localtime:ro"
            ];
            environment.TZ = cfg.timeZone;
          };

          # Home Assistant creates a minimal configuration.yaml itself when the
          # directory is empty, so Nix seeds nothing here — the operator owns
          # /config. Mode 0700 because the directory holds the auth store
          # (.storage) with every token and integration credential.
          systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0700 root root -" ];

          # The container carries nixpkgs' widened limit already (5 starts per
          # hour, not per 10 seconds), which a crash loop actually crosses, so a
          # failing instance reaches `failed` and this registration fires.
          services.notify.events."podman-home-assistant".failure = { };

          services.state-backups.services.home-assistant = {
            enable = true;
            mode = "export";
            paths = [ cfg.dataDir ];
            # The recorder database and its WAL sidecars are captured by the
            # export below instead of being copied mid-write.
            exclude = [
              databaseFile
              "${databaseFile}-wal"
              "${databaseFile}-shm"
            ];
            exportPaths = [ "${exportDir}/home-assistant_v2.db" ];
            prepareCommands = [
              "${pkgs.coreutils}/bin/mkdir -p ${exportDir}"
              "${pkgs.sqlite}/bin/sqlite3 -readonly ${databaseFile} ${lib.escapeShellArg ".backup ${exportDir}/home-assistant_v2.db"}"
            ];
            cleanupCommands = [ "${pkgs.coreutils}/bin/rm -rf ${exportDir}" ];
          };
        })
      ];
    };
}
