{
  config,
  lib,
  pkgs,
  ociImages,
  ...
}:
let
  cfg = config.services.phoenix;

  hostGrpc = "http://127.0.0.1:${toString cfg.grpcPort}";
  containerGrpc = "http://host.containers.internal:${toString cfg.grpcPort}";
  hostHttp = "http://127.0.0.1:${toString cfg.port}";
in
{
  options.services.phoenix = {
    enable = lib.mkEnableOption "Arize Phoenix LLM observability collector";

    image = lib.mkOption {
      type = lib.types.str;
      default = ociImages.phoenix;
      description = "Arize Phoenix OCI image reference.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/phoenix";
      description = "Host path for Phoenix working directory (SQLite DB lives here).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 6006;
      description = "HTTP port for Phoenix UI and HTTP OTLP ingestion.";
    };

    grpcPort = lib.mkOption {
      type = lib.types.port;
      default = 4317;
      description = "gRPC port for OTel OTLP trace ingestion.";
    };

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = "Number of days to retain traces before pruning.";
    };

    pruneMaxDbSizeMb = lib.mkOption {
      type = lib.types.int;
      default = 500;
      description = "Max SQLite DB size in MB before a full rotation is triggered.";
    };

    extraEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables passed to the Phoenix container.";
    };

    endpoint = {
      grpc = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = hostGrpc;
        description = "Phoenix gRPC OTLP endpoint reachable from the host.";
      };

      grpcContainer = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = containerGrpc;
        description = "Phoenix gRPC OTLP endpoint reachable from other Podman containers.";
      };

      http = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        default = hostHttp;
        description = "Phoenix HTTP OTLP endpoint reachable from the host.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.podman.enable = true;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root - -"
      "z ${cfg.dataDir} 0755 root root - -"
    ];

    virtualisation.oci-containers.containers.phoenix = {
      autoStart = true;
      image = cfg.image;
      ports = [
        "0.0.0.0:${toString cfg.port}:${toString cfg.port}"
        "0.0.0.0:${toString cfg.grpcPort}:${toString cfg.grpcPort}"
      ];
      environment = {
        PHOENIX_WORKING_DIR = "/var/lib/phoenix";
        PHOENIX_PORT = toString cfg.port;
        PHOENIX_GRPC_PORT = toString cfg.grpcPort;
        PHOENIX_HOST = "0.0.0.0";
      }
      // cfg.extraEnv;
      volumes = [
        "${cfg.dataDir}:/var/lib/phoenix"
      ];
    };

    systemd.services."podman-phoenix" = {
      description = "Arize Phoenix LLM observability collector";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
    };

    # Periodic trace pruning via DB rotation when size exceeds threshold.
    systemd.services.phoenix-prune = {
      description = "Prune old Arize Phoenix traces";
      after = [ "podman-phoenix.service" ];
      wants = [ "podman-phoenix.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "phoenix-prune" ''
          set -euo pipefail
          DB="${cfg.dataDir}/phoenix.db"
          MAX_SIZE=${toString cfg.pruneMaxDbSizeMb}
          RETENTION_DAYS=${toString cfg.retentionDays}

          if [ ! -f "$DB" ]; then
            exit 0
          fi

          # If the DB exists and has entries, try age-based pruning via sqlite3.
          if command -v sqlite3 &>/dev/null; then
            # Phoenix stores spans in the 'spans' table with 'start_time' as nanoseconds since epoch.
            # Compute cutoff: now - retention_days in nanoseconds.
            CUTOFF=$(( $(date +%s) - RETENTION_DAYS * 86400 ))
            CUTOFF_NS=$(( CUTOFF * 1000000000 ))
            sqlite3 "$DB" "DELETE FROM spans WHERE start_time < $CUTOFF_NS;" 2>/dev/null || true
            sqlite3 "$DB" "VACUUM;" 2>/dev/null || true
          fi

          # If the DB is still too large, rotate it (preserve as backup, start fresh).
          SIZE_MB=$(du -m "$DB" | cut -f1)
          if [ "$SIZE_MB" -gt "$MAX_SIZE" ]; then
            mv "$DB" "$DB.$(date +%Y%m%d-%H%M%S)"
            systemctl restart podman-phoenix
          fi
        '';
      };
    };

    systemd.timers.phoenix-prune = {
      description = "Monthly Arize Phoenix trace pruning timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "monthly";
        RandomizedDelaySec = "6h";
        Persistent = true;
      };
    };

    services.state-backups.services.phoenix = {
      enable = true;
      mode = "live";
      paths = [ cfg.dataDir ];
    };
  };
}
