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

  audiomuseDbAvailable =
    cfg.audiomuse.enable && cfg.secretFile != null && builtins.pathExists cfg.secretFile;

  litellmDbAvailable =
    cfg.litellm.enable && cfg.secretFile != null && builtins.pathExists cfg.secretFile;
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

      passwordKey = lib.mkOption {
        type = lib.types.str;
        default = "roles/audiomuse/password";
        description = "SOPS YAML key path for the audiomuse Postgres role password within secretFile.";
      };

      allowedCIDRs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "100.64.0.0/10"
          "fd7a:115c:a1e0::/48"
        ];
        description = "Tailscale CIDR ranges allowed to authenticate as the audiomuse role with password auth.";
      };
    };

    secretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to a SOPS-encrypted YAML file containing the audiomuse Postgres role
        password (key roles/audiomuse/password).
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

      enableTCPIP = true;

      ensureDatabases =
        lib.optionals cfg.niks3.enable [ "niks3" ]
        ++ lib.optionals cfg.paperless.enable [ "paperless" ]
        ++ lib.optionals audiomuseDbAvailable [ "audiomuse" ]
        ++ lib.optionals litellmDbAvailable [ "litellm" ];

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
        ++ lib.optionals audiomuseDbAvailable [
          {
            name = "audiomuse";
            ensureDBOwnership = true;
            ensureClauses.login = true;
          }
        ]
        ++ lib.optionals litellmDbAvailable [
          {
            name = "litellm";
            ensureDBOwnership = true;
            ensureClauses.login = true;
          }
        ];

      authentication = lib.mkBefore ''
        ${lib.optionalString cfg.niks3.enable "local niks3 niks3 peer"}
        ${lib.optionalString cfg.paperless.enable "local paperless paperless peer"}
        ${lib.optionalString audiomuseDbAvailable (
          lib.concatMapStringsSep "\n" (
            cidr: "host audiomuse audiomuse ${cidr} scram-sha-256"
          ) cfg.audiomuse.allowedCIDRs
        )}
        ${lib.optionalString audiomuseDbAvailable "host all audiomuse all reject"}
        ${lib.optionalString litellmDbAvailable (
          lib.concatMapStringsSep "\n" (
            cidr: "host litellm litellm ${cidr} scram-sha-256"
          ) cfg.litellm.allowedCIDRs
        )}
        ${lib.optionalString litellmDbAvailable "host all litellm all reject"}
      '';

      settings = {
        max_connections = "40";
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
        assertion = !cfg.litellm.enable || litellmDbAvailable;
        message = "services.postgres-shared.litellm.enable is true but services.postgres-shared.litellm.secretFile is missing or absent (expected the litellm role password at key roles/litellm/password).";
      }
      {
        assertion = !cfg.audiomuse.enable || audiomuseDbAvailable;
        message = "services.postgres-shared.audiomuse.enable is true but services.postgres-shared.secretFile is missing or absent (expected the audiomuse role password at key roles/audiomuse/password).";
      }
    ];

    systemd.services.postgresql.serviceConfig = {
      ReadWritePaths = [ cfg.dataDir ];
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 postgres postgres - -"
    ];

    # ── AudioMuse dedicated database password ──────────────────────────────
    # The `audiomuse_postgres_password` secret is declared here (in the shared
    # Postgres platform module) from the generic postgres-shared SOPS file
    # (services.postgres-shared.secretFile), because the audiomuse compute leaf is
    # not enabled on this host once it moves to home-forge. OCI owns the database;
    # home-forge AudioMuse consumes the same file/key. The password is decrypted
    # at activation time and applied to Postgres on each start so that
    # password rotations from SOPS take effect on the next postgresql restart.
    # ──────────────────────────────────────────────────────────────────────────
    sops.secrets.audiomuse_postgres_password = lib.mkIf audiomuseDbAvailable {
      sopsFile = cfg.secretFile;
      key = cfg.audiomuse.passwordKey;
      path = "/run/secrets/postgres-shared/audiomuse.password";
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      restartUnits = [ "postgresql.service" ];
    };

    sops.secrets.postgres_shared_litellm_password = lib.mkIf litellmDbAvailable {
      sopsFile = cfg.secretFile;
      key = cfg.litellm.passwordKey;
      path = "/run/secrets/postgres-shared/litellm.password";
      owner = "postgres";
      group = "postgres";
      mode = "0400";
      restartUnits = [ "postgresql.service" ];
    };

    systemd.services.postgresql.postStart =
      let
        setRolePassword =
          role: passwordFile:
          let
            query = "SELECT format('ALTER ROLE ${role} PASSWORD %L', pg_read_file('${passwordFile}'))";
          in
          ''
            set -o pipefail
            ${pkgs.postgresql}/bin/psql --set=ON_ERROR_STOP=1 --tuples-only --no-align --command ${lib.escapeShellArg query} \
              | ${pkgs.postgresql}/bin/psql --set=ON_ERROR_STOP=1
          '';
      in
      (lib.optionalString audiomuseDbAvailable (
        setRolePassword "audiomuse" config.sops.secrets.audiomuse_postgres_password.path
      ))
      + (lib.optionalString litellmDbAvailable (
        setRolePassword "litellm" config.sops.secrets.postgres_shared_litellm_password.path
      ));

    # ── Shared PostgreSQL backup coverage ──────────────────────────────────
    # Export-first contract: the native NixOS postgresqlBackup module runs
    # pg_dumpall as the postgres user into the state-backups staging root, so
    # restic captures a logical export instead of the raw live data directory.
    # The restic job Requires+After the export unit, so each backup run
    # generates a fresh consistent dump and aborts when the export fails. The
    # independent postgresqlBackup timer is disabled (startAt = [ ]): the
    # export runs only as a restic prerequisite. *.in-progress* dumps are
    # excluded; all.prev.sql.gz is retained as the previous-good fallback.
    services.postgresqlBackup = lib.mkIf hasDbConsumer {
      enable = true;
      backupAll = true;
      location = "${config.services.state-backups.stagingRoot}/postgres";
      pgdumpAllOptions = "--clean --if-exists -w";
      startAt = [ ];
    };

    systemd.services."restic-backups-${config.services.state-backups.backupName}" =
      lib.mkIf hasDbConsumer
        {
          requires = [ "postgresqlBackup.service" ];
          after = [ "postgresqlBackup.service" ];
        };

    services.state-backups.services.postgres-shared = lib.mkIf hasDbConsumer {
      enable = true;
      mode = "export";
      exportPaths = [ "${config.services.state-backups.stagingRoot}/postgres" ];
      exclude = [ "*.in-progress*" ];
    };
  };
}
