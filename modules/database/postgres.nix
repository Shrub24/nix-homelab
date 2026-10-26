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

      hasCredential = c: c.password != null && builtins.pathExists c.password.file;
      credentialled = lib.filter hasCredential (lib.filter (c: c.auth == "scram") consumers);

      provisionEtcName = "postgres/provision.sh";
      provisionScriptPath = "/etc/${provisionEtcName}";

      provisionable = lib.filter (c: c.setupSQL != "" || hasCredential c) consumers;

      # The trampoline reads its script from /etc, so a stale definition still runs the current consumer set.
      provisionScript = pkgs.writeShellScript "postgresql-provision" ''
        set -euo pipefail
        export PGPORT=${if instance == null then "5432" else toString instance.port}
        ${lib.concatMapStringsSep "\n" (
          c:
          ensureRole c
          + ensureDatabase c
          + lib.optionalString (hasCredential c) (setRolePassword c)
          + runSetupSQL c
        ) provisionable}
      '';

      # Footgun: pg_hba needs a mask; without one postgres refuses to load the whole file.
      withMask =
        cidr:
        if lib.hasInfix "/" cidr then cidr else "${cidr}/${if lib.hasInfix ":" cidr then "128" else "32"}";

      authLine =
        c:
        if c.auth == "peer" then
          [ "local ${c.database} ${c.role} peer" ]
        else
          # Owned and extra databases get one allow row each; the role's catch-all reject follows.
          lib.concatMap (
            cidr:
            map (db: "host ${db} ${c.role} ${withMask cidr} scram-sha-256") ([ c.database ] ++ c.extraDatabases)
          ) c.allowedCIDRs
          ++ [ "host all ${c.role} all reject" ];

      secretName = c: "postgres_${c.name}_password";

      psql = "${config.services.postgresql.finalPackage}/bin/psql";

      # Converged here, not via ensureDatabases: a start from a stale definition would skip a new consumer.
      ensureRole = c: ''
        if [ "$(${psql} -tAc ${lib.escapeShellArg "SELECT 1 FROM pg_roles WHERE rolname = '${c.role}'"})" != "1" ]; then
          ${psql} -tAc ${lib.escapeShellArg "CREATE ROLE \"${c.role}\""} ||
            { echo "services.postgres.consumers.${c.name}: failed to create role '${c.role}'" >&2; exit 1; }
        fi
        ${loginClause c}
      '';

      loginClause =
        c:
        lib.optionalString (c.auth == "scram") ''
          ${psql} -tAc ${lib.escapeShellArg "ALTER ROLE \"${c.role}\" LOGIN"} ||
            { echo "services.postgres.consumers.${c.name}: failed to enable login for role '${c.role}'" >&2; exit 1; }
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
      setRolePassword =
        c:
        let
          query = "SELECT format('ALTER ROLE ${c.role} PASSWORD %L', pg_read_file('${
            config.sops.secrets.${secretName c}.path
          }'))";
        in
        ''
          ${psql} --set=ON_ERROR_STOP=1 --tuples-only --no-align --command ${lib.escapeShellArg query} \
            | ${psql} --set=ON_ERROR_STOP=1 ||
              { echo "services.postgres.consumers.${c.name}: failed to apply the role password" >&2; exit 1; }
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
        ) consumers;
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
            # A provisioning-script change restarts postgresql; partOf carries the restart to provisioning.
            restartTriggers = lib.optionals (provisionable != [ ]) [ provisionScript ];
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
