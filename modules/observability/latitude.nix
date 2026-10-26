# Agent-failure triage console (Latitude), beside langfuse on home-forge.
# Stateful roles are native; Temporal and the application roles are digest-pinned containers, with no published ports.
{
  config,
  inputs,
  ...
}:
let
  globals = import ../../policy/globals.nix;
  # Fallback for hosts without the gateway; the local listener wins in the module body.
  bifrostCanonicalUrl =
    (inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet {
      service = "bifrost";
      endpoint = "embeddings";
      via = "tailnet";
    }).url;
in
{
  flake.modules.nixos.latitude =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.latitude;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      hasSecretFile = cfg.secretFiles.host != null;

      globals = import ../../policy/globals.nix;
      loopback = "127.0.0.1";
      serviceAddress = globals.serviceNetwork.address;
      serviceHost = globals.serviceNetwork.hostName;
      containerSourceCIDR = globals.serviceNetwork.containerSourceCIDR;
      # Mounted at the same path in every application container.
      storageMount = "--volume=${cfg.dataDir}/storage:/state/storage";
      netHelpers = import ../../lib/networking.nix { inherit lib; };

      # Bare origin from the local listener; the /v1 prefix is appended here.
      hasLocalBifrost = lib.hasAttrByPath [ "services" "bifrost" "localEndpoint" ] options;
      bifrostBaseUrl =
        if hasLocalBifrost then "${config.services.bifrost.localEndpoint.url}/v1" else bifrostCanonicalUrl;

      # The browser calls the API origin directly; upstream has no proxy.
      catalog = config.repo.web.catalog;
      webUrl = catalog.latitude.publicUrl or null;
      apiUrl = catalog."latitude-api".publicUrl or null;
      # Ingest is a tailnet machine endpoint: the catalog endpoint is loopback on its own host, so the tailnet name is composed here.
      ingestPort = catalog."latitude-ingest".endpoint.port or cfg.ingestPort;
      ingestUrl = "http://${config.networking.hostName}.${globals.tailnet.suffix}:${toString ingestPort}";

      # HTTP port is fleet policy: Home Assistant owns 8123 on this host.
      clickhouseUrl = "http://${serviceHost}:${toString globals.observability.clickhouseHttpPort}";

      # No substitution file: a second one shadows the first's variables on ClickHouse >= 26.8.
      # Also the unit's restart trigger, since ClickHouse does not watch users.d.
      clickhouseUsers = lib.optionalString hasSecretFile ''
        <clickhouse>
          <users>
            <latitude>
              <profile>default</profile>
              <quota>default</quota>
              <networks><ip>${loopback}</ip><ip>::1</ip><ip>${serviceAddress}</ip><ip>${containerSourceCIDR}</ip></networks>
              <no_password/>
            </latitude>
          </users>
        </clickhouse>
      '';

      # Temporal reads no LAT_* variables, so it is excluded.
      appServices = [
        "web"
        "api"
        "ingest"
        "workers"
        "workflows"
      ];

      # One shared set for the whole stack; absent until the secret file is encrypted.
      appEnv = lib.optionalAttrs hasSecretFile {
        environmentFiles = [ config.sops.templates."latitude.environment".path ];
      };

      # Temporal's auto-setup reads POSTGRES_* names, so it gets its own file.
      temporalEnv = lib.optionalAttrs hasSecretFile {
        environmentFiles = [ config.sops.templates."latitude-temporal.environment".path ];
      };

      appUnitDeps = [
        "network-online.target"
        "clickhouse.service"
        "postgresql.service"
        "postgresql-provision.service"
        "redis-latitude.service"
        "redis-latitude-queue.service"
        "podman-latitude-temporal.service"
        "latitude-migrations.service"
      ];

      appUnitRequires = [
        "postgresql-provision.service"
        "podman-latitude-temporal.service"
        "latitude-migrations.service"
      ];

      # Roles abort on refused connections and switch-to-configuration cannot order their restarts;
      # wait for the endpoints they dial instead.
      waitForDeps = pkgs.writeShellScript "latitude-wait-for-deps" ''
        set -u
        deadline=$(( SECONDS + 120 ))
        for target in \
          ${serviceAddress}:5432 \
          ${serviceAddress}:${toString globals.observability.clickhouseHttpPort} \
          ${serviceAddress}:${toString cfg.redisPort} \
          ${serviceAddress}:${toString cfg.redisQueuePort} \
          ${serviceAddress}:${toString cfg.temporalPort}
        do
          host=''${target%:*}
          port=''${target##*:}
          while ! (echo > "/dev/tcp/$host/$port") 2>/dev/null; do
            if (( SECONDS >= deadline )); then
              echo "latitude: $host:$port still refused after 120s" >&2
              exit 1
            fi
            sleep 2
          done
        done
      '';
    in
    {
      imports = [ ../database/postgres/_consumer.nix ];

      options.services.latitude = {
        images = {
          web = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitude.web;
            description = "Latitude web (SPA server) container image reference.";
          };
          api = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitude.api;
            description = "Latitude API container image reference.";
          };
          ingest = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitude.ingest;
            description = "Latitude OTLP ingest container image reference.";
          };
          workers = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitude.workers;
            description = "Latitude BullMQ workers container image reference.";
          };
          workflows = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitude.workflows;
            description = "Latitude Temporal workers container image reference.";
          };
          migrations = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitude.migrations;
            description = "Latitude one-shot migration image reference (PostgreSQL + ClickHouse).";
          };
          temporal = lib.mkOption {
            type = lib.types.str;
            default = config.repo.ociImages.latitudeTemporal;
            description = "Temporal auto-setup container image reference (schema setup plus server).";
          };
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/storage/latitude";
          description = "Host directory holding Latitude's own state (object store, Redis AOF).";
        };

        webPort = lib.mkOption {
          type = lib.types.port;
          default = 3110;
          description = "Host port the web container serves the UI on (upstream's 3000 belongs to Grafana, not Langfuse).";
        };

        apiPort = lib.mkOption {
          type = lib.types.port;
          default = 3001;
          description = "Host port the API container serves on.";
        };

        ingestPort = lib.mkOption {
          type = lib.types.port;
          default = 3002;
          description = "Host port the OTLP/HTTP ingest container serves on.";
        };

        workersHealthPort = lib.mkOption {
          type = lib.types.port;
          default = 9092;
          description = "Host port the workers role serves its health endpoint on (upstream's 9090 is cockpit's socket).";
        };

        workflowsHealthPort = lib.mkOption {
          type = lib.types.port;
          default = 9091;
          description = "Host port the workflows role serves its health endpoint on.";
        };

        temporalPort = lib.mkOption {
          type = lib.types.port;
          default = 7233;
          description = "Host port the Temporal frontend serves on.";
        };

        redisPort = lib.mkOption {
          type = lib.types.port;
          default = 6381;
          description = "Host port of the cache Redis instance (langfuse owns 6379).";
        };

        redisQueuePort = lib.mkOption {
          type = lib.types.port;
          default = 6382;
          description = "Host port of the BullMQ Redis instance.";
        };

        clickhouseUser = lib.mkOption {
          type = lib.types.str;
          default = "latitude";
          description = "ClickHouse user Latitude authenticates as.";
        };

        clickhouseDatabase = lib.mkOption {
          type = lib.types.str;
          default = "latitude";
          description = "Dedicated ClickHouse database Latitude owns.";
        };

        smtp = {
          host = lib.mkOption {
            type = lib.types.str;
            default = "smtp.resend.com";
            description = "SMTP host for magic-link sign-in (Resend's relay by default).";
          };
          port = lib.mkOption {
            type = lib.types.port;
            default = 587;
            description = "SMTP submission port.";
          };
          username = lib.mkOption {
            type = lib.types.str;
            default = "resend";
            description = "SMTP username (Resend's relay takes the literal account name).";
          };
          from = lib.mkOption {
            type = lib.types.str;
            default = "latitude@${globals.domain}";
            description = "From address on magic-link mail.";
          };
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "latitude-host-secrets";
      };

      config = lib.mkMerge [

        {
          assertions = [
            {
              assertion = webUrl != null;
              message = "services.latitude: the web catalog entry 'latitude' is missing from policy/web-services.nix; magic-link sign-in mints its redirect from that public URL.";
            }
            {
              assertion = apiUrl != null;
              message = "services.latitude: the web catalog entry 'latitude-api' is missing from policy/web-services.nix; the browser calls the API on that origin.";
            }
            {
              assertion = config.services.clickhouse.enable;
              message = "services.latitude.enable is true but the ClickHouse substrate is not selected (select the clickhouse aspect): its trace store has no server otherwise.";
            }
            {
              # Redis instances get per-instance users; an undeclared tmpfiles owner fails activation
              # with 'Unknown user', and redis exits on a missing dir.
              assertion = lib.all (u: config.users.users ? ${u}) [
                "root"
                "redis-latitude"
                "redis-latitude-queue"
              ];
              message = "latitude: a tmpfiles rule owner is not a declared user; use the per-instance nixpkgs user (redis-<instance>), not bare 'redis'.";
            }
          ];

          # BYPASSRLS satisfies the schema-owning admin URL; CREATEDB lets Temporal create its databases.
          # Stays on wal_level=replica: upstream's checklist needs only the vector extension.
          services.postgres.consumers.latitude = lib.mkIf hasSecretFile {
            database = "latitude";
            role = "latitude";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "database/password";
            };
            allowedCIDRs = [
              "127.0.0.1/32"
              "::1/128"
              serviceAddress
              containerSourceCIDR
            ];
            # pg_hba is database-scoped: without these, Temporal's auto-setup hits the catch-all reject.
            extraDatabases = [
              "temporal"
              "temporal_visibility"
              "postgres"
            ];
            extensions = ps: [ ps.pgvector ];
            setupSQL = ''
              CREATE EXTENSION IF NOT EXISTS vector;
              ALTER ROLE latitude BYPASSRLS;
              ALTER ROLE latitude CREATEDB;
            '';
          };

          environment.etc."clickhouse-server/users.d/300-latitude.xml" = lib.mkIf hasSecretFile {
            text = clickhouseUsers;
          };

          # Ephemeral (no RDB or AOF); upstream has no password for this role, so loopback plus the service address scope it.
          services.redis.servers.latitude = {
            enable = true;
            bind = "${loopback} ${serviceAddress}";
            port = cfg.redisPort;
            save = [ ];
            appendOnly = false;
            # Without a password, protected mode rejects the service-address dial with EPIPE; the bind is the scope.
            settings.protected-mode = "no";
            # State lives on the storage mount, not nixpkgs' default.
            settings.dir = lib.mkForce "${cfg.dataDir}/redis-cache";
          };

          # BullMQ needs append-only persistence and no eviction; it cannot share the cache policy.
          services.redis.servers.latitude-queue = {
            enable = true;
            bind = "${loopback} ${serviceAddress}";
            port = cfg.redisQueuePort;
            save = [ ];
            appendOnly = true;
            requirePassFile =
              if hasSecretFile then config.sops.secrets.latitude_redis_queue_password.path else null;
            settings.dir = lib.mkForce "${cfg.dataDir}/redis-queue";
            settings.maxmemory-policy = "noeviction";
          };

          sops.templates."latitude.environment" = lib.mkIf hasSecretFile {
            owner = "root";
            group = "root";
            mode = "0400";
            # Read at container start, not from the unit text: a content change must restart.
            restartUnits = map (name: "podman-latitude-${name}.service") appServices;
            content = ''
              # The web origin is gated by Access; the API carries no gate, Latitude's own auth applies.
              LAT_WEB_URL=${webUrl}
              LAT_WEB_PORT=${toString cfg.webPort}
              LAT_API_URL=${apiUrl}
              LAT_API_PORT=${toString cfg.apiPort}
              LAT_INGEST_URL=${ingestUrl}
              LAT_INGEST_PORT=${toString cfg.ingestPort}
              LAT_TRUSTED_ORIGINS=${webUrl}
              LAT_CORS_ALLOWED_ORIGINS=${webUrl}

              LAT_DATABASE_URL=postgres://latitude:${config.sops.placeholder.latitude_postgres_password}@${serviceHost}:5432/latitude
              LAT_ADMIN_DATABASE_URL=postgres://latitude:${config.sops.placeholder.latitude_postgres_password}@${serviceHost}:5432/latitude

              LAT_CLICKHOUSE_URL=${clickhouseUrl}
              LAT_CLICKHOUSE_USER=${cfg.clickhouseUser}
              LAT_CLICKHOUSE_PASSWORD=${config.sops.placeholder.latitude_clickhouse_password}
              LAT_CLICKHOUSE_DB=${cfg.clickhouseDatabase}
              # The migrations script rebuilds user:password@host:port/db itself; credentials or a db path here get appended again.
              LAT_CLICKHOUSE_MIGRATION_URL=clickhouse://${serviceHost}:9000
              LAT_CLICKHOUSE_CLUSTER_ENABLED=false

              LAT_REDIS_HOST=${serviceHost}
              LAT_REDIS_PORT=${toString cfg.redisPort}
              LAT_BULLMQ_HOST=${serviceHost}
              LAT_BULLMQ_PORT=${toString cfg.redisQueuePort}
              LAT_BULLMQ_PASSWORD=${config.sops.placeholder.latitude_redis_queue_password}

              LAT_TEMPORAL_ADDRESS=${serviceHost}:${toString cfg.temporalPort}
              LAT_TEMPORAL_NAMESPACE=default
              LAT_TEMPORAL_TASK_QUEUE=latitude-workflows

              LAT_STORAGE_DRIVER=fs
              LAT_STORAGE_FS_ROOT=/state/storage

              LAT_MASTER_ENCRYPTION_KEY=${config.sops.placeholder.latitude_master_encryption_key}
              LAT_BETTER_AUTH_SECRET=${config.sops.placeholder.latitude_better_auth_secret}

              # Enabled only when both values are set; the OAuth callback must be ${webUrl}/api/auth/callback/github exactly.
              LAT_GITHUB_CLIENT_ID=${config.sops.placeholder.latitude_github_client_id}
              LAT_GITHUB_CLIENT_SECRET=${config.sops.placeholder.latitude_github_client_secret}

              # All six or none: a partial set hides the integration. The private key is the base64 of the .pem.
              LAT_GITHUB_APP_ID=${config.sops.placeholder.latitude_github_app_id}
              LAT_GITHUB_APP_SLUG=${config.sops.placeholder.latitude_github_app_slug}
              LAT_GITHUB_APP_PRIVATE_KEY=${config.sops.placeholder.latitude_github_app_private_key}
              LAT_GITHUB_WEBHOOK_SECRET=${config.sops.placeholder.latitude_github_webhook_secret}
              LAT_GITHUB_APP_CLIENT_ID=${config.sops.placeholder.latitude_github_app_client_id}
              LAT_GITHUB_APP_CLIENT_SECRET=${config.sops.placeholder.latitude_github_app_client_secret}

              # Magic-link sign-in: this transport is required.
              LAT_SMTP_HOST=${cfg.smtp.host}
              LAT_SMTP_PORT=${toString cfg.smtp.port}
              LAT_SMTP_USER=${cfg.smtp.username}
              LAT_SMTP_PASS=${config.sops.placeholder.latitude_smtp_password}
              LAT_SMTP_FROM=${cfg.smtp.from}

              # Embeddings go through the fleet gateway; the voyage-4 dimension mapping is the normalizer's job.
              # The embedding model is fixed: switching later breaks semantic search, since rows are never re-embedded.
              LAT_CUSTOM_AI_BASE_URL=${bifrostBaseUrl}
              LAT_CUSTOM_AI_API_KEY=bifrost-local
              LAT_AI_GENERATION_PROVIDER=custom
              LAT_AI_GENERATION_MODEL=${globals.bifrost.aliases.text}
              LAT_AI_EMBEDDING_PROVIDER=custom
              LAT_AI_EMBEDDING_MODEL=${globals.bifrost.aliases.embedding}

              # Pinned: upstream's default 9090 is cockpit's socket on this host, and a collision exits silently.
              LAT_WORKERS_HEALTH_PORT=${toString cfg.workersHealthPort}
              LAT_WORKFLOWS_HEALTH_PORT=${toString cfg.workflowsHealthPort}

              LAT_BILLING_ENABLED=false
            '';
          };

          sops.templates."latitude-temporal.environment" = lib.mkIf hasSecretFile {
            owner = "root";
            group = "root";
            mode = "0400";
            # Read at container start, not from the unit text: a content change must restart.
            restartUnits = [ "podman-latitude-temporal.service" ];
            content = ''
              DB=postgres12
              DB_PORT=5432
              POSTGRES_SEEDS=${serviceHost}
              POSTGRES_USER=latitude
              POSTGRES_PWD=${config.sops.placeholder.latitude_postgres_password}
              DBNAME=temporal
              VISIBILITY_DBNAME=temporal_visibility
            '';
          };

          sops.secrets = lib.mkIf hasSecretFile (
            secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              latitude_postgres_password = {
                key = "database/password";
                path = "/run/secrets/latitude.postgres_password";
              };
              latitude_clickhouse_password = {
                key = "clickhouse/password";
                path = "/run/secrets/latitude.clickhouse_password";
              };
              latitude_redis_queue_password = {
                key = "redis/queue_password";
                path = "/run/secrets/latitude.redis_queue_password";
              };
              latitude_master_encryption_key = {
                key = "master_encryption_key";
                path = "/run/secrets/latitude.master_encryption_key";
              };
              latitude_better_auth_secret = {
                key = "better_auth_secret";
                path = "/run/secrets/latitude.better_auth_secret";
              };
              latitude_github_client_id = {
                key = "github/client_id";
                path = "/run/secrets/latitude.github_client_id";
              };
              latitude_github_client_secret = {
                key = "github/client_secret";
                path = "/run/secrets/latitude.github_client_secret";
              };
              latitude_github_app_id = {
                key = "github/app_id";
                path = "/run/secrets/latitude.github_app_id";
              };
              latitude_github_app_slug = {
                key = "github/app_slug";
                path = "/run/secrets/latitude.github_app_slug";
              };
              latitude_github_app_private_key = {
                key = "github/app_private_key";
                path = "/run/secrets/latitude.github_app_private_key";
              };
              latitude_github_webhook_secret = {
                key = "github/webhook_secret";
                path = "/run/secrets/latitude.github_webhook_secret";
              };
              latitude_github_app_client_id = {
                key = "github/app_client_id";
                path = "/run/secrets/latitude.github_app_client_id";
              };
              latitude_github_app_client_secret = {
                key = "github/app_client_secret";
                path = "/run/secrets/latitude.github_app_client_secret";
              };
              latitude_smtp_password = {
                key = "smtp/password";
                path = "/run/secrets/latitude.smtp_password";
              };
            }
          );

          virtualisation.podman.enable = true;

          virtualisation.oci-containers.containers = {
            # Public listeners are host sockets, so the firewall keeps them tailnet-scoped; workers serve health only.
            latitude-web = {
              autoStart = true;
              image = cfg.images.web;
              # Ignores LAT_WEB_PORT and defaults to 3000, which langfuse-web owns here; Nitro honours PORT.
              environment.PORT = toString cfg.webPort;
              extraOptions = [
                "--network=host"
                storageMount
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
            }
            // appEnv;

            latitude-api = {
              autoStart = true;
              image = cfg.images.api;
              extraOptions = [
                "--network=host"
                storageMount
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
            }
            // appEnv;

            latitude-ingest = {
              autoStart = true;
              image = cfg.images.ingest;
              extraOptions = [
                "--network=host"
                storageMount
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
            }
            // appEnv;

            latitude-workers = {
              autoStart = true;
              image = cfg.images.workers;
              extraOptions = [
                "--network=host"
                storageMount
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
            }
            // appEnv;

            latitude-workflows = {
              autoStart = true;
              image = cfg.images.workflows;
              extraOptions = [
                "--network=host"
                storageMount
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
            }
            // appEnv;

            # Auto-setup creates and migrates two databases, hence CREATEDB on the consumer role.
            latitude-temporal = {
              autoStart = true;
              image = cfg.images.temporal;
              # getent maps the hostname to 127.0.0.2 on NixOS, so bind the service address; 0.0.0.0 would expose
              # this unauthenticated gRPC frontend.
              environment.BIND_ON_IP = serviceAddress;
              extraOptions = [
                "--network=host"
                "--add-host=${serviceHost}:${serviceAddress}"
              ];
            }
            // temporalEnv;
          };

          systemd = {
            tmpfiles.rules = [
              "d ${cfg.dataDir} 0755 root root - -"
              "z ${cfg.dataDir} 0755 root root - -"
              "d ${cfg.dataDir}/storage 0750 999 999 - -"
              "z ${cfg.dataDir}/storage 0750 999 999 - -"
              "d ${cfg.dataDir}/redis-cache 0750 redis-latitude redis-latitude - -"
              "z ${cfg.dataDir}/redis-cache 0750 redis-latitude redis-latitude - -"
              "d ${cfg.dataDir}/redis-queue 0750 redis-latitude-queue redis-latitude-queue - -"
              "z ${cfg.dataDir}/redis-queue 0750 redis-latitude-queue redis-latitude-queue - -"
            ];

            services =
              lib.listToAttrs (
                map (name: {
                  name = "podman-latitude-${name}";
                  value =
                    let
                      # Exclude temporal from its own dependency lists.
                      dropSelf = lib.filter (u: u != "podman-latitude-${name}.service");
                    in
                    {
                      wants = [ "network-online.target" ];
                      after = dropSelf appUnitDeps;
                      requires = dropSelf appUnitRequires;
                      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
                    }
                    // lib.optionalAttrs (builtins.elem name appServices) {
                      serviceConfig.ExecStartPre = [ waitForDeps ];
                    };
                }) (appServices ++ [ "temporal" ])
              )
              // {
                # ClickHouse does not watch users.d; reload on substitution change.
                clickhouse.restartTriggers = lib.optional hasSecretFile clickhouseUsers;

                # ProtectSystem=strict exempts only StateDirectory, so AOF writes to the storage mount fail with EROFS.
                redis-latitude-queue.serviceConfig.ReadWritePaths = [ cfg.dataDir ];

                # Upstream migrations create neither the ClickHouse database nor the Postgres schema.
                latitude-db-init = lib.mkIf hasSecretFile {
                  description = "Create the Latitude ClickHouse database";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "clickhouse.service" ];
                  wants = [ "clickhouse.service" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    # Client from the same package set as the server. Bound the wait: After= orders on the start job, not the port.
                    for ((i=0; i<30; i++)); do
                      if ${pkgs.clickhouse}/bin/clickhouse-client --query "CREATE DATABASE IF NOT EXISTS ${cfg.clickhouseDatabase}"; then
                        exit 0
                      fi
                      sleep 2
                    done
                    echo "latitude-db-init: clickhouse not reachable after 60s" >&2
                    exit 1
                  '';
                };

                # Re-runs on image bump (the unit text carries the reference); migrations are idempotent.
                latitude-migrations = lib.mkIf hasSecretFile {
                  description = "Latitude database migrations (PostgreSQL + ClickHouse)";
                  wantedBy = [ "multi-user.target" ];
                  after = [
                    "postgresql.service"
                    "postgresql-provision.service"
                    "clickhouse.service"
                    "latitude-db-init.service"
                  ];
                  requires = [
                    "postgresql-provision.service"
                    "latitude-db-init.service"
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    RequiresMountsFor = cfg.dataDir;
                  };
                  script = ''
                    ${pkgs.podman}/bin/podman run --rm --network=host \
                      --add-host=${serviceHost}:${serviceAddress} \
                      --env-file ${config.sops.templates."latitude.environment".path} \
                      ${cfg.images.migrations}
                  '';
                };

                # Cost dashboard and agent score sit behind upstream feature flags with no self-host switch; rows are written directly.
                latitude-seed-flags = lib.mkIf hasSecretFile {
                  description = "Enable Latitude's cost dashboard, Agent Score and custom behaviors";
                  wantedBy = [ "multi-user.target" ];
                  after = [ "latitude-migrations.service" ];
                  requires = [ "latitude-migrations.service" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    export PGPASSWORD="$(cat ${config.sops.secrets.latitude_postgres_password.path})"
                    ${pkgs.postgresql}/bin/psql \
                      -h ${serviceHost} -p 5432 -U latitude -d latitude \
                      -v ON_ERROR_STOP=1 <<'SQL'
                    INSERT INTO latitude.feature_flags (identifier, enabled_for_all)
                    VALUES ('costDashboard', true), ('agentScore', true), ('customBehaviors', true)
                    ON CONFLICT (identifier) DO UPDATE SET enabled_for_all = true;
                    SQL
                  '';
                };

                # svc0 appears only after networkd applies it; retry the start.
                "redis-latitude".serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = 5;
                };
                "redis-latitude-queue".serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = 5;
                };
                clickhouse.serviceConfig = {
                  Restart = "on-failure";
                  RestartSec = 5;
                };
              };
          };

          # Stateful roles are reachable from the host and containers through the service address only.
          networking.firewall.extraCommands = lib.concatStringsSep "\n" [
            (netHelpers.mkServiceIngressRule {
              sourceCIDR = containerSourceCIDR;
              address = serviceAddress;
              ports = [
                cfg.redisPort
                cfg.redisQueuePort
              ];
            })
            (netHelpers.mkServiceIngressRule {
              sourceCIDR = containerSourceCIDR;
              address = serviceAddress;
              ports = [ cfg.temporalPort ];
            })
          ];

          # No state-backups registration: Postgres rides the substrate's export, ClickHouse is regenerable, and object payloads are not traces.
        }
      ];
    };
}
