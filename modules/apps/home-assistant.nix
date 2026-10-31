# Home Assistant container on the host network. Options are `services.hass` because nixpkgs
# already owns `services.home-assistant`.
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
      # The recorder database is live: exported through the online backup API, never copied raw.
      databaseFile = "${cfg.dataDir}/home-assistant_v2.db";
    in
    {
      # Declaration-only, so the registration below also evaluates where the mechanism is absent.
      imports = [ ../backups/state-backups/_consumer.nix ];

      options.services.hass = {
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

      config = {
        assertions = [
          {
            assertion = route != null;
            message = "services.hass: canonical web-policy route 'repo.web.catalog.home-assistant' is missing; declare the home-assistant route in policy/web-services.nix.";
          }
          {
            assertion = route == null || route.upstreamPort == cfg.port;
            message = "services.hass: the route's upstream port must match services.hass.port, or the edge dials a port nothing listens on.";
          }
        ];

        # Host networking for LAN discovery; nothing is published, so the listener is whatever
        # Home Assistant binds.
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

        # 0700: the operator owns /config, and .storage holds every token.
        systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0700 root root -" ];

        services.notify.events."podman-home-assistant".failure = { };

        services.state-backups.services.home-assistant = {
          enable = true;
          mode = "export";
          paths = [ cfg.dataDir ];
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
      };
    };
}
