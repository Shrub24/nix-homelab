# Shared PostgreSQL mechanism (modular-postgres-instances, D-058).
#
# Three layers, so adding a consumer or a cluster never means editing this file:
#   * mechanism (here) — renders provisioning from an instance plus a consumer
#     registry; names no consumer and no instance;
#   * instance — a placement aspect imports this mechanism and the host that
#     runs the cluster declares `services.postgres.instances.<name>`;
#   * consumer — a service registers the database, role, credential, and
#     extensions it needs from its own module.
#
# Registrations are keyed by consumer name: a host runs at most one cluster (the
# native PostgreSQL runtime is single-cluster), so `instances.<name>` names the
# cluster for the internal contract while consumers stay instance-free. A
# consumer running on another host is registered here by the *provider*, because
# only the provider can create the role and read its credential — the exception,
# not the rule.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.postgres;

  instanceNames = lib.attrNames cfg.instances;
  instance = if instanceNames == [ ] then null else cfg.instances.${lib.head instanceNames};

  consumers = lib.mapAttrsToList (
    name: entry:
    entry
    // {
      inherit name;
      role = if entry.role == null then name else entry.role;
    }
  ) cfg.consumers;

  hasCredential = c: c.password != null && builtins.pathExists c.password.file;
  credentialled = lib.filter hasCredential (lib.filter (c: c.auth == "scram") consumers);

  # Only consumers with something to apply need the provisioning unit.
  provisionable = lib.filter (c: c.setupSQL != "" || hasCredential c) consumers;
  provisionScript = lib.concatMapStringsSep "\n" (
    c: runSetupSQL c + lib.optionalString (hasCredential c) (setRolePassword c)
  ) provisionable;

  authLine =
    c:
    if c.auth == "peer" then
      [ "local ${c.database} ${c.role} peer" ]
    else
      lib.concatMap (cidr: [ "host ${c.database} ${c.role} ${cidr} scram-sha-256" ]) c.allowedCIDRs
      ++ [ "host all ${c.role} all reject" ];

  secretName = c: "postgres_${c.name}_password";

  # Applies the SOPS-held password to each provider-side role whenever this unit
  # runs, so a rotation takes effect by restarting it.
  setRolePassword =
    c:
    let
      query = "SELECT format('ALTER ROLE ${c.role} PASSWORD %L', pg_read_file('${
        config.sops.secrets.${secretName c}.path
      }'))";
    in
    ''
      # nixpkgs creates the role in postgresql-setup.service, which this unit is
      # ordered after; if it is missing, that ordering was lost — say so instead
      # of failing with an opaque psql error.
      if ! ${config.services.postgresql.finalPackage}/bin/psql -tAc ${lib.escapeShellArg "SELECT 1 FROM pg_roles WHERE rolname = '${c.role}'"} | grep -q 1; then
        echo "services.postgres.consumers.${c.name}: role '${c.role}' does not exist; postgresql-setup.service must run before provisioning" >&2
        exit 1
      fi
      ${config.services.postgresql.finalPackage}/bin/psql --set=ON_ERROR_STOP=1 --tuples-only --no-align --command ${lib.escapeShellArg query} \
        | ${config.services.postgresql.finalPackage}/bin/psql --set=ON_ERROR_STOP=1
    '';

  # Setup SQL runs as ordinary `psql` input; without a named failure a typo would
  # abort the cluster start with no hint of which registration caused it.
  runSetupSQL =
    c:
    lib.optionalString (c.setupSQL != "") ''
      ${config.services.postgresql.finalPackage}/bin/psql --set=ON_ERROR_STOP=1 --no-align --dbname ${lib.escapeShellArg c.database} --command ${lib.escapeShellArg c.setupSQL} || {
        echo "services.postgres.consumers.${c.name}: setupSQL failed against database '${c.database}'; fix the registration, and declare the server package it needs (for example extensions = ps: [ ps.pgvector ])" >&2
        exit 1
      }
    '';

  errors =
    lib.optionals (lib.length instanceNames > 1) [
      "services.postgres declares ${toString (lib.length instanceNames)} instances (${lib.concatStringsSep ", " instanceNames}); the native PostgreSQL runtime is single-cluster, so a host declares at most one"
    ]
    ++ lib.concatMap (
      c:
      lib.optionals (c.auth == "scram" && c.password == null) [
        "services.postgres.consumers.${c.name}: password authentication requires a password { file, key } (use auth = \"peer\" for a host-local consumer over the Unix socket)"
      ]
      ++
        lib.optionals (c.auth == "scram" && c.password != null && !(builtins.pathExists c.password.file))
          [
            "services.postgres.consumers.${c.name}: password file '${toString c.password.file}' does not exist"
          ]
    ) consumers;
in
{
  options.services.postgres = {
    enable = lib.mkEnableOption "the shared PostgreSQL mechanism" // {
      default = false;
    };

    instances = lib.mkOption {
      default = { };
      description = ''
        PostgreSQL clusters this host runs, keyed by the instance name the
        internal contract refers to. Port and data directory are host facts.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            port = lib.mkOption {
              type = lib.types.port;
              description = "TCP port this instance listens on.";
            };
            dataDir = lib.mkOption {
              type = lib.types.str;
              description = "Data directory on the shared service-state mount.";
            };
          };
        }
      );
    };

    localEndpoint = lib.mkOption {
      readOnly = true;
      type = lib.types.nullOr (
        lib.types.submodule {
          options.port = lib.mkOption {
            type = lib.types.port;
            description = "Port of this host's cluster.";
          };
        }
      );
      description = ''
        This host's cluster endpoint when it declares one, so a co-located
        consumer reaches the database directly instead of over the tailnet.
      '';
    };

    consumers = lib.mkOption {
      default = { };
      description = ''
        Databases and roles registered against this host's cluster, keyed by
        consumer name. A consumer registers itself from its own module; the
        mechanism owns provisioning.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            database = lib.mkOption {
              type = lib.types.str;
              description = "Database the consumer owns.";
            };
            role = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Login role owning the database; defaults to the consumer name.";
            };
            auth = lib.mkOption {
              type = lib.types.enum [
                "peer"
                "scram"
              ];
              default = "peer";
              description = ''
                `peer` authenticates a host-local consumer over the Unix socket
                and needs no credential; `scram` provisions a password role
                reachable from the consumer's `allowedCIDRs`.
              '';
            };
            password = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    file = lib.mkOption {
                      type = lib.types.path;
                      description = "SOPS-encrypted file holding this role's password.";
                    };
                    key = lib.mkOption {
                      type = lib.types.str;
                      description = "Key path of this role's password within that file.";
                    };
                  };
                }
              );
              default = null;
              description = ''
                The role's credential, owned by the consumer that uses it. The
                same file and key are read here to provision the role and by the
                consumer to authenticate, so the value has one authoritative
                source.
              '';
            };
            allowedCIDRs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                "100.64.0.0/10"
                "fd7a:115c:a1e0::/48"
              ];
              description = "CIDR ranges allowed to authenticate as this role with password authentication.";
            };
            extensions = lib.mkOption {
              type = lib.types.functionTo (lib.types.listOf lib.types.package);
              default = _: [ ];
              example = lib.literalExpression "ps: [ ps.pgvector ]";
              description = ''
                Server-side extension packages this consumer needs, in the shape
                `services.postgresql.extensions` uses: a function of the
                instance's own extension set, so the package always matches the
                server version. The matching SQL belongs in `setupSQL`.
              '';
            };
            setupSQL = lib.mkOption {
              type = lib.types.lines;
              default = "";
              example = lib.literalExpression ''"CREATE EXTENSION IF NOT EXISTS vector;"'';
              description = ''
                SQL run in this consumer's database on every cluster start, as
                the `postgres` superuser. Must be idempotent.
              '';
            };
          };
        }
      );
    };
  };

  # Single unconditional definition: this is a projection of the host's own
  # declaration, read by co-located consumers, and it exists even when the
  # mechanism is disabled so those consumers can check for a local cluster.
  config = lib.mkMerge [
    {
      # A projection of the host's own declaration, read by co-located consumers;
      # defined unconditionally so those consumers can test for a local cluster
      # even where the mechanism is disabled.
      services.postgres.localEndpoint = if instance == null then null else { inherit (instance) port; };
    }

    (lib.mkIf cfg.enable {
      assertions = map (message: {
        inherit message;
        assertion = false;
      }) errors;

      services.postgresql = lib.mkIf (instance != null) {
        enable = true;
        dataDir = instance.dataDir;

        enableTCPIP = true;

        ensureDatabases = lib.unique (map (c: c.database) consumers);

        ensureUsers = lib.unique (
          map (
            c:
            {
              name = c.role;
              ensureDBOwnership = true;
            }
            // lib.optionalAttrs (c.auth == "scram") { ensureClauses.login = true; }
          ) consumers
        );

        authentication = lib.mkBefore (lib.concatStringsSep "\n" (lib.concatMap authLine consumers));

        # Consumers contribute packages; the mechanism composes them through the
        # instance's own extension set, so a package always matches the server.
        extensions = ps: lib.unique (lib.concatMap (c: c.extensions ps) consumers);

        settings = {
          port = instance.port;
          max_connections = lib.mkDefault "40";
          shared_buffers = lib.mkDefault "64MB";
          effective_cache_size = lib.mkDefault "128MB";
          maintenance_work_mem = lib.mkDefault "16MB";
          wal_buffers = lib.mkDefault "4MB";
          random_page_cost = lib.mkDefault "1.1";
          effective_io_concurrency = lib.mkDefault "200";
          work_mem = lib.mkDefault "4MB";
          huge_pages = lib.mkDefault "off";
        };
      };

      sops.secrets = lib.mkIf (instance != null) (
        lib.listToAttrs (
          map (
            c:
            lib.nameValuePair (secretName c) {
              sopsFile = c.password.file;
              key = c.password.key;
              path = "/run/secrets/postgres/${c.name}.password";
              owner = "postgres";
              group = "postgres";
              mode = "0400";
              restartUnits = [ "postgresql-provision.service" ];
            }
          ) credentialled
        )
      );

      systemd.services.postgresql = lib.mkIf (instance != null) {
        serviceConfig.ReadWritePaths = [ instance.dataDir ];
      };

      # Provisioning is its own unit, ordered after nixpkgs'
      # postgresql-setup.service: that unit creates the databases and roles and
      # runs *after* postgresql.service, so `postStart` would execute too early on
      # a fresh cluster and fail on a role that does not exist yet. `wantedBy` and
      # `partOf` the postgresql target mirror nixpkgs' wiring, so restarting the
      # target re-applies credentials.
      systemd.services.postgresql-provision = lib.mkIf (instance != null && provisionable != [ ]) {
        description = "PostgreSQL consumer provisioning (role credentials, setup SQL)";
        requires = [ "postgresql-setup.service" ];
        after = [
          "postgresql.service"
          "postgresql-setup.service"
        ];
        wantedBy = [ "postgresql.target" ];
        partOf = [ "postgresql.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          Group = "postgres";
        };
        path = [ pkgs.postgresql ];
        script = "set -o pipefail\n" + provisionScript;
      };

      systemd.tmpfiles.rules = lib.optionals (instance != null) [
        "d ${instance.dataDir} 0700 postgres postgres - -"
      ];

      # ── Backup coverage ────────────────────────────────────────────────────
      # Export-first contract: the native NixOS postgresqlBackup module runs
      # pg_dumpall as the postgres user into the state-backups staging root, so
      # restic captures a logical export instead of the raw live data directory.
      # The restic job Requires+After the export unit, so each backup run
      # generates a fresh consistent dump and aborts when the export fails. The
      # independent postgresqlBackup timer is disabled (startAt = [ ]): the
      # export runs only as a restic prerequisite. *.in-progress* dumps are
      # excluded; all.prev.sql.gz is retained as the previous-good fallback.
      services.postgresqlBackup = lib.mkIf (consumers != [ ]) {
        enable = true;
        backupAll = true;
        location = "${config.services.state-backups.stagingRoot}/postgres";
        pgdumpAllOptions = "--clean --if-exists -w";
        startAt = [ ];
      };

      systemd.services."restic-backups-${config.services.state-backups.backupName}" =
        lib.mkIf (consumers != [ ])
          {
            requires = [ "postgresqlBackup.service" ];
            after = [ "postgresqlBackup.service" ];
          };

      services.state-backups.services.postgres = lib.mkIf (consumers != [ ]) {
        enable = true;
        mode = "export";
        exportPaths = [ "${config.services.state-backups.stagingRoot}/postgres" ];
        exclude = [ "*.in-progress*" ];
      };
    })
  ];
}
