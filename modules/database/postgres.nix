# Shared PostgreSQL mechanism.
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
{
  flake.modules.nixos.postgres =
    {
      config,
      lib,
      pkgs,
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

      # Only consumers with something to apply need the provisioning unit.
      provisionable = lib.filter (c: c.setupSQL != "" || hasCredential c) consumers;

      # The unit runs a fixed trampoline and reads this script from /etc, so the
      # executed consumer set is the current generation's even when systemd starts
      # the unit from the definition it already had loaded (D-069).
      provisionScript = pkgs.writeShellScript "postgresql-provision" ''
        set -euo pipefail
        export PGPORT=${if instance == null then "5432" else toString instance.port}
        # A switch that ships a new server package enqueues postgresql's restart
        # after this unit may already be queued, so `After=` alone can hand us the
        # old process — and CREATE EXTENSION resolves against the server's package.
        # Wait (bounded) for this generation's own server before any SQL runs.
        wantServer=${config.services.postgresql.finalPackage}/bin/postgres
        gotServer=
        for _ in $(seq 1 60); do
          gotServer=
          # Identity = the unit MainPID's command line, not /proc/*/exe: the
          # and-plugins package is a ~70k launcher that execs the shared plain
          # server, so every generation's exe resolves outside its own store
          # path — and a /proc scan is lexicographic (last match nondeterministic
          # between launcher and backends; a scan once "passed" by luck).
          mainPid=$(systemctl show --property=MainPID --value postgresql 2>/dev/null || true)
          if [ -n "${"mainPid:-"}" ] && [ "$mainPid" != "0" ]; then
            gotServer=$(tr "\0" "\n" < "/proc/$mainPid/cmdline" 2>/dev/null | head -n1 || true)
          fi
          if [ "$gotServer" = "$wantServer" ]; then
            break
          fi
          sleep 1
        done
        if [ "$gotServer" != "$wantServer" ]; then
          echo "postgresql-provision: server runs '$gotServer', expected '$wantServer' after 60s" >&2
          exit 1
        fi
        ${lib.concatMapStringsSep "\n" (
          c:
          ensureRole c
          + ensureDatabase c
          + lib.optionalString (hasCredential c) (setRolePassword c)
          + runSetupSQL c
        ) provisionable}
      '';

      # Footgun: pg_hba needs a mask. A maskless address shifts the auth-method
      # column into the netmask field, and postgres refuses to load the whole file.
      withMask =
        cidr:
        if lib.hasInfix "/" cidr then cidr else "${cidr}/${if lib.hasInfix ":" cidr then "128" else "32"}";

      authLine =
        c:
        if c.auth == "peer" then
          [ "local ${c.database} ${c.role} peer" ]
        else
          # One allow row per database per source range, then the role's
          # catch-all reject — everything outside the owned + extra set stays
          # unreachable even though nixpkgs' default block follows ours.
          lib.concatMap (
            cidr:
            map (db: "host ${db} ${c.role} ${withMask cidr} scram-sha-256") ([ c.database ] ++ c.extraDatabases)
          ) c.allowedCIDRs
          ++ [ "host all ${c.role} all reject" ];

      secretName = c: "postgres_${c.name}_password";

      psql = "${config.services.postgresql.finalPackage}/bin/psql";

      # Roles and databases are converged here rather than through nixpkgs'
      # `ensureDatabases`/`ensureUsers`: systemd may start postgresql-setup.service
      # from the definition it already had loaded, which leaves a newly registered
      # consumer's role and database missing for that activation (D-069).
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
          ${psql} --set=ON_ERROR_STOP=1 --tuples-only --no-align --command ${lib.escapeShellArg query} \
            | ${psql} --set=ON_ERROR_STOP=1 ||
              { echo "services.postgres.consumers.${c.name}: failed to apply the role password" >&2; exit 1; }
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
          ++
            # pg_hba is database-scoped: a role that creates satellite databases
            # cannot connect to them through its own catch-all reject, and the
            # stack that requires them dies at first boot. Fail closed here.
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
          services.postgres.enable = true;

          # Defined unconditionally: a projection of the host's own declaration,
          # read by co-located consumers to test for a local cluster even where
          # the mechanism is disabled.
          services.postgres.localEndpoint = if instance == null then null else { inherit (instance) port; };
        }

        (lib.mkIf cfg.enable {
          assertions = map (message: {
            inherit message;
            assertion = false;
          }) errors;

          services.postgresql = lib.mkIf (instance != null) {
            enable = true;
            inherit (instance) dataDir;

            enableTCPIP = true;

            authentication = lib.mkBefore (lib.concatStringsSep "\n" (lib.concatMap authLine consumers));

            # Consumers contribute packages; the mechanism composes them through the
            # instance's own extension set, so a package always matches the server.
            extensions = ps: lib.unique (lib.concatMap (c: c.extensions ps) consumers);

            settings = {
              inherit (instance) port;
              # mkForce: nixpkgs derives "*" from `enableTCPIP`.
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
            # Consumer changes ride postgresql's restart set: systemctl
            # propagates through partOf, so the pair restarts in one ordered
            # transaction and provisioning always starts after this
            # generation's server is live (the trampoline unit itself never
            # changes).
            restartTriggers = lib.optionals (provisionable != [ ]) [ provisionScript ];
            serviceConfig.ReadWritePaths = [ instance.dataDir ];
          };

          # Provisioning is its own unit, ordered after nixpkgs'
          # postgresql-setup.service (which itself runs after postgresql.service, so
          # `postStart` would execute too early on a fresh cluster). Consumer roles,
          # databases, and ownership are converged here, not through nixpkgs'
          # `ensureDatabases`/`ensureUsers` (D-069). `wantedBy` and `partOf` the
          # postgresql target mirror nixpkgs' wiring, so restarting the target
          # re-applies consumer state.
          systemd.services.postgresql-provision = lib.mkIf (instance != null && provisionable != [ ]) {
            description = "PostgreSQL consumer provisioning (roles, databases, credentials, setup SQL)";
            # The requires edge on postgresql is load-bearing for ordering:
            # switch-to-configuration restarts units through their requires
            # graph, so without it provisioning can start (and burn its
            # server-identity wait) before this activation's postgres restart.
            requires = [
              "postgresql-setup.service"
              "postgresql.service"
            ];
            after = [
              "postgresql.service"
              "postgresql-setup.service"
            ];
            wantedBy = [ "postgresql.target" ];
            # Re-run only as a consequence of postgresql's own restart, never
            # as an independent job: switch-to-configuration enqueues the two
            # restarts in nondeterministic order, and an early provisioning
            # attempt (its server-identity guard timing out at 60s) starves the
            # job queue — including postgresql's restart itself — until it
            # fails. The script trigger therefore lives on postgresql below.
            partOf = [
              "postgresql.target"
              "postgresql.service"
            ];
            # Trampoline: the unit's own content never changes with the consumer set,
            # so a stale in-memory definition still executes the current script.
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

          # Export-first contract: restic captures a pg_dumpall export, not the live
          # data directory. The independent postgresqlBackup timer stays disabled
          # (`startAt = [ ]`) — the restic job Requires+After the export — and the
          # staging copy is cleared once the run has uploaded it.
          services.postgresqlBackup = lib.mkIf (consumers != [ ] && config.services.state-backups.enable) {
            enable = true;
            backupAll = true;
            location = "${config.services.state-backups.stagingRoot}/postgres";
            pgdumpAllOptions = "--clean --if-exists -w";
            startAt = [ ];
          };

          systemd.services."restic-backups-${config.services.state-backups.backupName}" =
            lib.mkIf (consumers != [ ] && config.services.state-backups.enable)
              {
                requires = [ "postgresqlBackup.service" ];
                after = [ "postgresqlBackup.service" ];
              };

          # Upstream writes the export into `location` without creating it, and the
          # unit runs as postgres — which cannot create a child of the 0711
          # root-owned staging root. The directory is therefore installed with the
          # dump itself: `+` keeps the create root-privileged while the dump stays
          # postgres-owned, so it works on the first run after a cleanup as well as
          # at boot. The post-restic cleanup still removes it, so no plaintext
          # export outlives the run that uploaded it.
          systemd.services.postgresqlBackup =
            lib.mkIf (consumers != [ ] && config.services.state-backups.enable)
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
        })
      ];
    };
}
