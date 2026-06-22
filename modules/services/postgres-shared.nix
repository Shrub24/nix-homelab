{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.postgres-shared;
  hasDbConsumer =
    cfg.niks3.enable || cfg.paperless.enable || cfg.audiomuse.enable || cfg.litellm.enable;
in
{
  options.services.postgres-shared = {
    enable = lib.mkEnableOption "shared PostgreSQL platform substrate";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/postgres";
      description = "PostgreSQL data directory on the shared service-state mount.";
    };

    niks3 = {
      enable = lib.mkEnableOption "dedicated niks3 database and user on the shared PostgreSQL instance";
    };

    paperless = {
      enable = lib.mkEnableOption "dedicated paperless database and user on the shared PostgreSQL instance";
    };

    audiomuse = {
      enable = lib.mkEnableOption "dedicated audiomuse database and user on the shared PostgreSQL instance with TCP password auth";
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a SOPS-encrypted YAML file containing Postgres role passwords
        for external-consumer database roles (e.g. litellm).
        Expected YAML keys follow the pattern "roles/<name>/password".
      '';
    };

    litellm = {
      enable = lib.mkEnableOption "dedicated litellm database and user on the shared PostgreSQL instance with TCP password auth over Tailscale";

      passwordKey = lib.mkOption {
        type = lib.types.str;
        default = "roles/litellm/password";
        description = "SOPS YAML key path for the litellm Postgres role password within secretFile.";
      };

      allowedCIDRs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ];
        description = "CIDR ranges allowed to authenticate as the litellm role with password auth.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      dataDir = cfg.dataDir;

      # Listen on all interfaces so Podman containers can reach Postgres via host.containers.internal.
      # Uses the native enableTCPIP option (nixpkgs sets listen_addresses = "*" at priority 100).
      # Overridable per-host with a direct listen_addresses assignment.
      enableTCPIP = true;

      ensureDatabases =
        lib.optionals cfg.niks3.enable [ "niks3" ]
        ++ lib.optionals cfg.paperless.enable [ "paperless" ]
        ++ lib.optionals cfg.audiomuse.enable [ "audiomuse" ]
        ++ lib.optionals cfg.litellm.enable [ "litellm" ];

      ensureUsers =
        lib.optionals cfg.niks3.enable [
          {
            name = "niks3";
            ensureDBOwnership = true;
          }
        ]
        ++ lib.optionals cfg.paperless.enable [
          {
            name = "paperless";
            ensureDBOwnership = true;
          }
        ]
        ++ lib.optionals cfg.audiomuse.enable [
          {
            name = "audiomuse";
            ensureDBOwnership = true;
            ensureClauses.login = true;
          }
        ]
        ++ lib.optionals cfg.litellm.enable [
          {
            name = "litellm";
            ensureDBOwnership = true;
            ensureClauses.login = true;
          }
        ];

      authentication = lib.mkBefore ''
        ${lib.optionalString cfg.niks3.enable "local niks3 niks3 peer"}
        ${lib.optionalString cfg.paperless.enable "local paperless paperless peer"}
        ${lib.optionalString cfg.audiomuse.enable "host audiomuse audiomuse 0.0.0.0/0 scram-sha-256"}
        ${lib.optionalString cfg.audiomuse.enable "host audiomuse audiomuse ::/0 scram-sha-256"}
        ${lib.optionalString cfg.litellm.enable (
          lib.concatMapStringsSep "\n" (
            cidr: "host litellm litellm ${cidr} scram-sha-256"
          ) cfg.litellm.allowedCIDRs
        )}
      '';

      settings = {
        max_connections = "20";
        shared_buffers = "64MB";
        effective_cache_size = "128MB";
        maintenance_work_mem = "16MB";
        wal_buffers = "4MB";
        random_page_cost = "1.1";
        effective_io_concurrency = "200";
        work_mem = "4MB";
        huge_pages = "off";
      };
    };

    assertions = [
      {
        assertion = !cfg.litellm.enable || cfg.secretFile != null;
        message = "services.postgres-shared.litellm.enable is true but services.postgres-shared.secretFile is not set.";
      }
    ];

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = [ cfg.dataDir ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 postgres postgres - -"
    ];

    # ── AudioMuse dedicated database password ──────────────────────────────
    # The `audiomuse_postgres_password` SOPS secret is declared by the audiomuse
    # service module (which owns the music secret file). The password file is
    # rendered at activation time and applied to Postgres on each start so that
    # password rotations from SOPS take effect on the next postgresql restart.
    # ──────────────────────────────────────────────────────────────────────────
    sops.templates."audiomuse-postgres-password" = lib.mkIf cfg.audiomuse.enable {
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      content = "${config.sops.placeholder.audiomuse_postgres_password}";
    };

    sops.templates."postgres-shared-litellm-password" =
      lib.mkIf (cfg.litellm.enable && cfg.secretFile != null)
        {
          owner = "postgres";
          group = "postgres";
          mode = "0400";
          content = "${config.sops.placeholder.postgres_shared_litellm_password}";
        };

    sops.secrets.postgres_shared_litellm_password =
      lib.mkIf (cfg.litellm.enable && cfg.secretFile != null)
        {
          sopsFile = cfg.secretFile;
          key = cfg.litellm.passwordKey;
          path = "/run/secrets/postgres-shared/litellm.password";
          owner = "postgres";
          group = "postgres";
          mode = "0400";
        };

    systemd.services.postgresql.postStart =
      (lib.optionalString cfg.audiomuse.enable ''
        PWD_FILE="${config.sops.templates."audiomuse-postgres-password".path}"
        if [ -f "$PWD_FILE" ]; then
          ${pkgs.postgresql}/bin/psql -tAc "ALTER USER audiomuse PASSWORD '$(cat "$PWD_FILE")';" 2>/dev/null || true
        fi
      '')
      + (lib.optionalString (cfg.litellm.enable && cfg.secretFile != null) ''
        PWD_FILE="${config.sops.templates."postgres-shared-litellm-password".path}"
        if [ -f "$PWD_FILE" ]; then
          ${pkgs.postgresql}/bin/psql -tAc "ALTER USER litellm PASSWORD '$(cat "$PWD_FILE")';" 2>/dev/null || true
        fi
      '');

    # ── Shared PostgreSQL backup coverage ──────────────────────────────────
    # Covers the entire shared data directory (niks3, paperless, audiomuse, etc.).
    # Individual services do not register separate Postgres volume backups.
    services.state-backups.services.postgres-shared = lib.mkIf hasDbConsumer {
      enable = true;
      mode = "live";
      paths = [ cfg.dataDir ];
    };
  };
}
