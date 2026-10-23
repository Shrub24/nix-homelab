# Home Assistant container, on the host network for discovery, with an operator-owned
# config directory. Options live under `services.hass`: nixpkgs owns `services.home-assistant`.
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
              # A native listener on this port wins the bind and Home Assistant drops into
              # recovery mode with no frontend. Fail closed here, not at activation.
              assertion =
                !(config.services ? clickhouse)
                || !(config.services.clickhouse.enable or false)
                || (config.services.clickhouse.serverConfig.http_port or 0) != cfg.port;
              message = "services.hass: port ${toString cfg.port} is also ClickHouse's HTTP port on this host; a host-networked Home Assistant cannot bind it. Move one of the two, as policy/globals.nix does for ClickHouse.";
            }
          ];

          # Host networking for discovery (HomeKit, Chromecast, Hue, Matter, ESPHome);
          # nothing is published, so the listener is whatever Home Assistant binds.
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

          # The operator owns /config. 0700 because .storage holds every token.
          systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0700 root root -" ];

          # nixpkgs already widens the start limit enough for a crash loop to reach `failed`.
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
