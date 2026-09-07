{
  config,
  lib,
  pkgs,
  ociImages,
  ...
}:
let
  cfg = config.services.omniroute;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };

  appUid = 1000;
  appGid = 1000;
  redisUid = 999;
  redisGid = 999;
  appDir = "${cfg.dataDir}/app";
  logsDir = "${appDir}/logs";
  redisDir = "${cfg.dataDir}/redis";
  environmentFile = config.sops.templates."omniroute.environment".path;
in
{
  options.services.omniroute = {
    enable = lib.mkEnableOption "OmniRoute LLM router";

    image = lib.mkOption {
      type = lib.types.str;
      default = ociImages.omniroute;
      description = "OmniRoute container image.";
    };

    redisImage = lib.mkOption {
      type = lib.types.str;
      default = ociImages.redis7Alpine;
      description = "Redis sidecar image backing the rate limiter.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/omniroute";
      description = "Host directory holding app state and redis data.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 20128;
      description = "Host and container port for the dashboard/API.";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "omniroute";
      description = "Podman network shared by the app and redis containers.";
    };

    memoryMb = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = "Node heap ceiling in MB (upstream: coding agents need 8192+).";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "omniroute-host-secrets";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        inherit (cfg) enable;
        file = cfg.secretFiles.host;
        feature = "services.omniroute";
        label = "secretFiles.host";
      })
    ];

    sops.templates."omniroute.environment" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        JWT_SECRET=${config.sops.placeholder.omniroute_jwt_secret}
        API_KEY_SECRET=${config.sops.placeholder.omniroute_api_key_secret}
        STORAGE_ENCRYPTION_KEY=${config.sops.placeholder.omniroute_storage_encryption_key}
        INITIAL_PASSWORD=${config.sops.placeholder.omniroute_initial_password}
        OMNIROUTE_WS_BRIDGE_SECRET=${config.sops.placeholder.omniroute_ws_bridge_secret}
      '';
    };

    sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
      omniroute_jwt_secret = {
        key = "omniroute/jwt_secret";
        path = "/run/secrets/omniroute.jwt_secret";
      };
      omniroute_api_key_secret = {
        key = "omniroute/api_key_secret";
        path = "/run/secrets/omniroute.api_key_secret";
      };
      omniroute_storage_encryption_key = {
        key = "omniroute/storage_encryption_key";
        path = "/run/secrets/omniroute.storage_encryption_key";
      };
      omniroute_initial_password = {
        key = "omniroute/initial_password";
        path = "/run/secrets/omniroute.initial_password";
      };
      omniroute_ws_bridge_secret = {
        key = "omniroute/ws_bridge_secret";
        path = "/run/secrets/omniroute.ws_bridge_secret";
      };
    };

    virtualisation = {
      podman.enable = true;

      oci-containers.containers = {
        omniroute-redis = {
          autoStart = true;
          image = cfg.redisImage;
          extraOptions = [
            "--network=${cfg.networkName}"
          ];
          volumes = [
            "${redisDir}:/data"
          ];
        };

        omniroute = {
          autoStart = true;
          inherit (cfg) image;
          ports = [
            "0.0.0.0:${toString cfg.port}:${toString cfg.port}"
          ];
          extraOptions = [
            "--network=${cfg.networkName}"
            "--stop-timeout=40"
          ];
          environment = {
            PRICING_SYNC_ENABLED = "true";
            DATA_DIR = "/app/data";
            NODE_ENV = "production";
            DASHBOARD_PORT = toString cfg.port;
            OMNIROUTE_MEMORY_MB = toString cfg.memoryMb;
            OMNIROUTE_SERVER_HOST = "0.0.0.0";
            AUTH_COOKIE_SECURE = "false";
            REDIS_URL = "redis://omniroute-redis:6379";
          };
          environmentFiles = [ environmentFile ];
          volumes = [
            "${appDir}:/app/data"
          ];
        };
      };
    };

    services.state-backups.services.omniroute = {
      enable = true;
      mode = "live";
      paths = [ appDir ];
      exclude = [
        logsDir
      ];
    };

    systemd = {
      services = {
        "podman-network-${cfg.networkName}" = {
          description = "Create Podman network ${cfg.networkName}";
          wantedBy = [ "multi-user.target" ];
          before = [
            "podman-omniroute-redis.service"
            "podman-omniroute.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${cfg.networkName} || ${pkgs.podman}/bin/podman network create ${cfg.networkName}'";
            ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${cfg.networkName} || true'";
          };
        };

        "podman-omniroute-redis" = {
          wants = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          after = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          unitConfig.RequiresMountsFor = [ cfg.dataDir ];
        };

        "podman-omniroute" = {
          wants = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
          ];
          after = [
            "network-online.target"
            "podman-network-${cfg.networkName}.service"
            "podman-omniroute-redis.service"
          ];
          requires = [
            "podman-network-${cfg.networkName}.service"
            "podman-omniroute-redis.service"
          ];
          unitConfig = {
            RequiresMountsFor = [
              cfg.dataDir
              appDir
            ];
            # Crash-loop budget: slow the systemd-driven restart to 15s and cap it at
            # 5 failures/hour so a persistent crash fails the unit (and alerts via
            # svc-monitor) instead of looping silently for hours. The default
            # 3-in-10s limit never trips because crash intervals exceed the window.
            StartLimitIntervalSec = 3600;
            StartLimitBurst = 5;
          };
          serviceConfig.RestartSec = "15s";
          restartTriggers = [ environmentFile ];
        };
      };

      tmpfiles.rules = [
        "d ${cfg.dataDir} 0755 root root - -"
        "z ${cfg.dataDir} 0755 root root - -"
        "d ${appDir} 0775 ${toString appUid} ${toString appGid} - -"
        "z ${appDir} 0775 ${toString appUid} ${toString appGid} - -"
        "d ${logsDir} 0775 ${toString appUid} ${toString appGid} - -"
        "z ${logsDir} 0775 ${toString appUid} ${toString appGid} - -"
        "d ${redisDir} 0775 ${toString redisUid} ${toString redisGid} - -"
        "z ${redisDir} 0775 ${toString redisUid} ${toString redisGid} - -"
      ];
    };
  };
}
