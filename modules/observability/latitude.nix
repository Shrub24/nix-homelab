# Latitude placement aspect: the agent-failure triage console (observability and
# signal discovery), colocated with langfuse on home-forge (trialed beside it
# on oci-melb-1).
#
# Shape (D-071): every stateful role that has a native equivalent runs on the host
# — the fleet PostgreSQL substrate (with pgvector), native ClickHouse in its own
# database, and two native Redis instances (cache plus a BullMQ queue that needs
# its own append-only, no-eviction policy). Temporal has no native equivalent, so
# it is a container like the six digest-pinned application images. Object storage
# is the `fs` driver on the heavy-app mount instead of a bundled SeaweedFS.
#
# Containers share the host network namespace, so each listener is an ordinary
# host socket filtered by the firewall; nothing is published.
{
  config,
  inputs,
  ...
}:
let
  # The gateway's canonical OpenAI-compatible route, resolved from nix-fleet's
  # service inventory against this flake's fleet (the same resolution docs-mcp
  # uses). The record's base path already carries /v1. This is the fallback for a
  # host that does not run the gateway itself; the host-local choice is made in
  # the module body, where `config` is the consuming host's own.
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

      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;

      globals = import ../../policy/globals.nix;
      loopback = "127.0.0.1";
      serviceAddress = globals.serviceNetwork.address;
      serviceHost = globals.serviceNetwork.hostName;
      containerSourceCIDR = globals.serviceNetwork.containerSourceCIDR;
      # The fs object-store root (LAT_STORAGE_FS_ROOT) is this host directory,
      # bind-mounted at the same path inside every stateless application container.
      storageMount = "--volume=${cfg.dataDir}/storage:/state/storage";
      netHelpers = import ../../lib/networking.nix { inherit lib; };

      # The gateway dial. Placement in the web policy names the provider host
      # (oci-melb-1), so nothing else makes a co-located consumer dial the socket
      # on its own machine; a host that runs the aspect publishes its listener as
      # `localEndpoint`, and these containers share the host network namespace,
      # so loopback is reachable from them. The local record is a bare origin —
      # the version prefix is ours to append.
      hasLocalBifrost = lib.hasAttrByPath [ "services" "bifrost" "localEndpoint" ] options;
      bifrostBaseUrl =
        if hasLocalBifrost then "${config.services.bifrost.localEndpoint.url}/v1" else bifrostCanonicalUrl;

      # The web app is a Vite SPA and the browser calls the API on its own origin
      # (upstream ships separate LAT_WEB_URL/LAT_API_URL values plus a CORS
      # allowlist, so nothing proxies the API). Ingest has no public route: it is
      # a machine endpoint on the tailnet, which is why it is read from the
      # catalog's tailscale-only endpoint rather than a public URL.
      catalog = config.repo.web.catalog;
      webUrl = catalog.latitude.publicUrl or null;
      apiUrl = catalog."latitude-api".publicUrl or null;
      # Ingest has no route: it is a machine endpoint exporters dial over the
      # tailnet. On the co-located host the catalog's `endpoint` resolves to
      # loopback, which is useless in the address the UI shows operators, so the
      # tailnet name is composed around the port that one declaration owns.
      ingestPort = catalog."latitude-ingest".endpoint.port or cfg.ingestPort;
      ingestUrl = "http://${config.networking.hostName}.${globals.tailnet.suffix}:${toString ingestPort}";

      # ClickHouse: HTTP for queries, native 9000 for the goose migrations. Both
      # are reached through the stable service name, which every container gets
      # as an /etc/hosts entry. The HTTP port is fleet policy because Home
      # Assistant owns 8123 on this host (D-102).
      clickhouseUrl = "http://${serviceHost}:${toString globals.observability.clickhouseHttpPort}";

      # The users fragment is its own file (each consumer owns one), and
      # latitude deliberately needs no substitution file: its user is
      # passwordless over the scoped networks (the openlit posture).
      # Footgun: a second separately-loaded substitution file shadows the
      # first file's variables in ClickHouse >= 26.8, so langfuse's auth
      # parsed empty whenever latitude rendered its own file.
      # It doubles as the unit's restart trigger because ClickHouse
      # does not watch users.d.
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

      # The application roles that talk to a database and a queue. Temporal is
      # excluded: it fronts its own Postgres databases and needs no application
      # environment.
      appServices = [
        "web"
        "api"
        "ingest"
        "workers"
        "workflows"
      ];

      # Every application role reads the same environment: they share one database,
      # one ClickHouse database, one queue and one object-store root, and upstream
      # ships a single variable set for the whole stack. Absent during the two-step
      # bootstrap window, when the path is bound but nothing is encrypted yet.
      appEnv = lib.optionalAttrs hasSecretFile {
        environmentFiles = [ config.sops.templates."latitude.environment".path ];
      };

      # Temporal's auto-setup reads the standard POSTGRES_* names, not the LAT_*
      # ones, so it gets its own small rendered file.
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

      # Every application role aborts on the first refused connection, and its
      # dependencies start in the same activation: switch-to-configuration
      # enqueues its own restart jobs, which no `after` edge can order against.
      # Wait for the endpoints a role dials instead of spending the restart
      # budget on a dependency that is seconds behind. PostgreSQL and ClickHouse
      # ports are the ones the environment file already names.
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
        enable = lib.mkEnableOption "Latitude agent observability";

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
            default = "";
            description = "From address on magic-link mail; set per host.";
          };
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "latitude-host-secrets";
      };

      config = lib.mkMerge [
        # Selection is enablement.
        { services.latitude.enable = true; }

        (lib.mkIf cfg.enable {
          assertions = [
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
              file = cfg.secretFiles.host;
              feature = "services.latitude";
              label = "secretFiles.host";
            })
            {
              assertion = webUrl != null;
              message = "services.latitude: the web catalog entry 'latitude' is missing from policy/web-services.nix; magic-link sign-in mints its redirect from that public URL.";
            }
            {
              assertion = apiUrl != null;
              message = "services.latitude: the web catalog entry 'latitude-api' is missing from policy/web-services.nix; the browser calls the API on that origin.";
            }
            {
              assertion = hasSecretFile -> cfg.smtp.from != "";
              message = "services.latitude.smtp.from must be set: sign-in is a magic link and no mail is sent without a sender.";
            }
            {
              # nixpkgs gives each redis instance a per-instance system user
              # (redis-<instance>), and an undeclared tmpfiles owner fails at
              # activation with 'Unknown user' — the dirs are silently never
              # created and redis exits on a missing `dir`.
              assertion = lib.all (u: config.users.users ? ${u}) [
                "root"
                "redis-latitude"
                "redis-latitude-queue"
              ];
              message = "latitude: a tmpfiles rule owner is not a declared user; use the per-instance nixpkgs user (redis-<instance>), not bare 'redis'.";
            }
          ];

          # Self-registration (D-058): the database, role, extension and credential
          # Latitude needs live next to Latitude. One consumer is one database and
          # one role, and upstream's two URLs (RLS-bound runtime plus schema-owning
          # admin) collapse onto that single role: BYPASSRLS makes it satisfy the
          # admin URL. CREATEDB lets Temporal's auto-setup create the `temporal` and
          # `temporal_visibility` databases it owns. Upstream's bundled compose runs
          # `wal_level=logical`, but its bring-your-own-infrastructure checklist
          # requires only the vector extension and a schema-create admin; this
          # cluster stays on `replica`, which is flagged to the operator.
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
            # pg_hba is database-scoped: without these the role's rows never
            # match a `temporal`/`temporal_visibility` connection and the
            # catch-all reject kills auto-setup (and every unit that requires
            # it). `postgres` is where auto-setup connects to create them.
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

          # Each consumer owns its own fragment file; langfuse's stays untouched.
          environment.etc."clickhouse-server/users.d/300-latitude.xml" = lib.mkIf hasSecretFile {
            text = clickhouseUsers;
          };

          # Cache: locks, rate limiters and budgets. Ephemeral by design (no RDB,
          # no AOF) — upstream ships no password variable for this role, and the
          # listener is scoped to loopback plus the container-facing service address.
          services.redis.servers.latitude = {
            enable = true;
            bind = "${loopback} ${serviceAddress}";
            port = cfg.redisPort;
            save = [ ];
            appendOnly = false;
            # With no password, Redis protected mode rejects every non-loopback
            # SOURCE before the first command — the host-networked containers
            # dial from the service address itself, so the handshake dies with
            # EPIPE. The bind above is the scoping; disable it explicitly.
            settings.protected-mode = "no";
            # nixpkgs' redis module derives the default dir from the instance
            # name; ours is a fleet policy (state under the storage mount).
            settings.dir = lib.mkForce "${cfg.dataDir}/redis-cache";
          };

          # Queue: BullMQ requires append-only persistence and no eviction, so it
          # cannot share the cache instance's policy.
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
            # The containers read this file at start and their unit text does not
            # carry it, so a content change has to restart them.
            restartUnits = map (name: "podman-latitude-${name}.service") appServices;
            content = ''
              # --- public origins: the browser loads the web origin and calls the
              # API origin directly. The edge gates the web route; the API route
              # carries no interactive gate, and Latitude's own auth authorizes it.
              LAT_WEB_URL=${webUrl}
              LAT_WEB_PORT=${toString cfg.webPort}
              LAT_API_URL=${apiUrl}
              LAT_API_PORT=${toString cfg.apiPort}
              LAT_INGEST_URL=${ingestUrl}
              LAT_INGEST_PORT=${toString cfg.ingestPort}
              LAT_TRUSTED_ORIGINS=${webUrl}
              LAT_CORS_ALLOWED_ORIGINS=${webUrl}

              # --- authoritative metadata (PostgreSQL substrate) ---
              # One lineage for both URLs: the role carries BYPASSRLS, so the
              # runtime URL behaves like the admin URL (see the consumer's setupSQL).
              LAT_DATABASE_URL=postgres://latitude:${config.sops.placeholder.latitude_postgres_password}@${serviceHost}:5432/latitude
              LAT_ADMIN_DATABASE_URL=postgres://latitude:${config.sops.placeholder.latitude_postgres_password}@${serviceHost}:5432/latitude

              # --- ClickHouse (spans and traces) ---
              LAT_CLICKHOUSE_URL=${clickhouseUrl}
              LAT_CLICKHOUSE_USER=${cfg.clickhouseUser}
              LAT_CLICKHOUSE_PASSWORD=${config.sops.placeholder.latitude_clickhouse_password}
              LAT_CLICKHOUSE_DB=${cfg.clickhouseDatabase}
              # The migrations script strips the scheme and rebuilds
              # user:password@host:port/db itself — credentials or a db path
              # here get appended again (observed: goose asked for the
              # database `latitude/latitude`).
              LAT_CLICKHOUSE_MIGRATION_URL=clickhouse://${serviceHost}:9000
              LAT_CLICKHOUSE_CLUSTER_ENABLED=false

              # --- Redis: cache plus the durable BullMQ queue ---
              LAT_REDIS_HOST=${serviceHost}
              LAT_REDIS_PORT=${toString cfg.redisPort}
              LAT_BULLMQ_HOST=${serviceHost}
              LAT_BULLMQ_PORT=${toString cfg.redisQueuePort}
              LAT_BULLMQ_PASSWORD=${config.sops.placeholder.latitude_redis_queue_password}

              # --- Temporal ---
              LAT_TEMPORAL_ADDRESS=${serviceHost}:${toString cfg.temporalPort}
              LAT_TEMPORAL_NAMESPACE=default
              LAT_TEMPORAL_TASK_QUEUE=latitude-workflows

              # --- object storage: the fs driver on the heavy-app mount, shared by
              # every stateless service through the same bind mount ---
              LAT_STORAGE_DRIVER=fs
              LAT_STORAGE_FS_ROOT=/state/storage

              # --- application secrets ---
              LAT_MASTER_ENCRYPTION_KEY=${config.sops.placeholder.latitude_master_encryption_key}
              LAT_BETTER_AUTH_SECRET=${config.sops.placeholder.latitude_better_auth_secret}

              # --- GitHub OAuth sign-in (Better Auth social provider). Upstream
              # enables it only when BOTH values are non-empty, and derives the
              # callback from LAT_WEB_URL: the OAuth app's registered callback
              # must be ${webUrl}/api/auth/callback/github, exact match.
              LAT_GITHUB_CLIENT_ID=${config.sops.placeholder.latitude_github_client_id}
              LAT_GITHUB_CLIENT_SECRET=${config.sops.placeholder.latitude_github_client_secret}

              # --- GitHub App integration (repo connect + signal auto-resolve).
              # A different app from the sign-in OAuth one above: upstream's
              # loader is all-or-nothing across these six, so a partial set — or
              # empty values — leaves the integration hidden rather than half-on.
              # Register the App with the setup/callback URL on the web host and
              # the webhook on the API host, subscribe to Pull request + Push,
              # and put the base64 of the .pem in the private key (upstream
              # decodes it and rejects a raw PEM).
              LAT_GITHUB_APP_ID=${config.sops.placeholder.latitude_github_app_id}
              LAT_GITHUB_APP_SLUG=${config.sops.placeholder.latitude_github_app_slug}
              LAT_GITHUB_APP_PRIVATE_KEY=${config.sops.placeholder.latitude_github_app_private_key}
              LAT_GITHUB_WEBHOOK_SECRET=${config.sops.placeholder.latitude_github_webhook_secret}
              LAT_GITHUB_APP_CLIENT_ID=${config.sops.placeholder.latitude_github_app_client_id}
              LAT_GITHUB_APP_CLIENT_SECRET=${config.sops.placeholder.latitude_github_app_client_secret}

              # --- email: sign-in is a magic link, so this transport is required ---
              LAT_SMTP_HOST=${cfg.smtp.host}
              LAT_SMTP_PORT=${toString cfg.smtp.port}
              LAT_SMTP_USER=${cfg.smtp.username}
              LAT_SMTP_PASS=${config.sops.placeholder.latitude_smtp_password}
              LAT_SMTP_FROM=${cfg.smtp.from}

              # --- AI: generation and embeddings go through the fleet gateway, which
              # owns the provider keys. Latitude's custom provider sends `dimensions`
              # on embedding calls; the gateway's Voyage normalizer maps it to
              # output_dimension, so voyage-4 returns the 2048-dim vectors the schema
              # requires. The embedding model is a one-time choice: switching later
              # breaks semantic search because existing rows are never re-embedded.
              # Reranking is left unset: its providers are voyage and amazon-bedrock
              # only, so discovery falls back to embedding order. The gateway takes
              # no client credential; this is the placeholder its other consumers pass. ---
              LAT_CUSTOM_AI_BASE_URL=${bifrostBaseUrl}
              LAT_CUSTOM_AI_API_KEY=bifrost-local
              LAT_AI_GENERATION_PROVIDER=custom
              LAT_AI_GENERATION_MODEL=${globals.bifrost.aliases.text}
              LAT_AI_EMBEDDING_PROVIDER=custom
              LAT_AI_EMBEDDING_MODEL=${globals.bifrost.aliases.embedding}

              # --- health listeners: host sockets beside the three public ones,
              # pinned because upstream's worker default (9090) is cockpit's
              # socket on this host and a collision is a silent exit(0) ---
              LAT_WORKERS_HEALTH_PORT=${toString cfg.workersHealthPort}
              LAT_WORKFLOWS_HEALTH_PORT=${toString cfg.workflowsHealthPort}

              LAT_BILLING_ENABLED=false
            '';
          };

          sops.templates."latitude-temporal.environment" = lib.mkIf hasSecretFile {
            owner = "root";
            group = "root";
            mode = "0400";
            # The container reads this file at start and the unit text does not
            # carry it, so a content change has to restart it.
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
              # GitHub App integration: upstream enables it only when all six are
              # non-empty, so empty values in the encrypted file keep it hidden.
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
            # Web (UI), api (browser and MCP clients) and ingest (OTLP/HTTP from
            # exporters) are the roles with public listeners; workers and
            # workflows serve health endpoints only, pinned beside them because
            # upstream's defaults collide (9090 is cockpit's socket). Every
            # listener is a host socket, so the firewall keeps them
            # tailnet-scoped.
            latitude-web = {
              autoStart = true;
              image = cfg.images.web;
              # The app ignores LAT_WEB_PORT and defaults to 3000 — which
              # langfuse-web owns on this host — so under host networking it
              # exits silently on the port collision. Nitro honours PORT.
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

            # Temporal: Postgres-backed workflow engine. Auto-setup creates and
            # migrates the two databases it owns, which is why the consumer role
            # carries CREATEDB.
            latitude-temporal = {
              autoStart = true;
              image = cfg.images.temporal;
              # Auto-setup derives its bind address from `getent hosts $(hostname)`
              # and NixOS maps the static hostname to 127.0.0.2 — an address no
              # client dials, so the engine came up unreachable. Keep it in the
              # unit text (not the environment file, whose changes do not restart
              # a running container). Deliberately the service address, not
              # 0.0.0.0: this gRPC frontend authenticates nobody.
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
                      # A unit must not require itself: the shared dep lists
                      # name the temporal unit, and temporal is in the map too.
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
                # The clickhouse unit reloads its users fragment when the substitution
                # changes; ClickHouse does not watch users.d on its own.
                clickhouse.restartTriggers = lib.optional hasSecretFile clickhouseUsers;

                # Footgun: nixpkgs' redis unit runs ProtectSystem=strict and only
                # StateDirectory (/var/lib/redis-<instance>) is exempt, so an AOF
                # write to the storage-mount dir fails with EROFS. The cache
                # instance writes nothing (save=[], no AOF) and needs no exemption.
                redis-latitude-queue.serviceConfig.ReadWritePaths = [ cfg.dataDir ];

                # Upstream's migrations create neither the ClickHouse database nor
                # the Postgres schema, so the database is created first.
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
                    # The client comes from the same host package set as the
                    # server (D-093).
                    # Bound the wait: After=clickhouse.service orders against
                    # the start job completing, not the port accepting — a
                    # graceful CH start is still loading config when this runs.
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

                # Migrations apply PostgreSQL and ClickHouse schema changes before the
                # application roles start. The unit text carries the image reference,
                # so an image bump re-runs it (the migrations are idempotent).
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

                # The cost dashboard, Agent Score and custom behaviors are feature
                # flagged upstream: a `feature_flags` row with `enabled_for_all` is
                # what turns them on, and there is no supported self-host switch for
                # that, so the rows are written directly (idempotent).
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

                # svc0 exists only once systemd-networkd has applied it — an ordering
                # no unit dependency can express — so a start that races the address
                # retries.
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

          # Native stateful roles reachable from the host itself and from containers
          # through the service address; scoped to the Podman pool, not to a bridge.
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

          # No state-backups registration: the durable roles are covered elsewhere —
          # PostgreSQL rides the substrate's export-first dump contract, ClickHouse
          # traces are regenerable under retention, and the object store holds
          # payloads whose loss does not lose a trace.
        })
      ];
    };
}
