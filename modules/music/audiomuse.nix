# Music feature sibling: contributes to the `music` aspect
# (flake.modules.nixos.music) as a deferredModule sibling; the host selects one
# name and the module system merges every sibling file.
{ ... }:
{
  flake.modules.nixos.music =
    {
      lib,
      config,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.audiomuse;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      # One credential, one source: the role password lives in secretFiles.db.
      # This service reads it to authenticate and the co-located cluster reads the
      # same file and key to provision the role.
      dbSecretAvailable = cfg.secretFiles.db != null && builtins.pathExists cfg.secretFiles.db;

      # The cluster this host runs, when it runs one. The declaration is probed
      # through `options` before the value is read, because reading an undeclared
      # option path raises NixOS' "did you mean" error rather than returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      navidromePort = 4533;
    in
    {
      # The registration below extends `services.postgres`'s contract, so this
      # service imports the module that declares it: a definition of an undeclared
      # option is rejected even when its `mkIf` is false. Enablement stays with the
      # `postgres` aspect, so importing the declarations provisions nothing.
      imports = [ ../database/postgres/_consumer.nix ];

      options.services.audiomuse = {
        enable = lib.mkEnableOption "AudioMuseAI similarity service";

        image = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.audiomuse;
          description = "Pinned AudioMuseAI container image.";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data/audiomuse";
          description = "Persistent state root for AudioMuseAI.";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Listen address for the AudioMuseAI web API host binding.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8000;
          description = "Host port for the AudioMuseAI web API and setup UI.";
        };

        timeZone = lib.mkOption {
          type = lib.types.str;
          default = "UTC";
          description = "Timezone passed into the AudioMuseAI containers.";
        };

        networkName = lib.mkOption {
          type = lib.types.str;
          default = "audiomuse-net";
          description = "Dedicated Podman network for AudioMuseAI containers.";
        };

        networkSubnet = lib.mkOption {
          type = lib.types.str;
          default = "10.89.42.0/24";
          description = ''
            Subnet for the dedicated Podman network. Pinned rather than left to
            Podman's pool because the PostgreSQL registration allows exactly this
            range to authenticate as the AudioMuse role.
          '';
        };

        dataBackupPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Paths included in durable state backup scope. AudioMuse durable state lives in its PostgreSQL database, which the cluster that serves it exports for restic; Redis/temp are non-canonical.";
        };

        environmentFile = lib.mkOption {
          type = lib.types.str;
          default = config.sops.templates."audiomuse.env".path;
          description = "Environment file containing AudioMuseAI bootstrap secrets.";
        };

        navidromeUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "http://host.containers.internal:${toString navidromePort}";
          description = "Optional Navidrome base URL presented to AudioMuseAI during initial setup.";
        };

        # AudioMuse's PostgreSQL database lives remotely in OCI's shared Postgres,
        # reached over Tailscale/MagicDNS (tailnet-only + SCRAM). The host is a leaf
        # contract input so home-forge can point at oci-melb-1 while remaining local
        # co-located deployments keep host.containers.internal. Redis/temp stay local.
        postgresHost = lib.mkOption {
          type = lib.types.str;
          default = "host.containers.internal";
          description = "PostgreSQL hostname/address for the AudioMuse database.";
        };

        postgresPort = lib.mkOption {
          type = lib.types.port;
          default = 5432;
          description = "PostgreSQL TCP port for the AudioMuse database.";
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "audiomuse-host-secrets";

        secretFiles.db = secretHelpers.mkSecretFileOption "audiomuse-db";

        secretKeys.postgresPassword = secretHelpers.mkSecretKeyOption "audiomuse/postgres_password";
      };

      config = lib.mkIf cfg.enable {
        # Self-registration: the database, role, and credential this service needs,
        # declared next to the service that uses them. The provider reads the same
        # file and key to provision the role, so the password has one authoritative
        # source instead of a hand-synced pair.
        services.postgres.consumers.audiomuse = lib.mkIf (localPostgres != null) {
          database = "audiomuse";
          auth = "scram";
          password = lib.mkIf dbSecretAvailable {
            file = cfg.secretFiles.db;
            key = cfg.secretKeys.postgresPassword;
          };
          # The container reaches the database over the Podman bridge, so the role
          # accepts exactly that range rather than the whole tailnet.
          allowedCIDRs = [ cfg.networkSubnet ];
        };

        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            enable = cfg.enable;
            file = cfg.secretFiles.host;
            feature = "services.audiomuse";
            label = "secretFiles.host";
          })
          (secretHelpers.mkRequiredSecretAssertion {
            enable = cfg.enable;
            file = cfg.secretFiles.db;
            feature = "services.audiomuse";
            label = "secretFiles.db";
          })
          {
            assertion = !cfg.enable || dbSecretAvailable;
            message = "services.audiomuse.enable is true but its encrypted secretFiles.db is missing.";
          }
          {
            assertion = !cfg.enable || localPostgres != null || cfg.postgresHost != null;
            message = "services.audiomuse.enable is true but no PostgreSQL endpoint is available: run a cluster on this host (select the postgres aspect) or set postgresHost explicitly for a database that lives elsewhere.";
          }
        ];

        sops.templates."audiomuse.env" = {
          owner = "root";
          group = "root";
          mode = "0400";
          restartUnits = [
            "podman-audiomuse-web.service"
            "podman-audiomuse-worker.service"
          ];
          content = ''
            TZ=${cfg.timeZone}
            AUTH_ENABLED=true
            AUDIOMUSE_USER=audiomuse
            AUDIOMUSE_PASSWORD=${config.sops.placeholder.audiomuse_password}
            API_TOKEN=${config.sops.placeholder.audiomuse_api_token}
            JWT_SECRET=${config.sops.placeholder.audiomuse_jwt_secret}
            POSTGRES_DB=audiomuse
            POSTGRES_USER=audiomuse
            POSTGRES_HOST=${cfg.postgresHost}
            POSTGRES_PORT=${toString cfg.postgresPort}
          ''
          + ''
            POSTGRES_PASSWORD=${config.sops.placeholder.audiomuse_postgres_password}
          ''
          + ''
            REDIS_URL=redis://audiomuse-redis:6379/0
          ''
          + lib.optionalString (cfg.navidromeUrl != null) ''
            NAVIDROME_URL=${cfg.navidromeUrl}
          '';
        };

        sops.secrets =
          secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
            audiomuse_password = {
              key = "audiomuse/password";
              path = "/run/secrets/audiomuse.password";
            };
            audiomuse_api_token = {
              key = "audiomuse/api_token";
              path = "/run/secrets/audiomuse.api_token";
            };
            audiomuse_jwt_secret = {
              key = "audiomuse/jwt_secret";
              path = "/run/secrets/audiomuse.jwt_secret";
            };
          }
          // {
            audiomuse_postgres_password = {
              sopsFile = cfg.secretFiles.db;
              key = cfg.secretKeys.postgresPassword;
              path = "/run/secrets/audiomuse.postgres_password";
              restartUnits = [
                "podman-audiomuse-web.service"
                "podman-audiomuse-worker.service"
              ];
            };
          };

        virtualisation.podman.enable = true;
        virtualisation.podman.autoPrune.enable = lib.mkDefault true;

        networking.firewall.interfaces."audiomuse0".allowedTCPPorts = lib.mkIf (cfg.navidromeUrl != null) [
          navidromePort
        ];

        systemd.services."podman-network-${cfg.networkName}" = {
          description = "Create Podman network ${cfg.networkName}";
          wantedBy = [ "multi-user.target" ];
          before = [
            "podman-audiomuse-redis.service"
            "podman-audiomuse-worker.service"
            "podman-audiomuse-web.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${cfg.networkName} || ${pkgs.podman}/bin/podman network create --interface-name=audiomuse0 --subnet=${cfg.networkSubnet} ${cfg.networkName}'";
            ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${cfg.networkName} || true'";
          };
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 root root - -"
          "d ${cfg.dataDir}/redis 0750 999 999 - -"
          "z ${cfg.dataDir}/redis 0750 999 999 - -"
          "d ${cfg.dataDir}/temp 0750 root root - -"
          "z ${cfg.dataDir}/temp 0750 root root - -"
        ];

        virtualisation.oci-containers.containers.audiomuse-redis = {
          autoStart = true;
          image = config.repo.ociImages.redis7Alpine;
          extraOptions = [ "--network=${cfg.networkName}" ];
          volumes = [ "${cfg.dataDir}/redis:/data" ];
        };

        virtualisation.oci-containers.containers.audiomuse-worker = {
          autoStart = true;
          image = cfg.image;
          extraOptions = [ "--network=${cfg.networkName}" ];
          environment = {
            SERVICE_TYPE = "worker";
            TEMP_DIR = "/app/temp_audio";
          };
          environmentFiles = [ cfg.environmentFile ];
          volumes = [ "${cfg.dataDir}/temp:/app/temp_audio" ];
        };

        virtualisation.oci-containers.containers.audiomuse-web = {
          autoStart = true;
          image = cfg.image;
          extraOptions = [ "--network=${cfg.networkName}" ];
          ports = [ "${cfg.listenAddress}:${toString cfg.port}:8000" ];
          environment = {
            SERVICE_TYPE = "flask";
            TEMP_DIR = "/app/temp_audio";
          };
          environmentFiles = [ cfg.environmentFile ];
          volumes = [ "${cfg.dataDir}/temp:/app/temp_audio" ];
        };

        systemd.services."podman-audiomuse-redis" = {
          wants = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          after = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          requires = [ "podman-network-${cfg.networkName}.service" ];
          unitConfig.RequiresMountsFor = [ cfg.dataDir ];
          serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/chown 999:999 '${cfg.dataDir}/redis'";
        };

        systemd.services."podman-audiomuse-worker" = {
          wants = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          after = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
            "podman-audiomuse-redis.service"
          ];
          requires = [
            "podman-network-${cfg.networkName}.service"
            "podman-audiomuse-redis.service"
          ];
          unitConfig.RequiresMountsFor = [ cfg.dataDir ];
          restartTriggers = [
            cfg.environmentFile
          ];
        };

        systemd.services."podman-audiomuse-web" = {
          wants = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          after = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
            "podman-audiomuse-redis.service"
          ];
          requires = [
            "podman-network-${cfg.networkName}.service"
            "podman-audiomuse-redis.service"
          ];
          unitConfig.RequiresMountsFor = [ cfg.dataDir ];
          restartTriggers = [
            cfg.environmentFile
          ];
        };

        services.state-backups.services.audiomuse = {
          enable = true;
          mode = "live";
          paths = cfg.dataBackupPaths;
        };
      };
    };
}
