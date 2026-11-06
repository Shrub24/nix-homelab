# Shared PostgreSQL mechanism: renders provisioning from `services.postgres.instances` and `.consumers`.
# Names no consumer or instance; a consumer on another host is registered by the provider, which alone can create its role.
_: {
  flake.modules.nixos.postgres =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.services.postgres;

      netHelpers = import ../../lib/networking.nix { inherit lib; };
      serviceNetwork = (import ../../policy/globals.nix).serviceNetwork;

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

      hasCredential = c: c.password != null;

      # Every role provisioned with a password: a scram-authenticated owning role, plus each
      # additional restricted login the consumer declares.
      passwordRoles = lib.concatMap (
        c:
        lib.optional (c.auth == "scram" && hasCredential c) {
          consumer = c;
          inherit (c) role;
          inherit (c) password;
        }
        ++ lib.mapAttrsToList (role: r: {
          consumer = c;
          inherit role;
          inherit (r) password;
        }) c.additionalRoles
      ) consumers;

      provisionEtcName = "postgres/provision.sh";
      provisionScriptPath = "/etc/${provisionEtcName}";

      provisionable = lib.filter (
        c: c.setupSQL != "" || hasCredential c || c.additionalRoles != { }
      ) consumers;

      # The trampoline reads its script from /etc, so a stale definition still runs the current consumer set.
      provisionScript = pkgs.writeShellScript "postgresql-provision" ''
        set -euo pipefail
        export PGPORT=${if instance == null then "5432" else toString instance.port}
        ${lib.concatMapStringsSep "\n" (
          c:
          ensureRole c c.role
          + ensureDatabase c
          + lib.optionalString (c.auth == "scram" && hasCredential c) (applyPassword c c.role)
          + lib.concatMapStringsSep "\n" (role: ensureRole c role + applyPassword c role) (
            lib.attrNames c.additionalRoles
          )
          + runSetupSQL c
        ) provisionable}
      '';

      # Footgun: pg_hba needs a mask; without one postgres refuses to load the whole file.
      withMask =
        cidr:
        if lib.hasInfix "/" cidr then cidr else "${cidr}/${if lib.hasInfix ":" cidr then "128" else "32"}";

      authLine =
        c:
        (
          if c.auth == "peer" then
            [ "local ${c.database} ${c.role} peer" ]
          else
            # Owned and extra databases get one allow row each; the role's catch-all reject follows.
            lib.concatMap (
              cidr:
              map (db: "host ${db} ${c.role} ${withMask cidr} scram-sha-256") ([ c.database ] ++ c.extraDatabases)
            ) c.allowedCIDRs
            ++ [ "host all ${c.role} all reject" ]
        )
        # An additional login reaches this consumer's database only, so its allow rows and its own
        # catch-all reject follow the owning role's.
        ++ lib.concatMap (
          role:
          lib.concatMap (cidr: [ "host ${c.database} ${role} ${withMask cidr} scram-sha-256" ]) c.allowedCIDRs
          ++ [ "host all ${role} all reject" ]
        ) (lib.attrNames c.additionalRoles);

      # One encrypted password per login. A consumer's owning role keeps the original name and
      # path, so an existing deployment re-reads the same file.
      passwordSecret =
        c: role: "postgres_${c.name}${lib.optionalString (role != c.role) "_${role}"}_password";
      passwordPath =
        c: role:
        "/run/secrets/postgres/${c.name}${lib.optionalString (role != c.role) "-${role}"}.password";

      psql = "${config.services.postgresql.finalPackage}/bin/psql";

      # Converged here, not via ensureDatabases: a start from a stale definition would skip a new consumer.
      # Any role other than the consumer's owner is a login; the owner is one only when the consumer
      # authenticates with a password.
      ensureRole = c: role: ''
        if [ "$(${psql} -tAc ${lib.escapeShellArg "SELECT 1 FROM pg_roles WHERE rolname = '${role}'"})" != "1" ]; then
          ${psql} -tAc ${lib.escapeShellArg "CREATE ROLE \"${role}\""} ||
            { echo "services.postgres.consumers.${c.name}: failed to create role '${role}'" >&2; exit 1; }
        fi
        ${lib.optionalString (role != c.role || c.auth == "scram") ''
          ${psql} -tAc ${lib.escapeShellArg "ALTER ROLE \"${role}\" LOGIN"} ||
            { echo "services.postgres.consumers.${c.name}: failed to enable login for role '${role}'" >&2; exit 1; }
        ''}
      '';

      ensureDatabase = c: ''
        if [ "$(${psql} -tAc ${lib.escapeShellArg "SELECT 1 FROM pg_database WHERE datname = '${c.database}'"})" != "1" ]; then
          ${psql} -tAc ${lib.escapeShellArg "CREATE DATABASE \"${c.database}\""} ||
            { echo "services.postgres.consumers.${c.name}: failed to create database '${c.database}'" >&2; exit 1; }
        fi
        ${psql} -tAc ${lib.escapeShellArg "ALTER DATABASE \"${c.database}\" OWNER TO \"${c.role}\""} ||
          { echo "services.postgres.consumers.${c.name}: failed to make '${c.role}' own '${c.database}'" >&2; exit 1; }
      '';

      # Restarting this unit re-applies a rotated password.
      applyPassword =
        c: role:
        let
          query = "SELECT format('ALTER ROLE ${role} PASSWORD %L', pg_read_file('${passwordPath c role}'))";
        in
        ''
          ${psql} --set=ON_ERROR_STOP=1 --tuples-only --no-align --command ${lib.escapeShellArg query} \
            | ${psql} --set=ON_ERROR_STOP=1 ||
              { echo "services.postgres.consumers.${c.name}: failed to apply the password for role '${role}'" >&2; exit 1; }
        '';

      # Named failure: a setup-SQL typo otherwise aborts the cluster start with no hint of its source.
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
          ++
            # pg_hba is database-scoped: without these, satellite databases fail at first boot.
            lib.optionals (lib.hasInfix "CREATEDB" c.setupSQL && c.extraDatabases == [ ]) [
              "services.postgres.consumers.${c.name}: setupSQL grants CREATEDB but extraDatabases is empty — declare every database the role creates (and 'postgres', where it first connects to create them), or its own 'host all <role> all reject' row will refuse them"
            ]
          ++ lib.optionals (lib.hasAttr c.role c.additionalRoles) [
            "services.postgres.consumers.${c.name}: additionalRoles.${c.role} collides with the consumer's owning role"
          ]
          ++ lib.concatMap (
            role:
            lib.optionals (!(builtins.pathExists c.additionalRoles.${role}.password.file)) [
              "services.postgres.consumers.${c.name}: additionalRoles.${role} password file '${
                toString c.additionalRoles.${role}.password.file
              }' does not exist"
            ]
          ) (lib.attrNames c.additionalRoles)
        ) consumers
        # One login carries one password and one set of HBA rows, so a name declared by two
        # consumers would have them applied in turn and shadow each other.
        ++ (
          let
            logins = lib.concatMap (
              c:
              map (role: {
                inherit role;
                consumer = c.name;
              }) ([ c.role ] ++ lib.attrNames c.additionalRoles)
            ) consumers;
            shared = lib.filter (
              role: lib.length (lib.unique (map (l: l.consumer) (lib.filter (l: l.role == role) logins))) > 1
            ) (lib.unique (map (l: l.role) logins));
          in
          lib.optionals (shared != [ ]) [
            "services.postgres: a login name belongs to one consumer, but ${lib.concatStringsSep ", " shared} is declared by more than one"
          ]
        );
    in
    {
      imports = [
        ./postgres/_consumer.nix
        ../backups/state-backups/_consumer.nix
      ];

      config = lib.mkMerge [
        {

          # Read by co-located consumers to detect a local cluster.
          services.postgres.localEndpoint = if instance == null then null else { inherit (instance) port; };
        }

        {
          assertions = map (message: {
            inherit message;
            assertion = false;
          }) errors;

          services.postgresql = lib.mkIf (instance != null) {
            enable = true;
            inherit (instance) dataDir;

            # Pinned: a default bump would start the new major against this data directory and fail at boot.
            package = pkgs.postgresql_17;

            enableTCPIP = true;

            authentication = lib.mkBefore (lib.concatStringsSep "\n" (lib.concatMap authLine consumers));

            # Consumers contribute packages; the instance's extension set keeps them matched to the server.
            extensions = ps: lib.unique (lib.concatMap (c: c.extensions ps) consumers);

            settings = {
              inherit (instance) port;
              listen_addresses = lib.mkForce "127.0.0.1,${serviceNetwork.address}";
              # 100 fits the whole consumer set: at 40 the cluster sat at 35 live connections.
              max_connections = lib.mkDefault "100";
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
                p:
                lib.nameValuePair (passwordSecret p.consumer p.role) {
                  sopsFile = p.password.file;
                  key = p.password.key;
                  path = passwordPath p.consumer p.role;
                  owner = "postgres";
                  group = "postgres";
                  mode = "0400";
                  restartUnits = [ "postgresql-provision.service" ];
                }
              ) passwordRoles
            )
          );

          systemd.services.postgresql = lib.mkIf (instance != null) {
            # A provisioning-script change restarts postgresql; partOf carries the restart to provisioning.
            # The rendered `pg_hba.conf` sits at a store path, which the data-dir symlink only picks up
            # on start, so a new consumer's access rules take effect through this restart — the
            # trampoline above never changes with the consumer set.
            restartTriggers =
              lib.optionals (provisionable != [ ]) [ provisionScript ]
              ++ lib.optional (instance != null) config.services.postgresql.authentication;
            serviceConfig.ReadWritePaths = [ instance.dataDir ];
          };

          # Ordered after nixpkgs' postgresql-setup, which runs too early for postStart on a fresh cluster.
          # wantedBy and partOf mirror nixpkgs, so restarting the target re-applies consumer state.
          systemd.services.postgresql-provision = lib.mkIf (instance != null && provisionable != [ ]) {
            description = "PostgreSQL consumer provisioning (roles, databases, credentials, setup SQL)";
            # requires makes a postgresql restart reach this unit; the script applies its SQL to whatever server is live.
            requires = [
              "postgresql-setup.service"
              "postgresql.service"
            ];
            after = [
              "postgresql.service"
              "postgresql-setup.service"
            ];
            wantedBy = [ "postgresql.target" ];
            # Re-run on postgresql restart (partOf); the script trigger lives on postgresql.
            partOf = [
              "postgresql.target"
              "postgresql.service"
            ];
            # Trampoline: its content never changes with the consumer set.
            script = "exec ${provisionScriptPath}";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              User = "postgres";
              Group = "postgres";
            };
          };

          environment.etc = lib.mkIf (instance != null && provisionable != [ ]) {
            "${provisionEtcName}".source = provisionScript;
          };

          systemd.tmpfiles.rules = lib.optionals (instance != null) [
            "d ${instance.dataDir} 0700 postgres postgres - -"
          ];

          # Export-first: restic captures a pg_dumpall export, not the data directory; the timer is disabled.
          services.postgresqlBackup =
            lib.mkIf
              (consumers != [ ] && lib.hasAttrByPath [ "services" "state-backups" "restoreStagePackage" ] options)
              {
                enable = true;
                backupAll = true;
                location = "${config.services.state-backups.stagingRoot}/postgres";
                pgdumpAllOptions = "--clean --if-exists -w";
                startAt = [ ];
              };

          systemd.services."restic-backups-${config.services.state-backups.backupName}" =
            lib.mkIf
              (consumers != [ ] && lib.hasAttrByPath [ "services" "state-backups" "restoreStagePackage" ] options)
              {
                requires = [ "postgresqlBackup.service" ];
                after = [ "postgresqlBackup.service" ];
              };

          # The dump directory is created with `+` (root) while the dump stays postgres-owned, so the first run after a cleanup works.
          # The post-restic cleanup removes it, so no plaintext export outlives its run.
          systemd.services.postgresqlBackup =
            lib.mkIf
              (consumers != [ ] && lib.hasAttrByPath [ "services" "state-backups" "restoreStagePackage" ] options)
              {
                serviceConfig.ExecStartPre = [
                  "+${pkgs.coreutils}/bin/install -d -m 0700 -o postgres -g postgres ${config.services.state-backups.stagingRoot}/postgres"
                ];
              };

          services.state-backups.services.postgres = lib.mkIf (consumers != [ ]) {
            enable = true;
            mode = "export";
            exportPaths = [ "${config.services.state-backups.stagingRoot}/postgres" ];
            exclude = [ "*.in-progress*" ];
            cleanupCommands = [
              "${pkgs.coreutils}/bin/rm -rf ${config.services.state-backups.stagingRoot}/postgres"
            ];
          };

          networking.firewall.extraCommands = lib.mkIf (consumers != [ ] && instance != null) (
            netHelpers.mkServiceIngressRule {
              sourceCIDR = serviceNetwork.containerSourceCIDR;
              address = serviceNetwork.address;
              ports = [ instance.port ];
            }
          );
        }
      ];
    };
}
