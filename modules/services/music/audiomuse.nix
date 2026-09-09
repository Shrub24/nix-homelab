{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.audiomuse;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

  # D-045 two-file credential contract: the database-side role password lives
  # in the OCI-only secrets/services/postgres-shared.yaml (key
  # roles/audiomuse/password); this service reads the client-side password
  # from secretFiles.db (secrets/applications/music.yaml, key
  # audiomuse/postgres_password). The operator keeps the two values matching.
  dbSecretAvailable = cfg.secretFiles.db != null && builtins.pathExists cfg.secretFiles.db;
  navidromePort = 4533;
in
{
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

    dataBackupPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths included in durable state backup scope. AudioMuse durable state is covered by shared-Postgres backup; Redis/temp are non-canonical.";
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
        ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${cfg.networkName} || ${pkgs.podman}/bin/podman network create --interface-name=audiomuse0 ${cfg.networkName}'";
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
}
