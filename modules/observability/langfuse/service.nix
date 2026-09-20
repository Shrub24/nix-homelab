# Sibling contributor to the `langfuse` aspect: the fleet contract and body for
# the LLM observability stack, published as the same `flake.modules.nixos.langfuse`
# name that ../langfuse.nix declares. Discovery reaches it; the aspect owner
# imports nothing from here.
#
# Shape (D-060, from the deployment-modality research): every stateful role runs
# declaratively on the host — native ClickHouse for traces/observations/scores,
# native Redis for the ingestion queue, the fleet PostgreSQL substrate for
# authoritative metadata, R2 for the three blob roles — and only the two
# stateless application roles are digest-pinned containers. ClickHouse trace
# data is regenerable under a retention TTL and is deliberately absent from the
# backup surface; the `langfuse` PostgreSQL database rides the substrate's
# export-first dump contract.
{
  flake.modules.nixos.langfuse =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.services.langfuse;
      secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;

      # The cluster this host runs, when it runs one; probed through `options`
      # because reading an undeclared option path raises NixOS' "did you mean"
      # error rather than returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;

      # Dedicated bridge (container-networking class A′): the worker must reach
      # ClickHouse, Redis, and PostgreSQL, which all widen their accept surface to
      # the bridge gateway. The subnet is reserved outside netavark's auto pool so
      # a future user-defined network cannot collide with it.
      bridgeGateway = "10.89.30.1";

      # Langfuse reaches ClickHouse over HTTP (8123) for queries and the native
      # protocol (9000) for migrations.
      clickhouseUrl = "http://${bridgeGateway}:8123";
      clickhouseMigrationUrl = "clickhouse://${bridgeGateway}:9000";
    in
    {
      imports = [ ../../database/postgres/_consumer.nix ];

      options.services.langfuse = {
        enable = lib.mkEnableOption "Langfuse LLM observability";

        image = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.langfuse;
          description = "Langfuse web container image reference (tag + digest).";
        };

        workerImage = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.langfuseWorker;
          description = "Langfuse worker container image reference (tag + digest).";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data/langfuse";
          description = "Host directory holding runtime state (clickhouse and redis live in their own state directories).";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 3000;
          description = "Host port the web container serves the UI and the OTLP ingestion endpoint on.";
        };

        networkName = lib.mkOption {
          type = lib.types.str;
          default = "langfuse0";
          description = "User-defined podman network the worker joins.";
        };

        networkSubnet = lib.mkOption {
          type = lib.types.str;
          default = "10.89.30.0/24";
          description = "Reserved bridge subnet for the langfuse network (outside netavark's auto pool).";
        };

        buckets = {
          events = lib.mkOption {
            type = lib.types.str;
            default = "langfuse-events";
            description = "R2 bucket for ingested event blobs.";
          };
          media = lib.mkOption {
            type = lib.types.str;
            default = "langfuse-media";
            description = "R2 bucket for media uploads.";
          };
          exports = lib.mkOption {
            type = lib.types.str;
            default = "langfuse-exports";
            description = "R2 bucket for batch exports.";
          };
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "langfuse-host-secrets";

        s3 = {
          endpoint = lib.mkOption {
            type = lib.types.str;
            default = "https://bef816e6776e8f13f5c03d2af70b036e.r2.cloudflarestorage.com";
            description = "S3-compatible endpoint for the blob roles (fleet R2 by default).";
          };

          region = lib.mkOption {
            type = lib.types.str;
            default = "auto";
            description = "S3 region string (R2 uses a fixed `auto`).";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            inherit (cfg) enable;
            file = cfg.secretFiles.host;
            feature = "services.langfuse";
            label = "secretFiles.host";
          })
          {
            assertion = !cfg.enable || localPostgres != null;
            message = "services.langfuse.enable is true but this host runs no PostgreSQL cluster (select the postgres aspect and declare services.postgres.instances.<name>).";
          }
        ];

        # Self-registration (D-058): the database, role, and credential this service
        # needs, declared next to the service that uses them. The provider reads the
        # same file and key to provision the role, so the password has one
        # authoritative source. The worker reaches the database over the bridge, so
        # the role accepts the bridge range; the web container reaches it on the
        # host network namespace, so loopback stays accepted too. No extensions:
        # upstream's compose installs none and Prisma manages the schema. Gated
        # on the secret file existing (the two-step sops bootstrap binds the
        # path before the operator encrypts anything), matching hindsight.
        services.postgres.consumers.langfuse = lib.mkIf (localPostgres != null && hasSecretFile) {
          database = "langfuse";
          role = "langfuse";
          auth = "scram";
          password = {
            file = cfg.secretFiles.host;
            key = "database/password";
          };
          allowedCIDRs = [
            "127.0.0.1/32"
            "::1/128"
            cfg.networkSubnet
          ];
        };

        # ClickHouse: declarative server and user configuration. The application
        # user's password reaches the server without entering the Nix store: the
        # server loads substitutions from a sops-rendered runtime file (include_from),
        # and the user fragment references the substitution by name (incl). ClickHouse
        # stores password_sha256_hex, so the substitution file carries the SHA-256
        # digest of the same plaintext the containers authenticate with.
        services.clickhouse = {
          enable = true;
          serverConfig = {
            listen_host = [
              "127.0.0.1"
              bridgeGateway
            ];
            http_port = 8123;
            tcp_port = 9000;
          }
          // (lib.optionalAttrs hasSecretFile {
            include_from = config.sops.templates."langfuse-clickhouse-substitutions".path;
          });
          usersConfig = { };
          extraUsersConfig =
            if hasSecretFile then
              ''
                <clickhouse>
                  <users>
                    <langfuse>
                      <profile>default</profile>
                      <quota>default</quota>
                      <networks><ip>127.0.0.1</ip><ip>${cfg.networkSubnet}</ip></networks>
                      <password_sha256_hex incl="langfuse_ch_password" optional="false"/>
                    </langfuse>
                  </users>
                </clickhouse>
              ''
            else
              "";
        };

        # Redis: queue + cache only, no durable state by design, so persistence
        # stays off and the server binds loopback plus the bridge gateway.
        services.redis.servers.langfuse = {
          enable = true;
          bind = null; # bind 0.0.0.0; access is gated by requirePass and firewall
          port = 6379;
          # The secret file is absent during the two-step bootstrap window; the
          # fail-closed assertion blocks any deploy in that state, so the
          # passwordless fallback only ever exists in evaluation.
          requirePassFile = if hasSecretFile then config.sops.secrets.langfuse_redis_password.path else null;
          save = [ ]; # no RDB snapshots: the queue is ephemeral
          appendOnly = false;
        };

        sops.templates."langfuse.environment" = lib.mkIf hasSecretFile {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            # --- authoritative metadata (PostgreSQL substrate) ---
            # The bridge gateway routes to the host from both containers: the web
            # container sits on the host network namespace (gateway routes like any
            # other address) and the worker sits on the bridge itself, so one
            # connection string serves both.
            DATABASE_URL=postgresql://langfuse:${config.sops.placeholder.langfuse_postgres_password}@${bridgeGateway}:${toString localPostgres.port}/langfuse

            # --- ClickHouse (traces/observations/scores) ---
            CLICKHOUSE_URL=${clickhouseUrl}
            CLICKHOUSE_MIGRATION_URL=${clickhouseMigrationUrl}
            CLICKHOUSE_USER=langfuse
            CLICKHOUSE_PASSWORD=${config.sops.placeholder.langfuse_clickhouse_password}
            CLICKHOUSE_CLUSTER_ENABLED=false

            # --- Redis (ingestion queue; the worker joins the bridge) ---
            REDIS_HOST=${bridgeGateway}
            REDIS_PORT=6379
            REDIS_AUTH=${config.sops.placeholder.langfuse_redis_password}

            # --- blob storage (fleet R2, three roles) ---
            LANGFUSE_S3_EVENT_UPLOAD_BUCKET=${cfg.buckets.events}
            LANGFUSE_S3_EVENT_UPLOAD_REGION=${cfg.s3.region}
            LANGFUSE_S3_EVENT_UPLOAD_ENDPOINT=${cfg.s3.endpoint}
            LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID=${config.sops.placeholder.langfuse_s3_access_key_id}
            LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY=${config.sops.placeholder.langfuse_s3_secret_access_key}
            LANGFUSE_S3_EVENT_UPLOAD_FORCE_PATH_STYLE=true
            LANGFUSE_S3_EVENT_UPLOAD_PREFIX=events/
            LANGFUSE_S3_MEDIA_UPLOAD_BUCKET=${cfg.buckets.media}
            LANGFUSE_S3_MEDIA_UPLOAD_REGION=${cfg.s3.region}
            LANGFUSE_S3_MEDIA_UPLOAD_ENDPOINT=${cfg.s3.endpoint}
            LANGFUSE_S3_MEDIA_UPLOAD_ACCESS_KEY_ID=${config.sops.placeholder.langfuse_s3_access_key_id}
            LANGFUSE_S3_MEDIA_UPLOAD_SECRET_ACCESS_KEY=${config.sops.placeholder.langfuse_s3_secret_access_key}
            LANGFUSE_S3_MEDIA_UPLOAD_FORCE_PATH_STYLE=true
            LANGFUSE_S3_MEDIA_UPLOAD_PREFIX=media/
            LANGFUSE_S3_BATCH_EXPORT_ENABLED=false
            LANGFUSE_S3_BATCH_EXPORT_BUCKET=${cfg.buckets.exports}
            LANGFUSE_S3_BATCH_EXPORT_REGION=${cfg.s3.region}
            LANGFUSE_S3_BATCH_EXPORT_ENDPOINT=${cfg.s3.endpoint}
            LANGFUSE_S3_BATCH_EXPORT_ACCESS_KEY_ID=${config.sops.placeholder.langfuse_s3_access_key_id}
            LANGFUSE_S3_BATCH_EXPORT_SECRET_ACCESS_KEY=${config.sops.placeholder.langfuse_s3_secret_access_key}
            LANGFUSE_S3_BATCH_EXPORT_FORCE_PATH_STYLE=true
            LANGFUSE_S3_BATCH_EXPORT_PREFIX=exports/

            # --- application secrets ---
            ENCRYPTION_KEY=${config.sops.placeholder.langfuse_encryption_key}
            SALT=${config.sops.placeholder.langfuse_salt}
            NEXTAUTH_SECRET=${config.sops.placeholder.langfuse_nextauth_secret}
            NEXTAUTH_URL=http://127.0.0.1:${toString cfg.port}
            TELEMETRY_ENABLED=false

            # --- first-run bootstrap (operator rotates after first login) ---
            LANGFUSE_INIT_USER_EMAIL=${config.sops.placeholder.langfuse_initial_admin_email}
            LANGFUSE_INIT_USER_PASSWORD=${config.sops.placeholder.langfuse_initial_admin_password}
          '';
        };

        sops.secrets = lib.mkIf hasSecretFile (
          secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
            langfuse_postgres_password = {
              key = "database/password";
              path = "/run/secrets/langfuse.postgres_password";
            };
            langfuse_clickhouse_password = {
              key = "clickhouse/password";
              path = "/run/secrets/langfuse.clickhouse_password";
            };
            # The SHA-256 form of the same password, for the ClickHouse user
            # fragment. One password, two representations: the containers send the
            # plaintext, the server stores the digest.
            langfuse_clickhouse_password_sha256 = {
              key = "clickhouse/password_sha256";
              path = "/run/secrets/langfuse.clickhouse_password_sha256";
            };
            langfuse_redis_password = {
              key = "redis/password";
              path = "/run/secrets/langfuse.redis_password";
            };
            langfuse_s3_access_key_id = {
              key = "s3/access_key_id";
              path = "/run/secrets/langfuse.s3_access_key_id";
            };
            langfuse_s3_secret_access_key = {
              key = "s3/secret_access_key";
              path = "/run/secrets/langfuse.s3_secret_access_key";
            };
            langfuse_encryption_key = {
              key = "encryption_key";
              path = "/run/secrets/langfuse.encryption_key";
            };
            langfuse_salt = {
              key = "salt";
              path = "/run/secrets/langfuse.salt";
            };
            langfuse_nextauth_secret = {
              key = "nextauth_secret";
              path = "/run/secrets/langfuse.nextauth_secret";
            };
            langfuse_initial_admin_email = {
              key = "initial_admin/email";
              path = "/run/secrets/langfuse.initial_admin_email";
            };
            langfuse_initial_admin_password = {
              key = "initial_admin/password";
              path = "/run/secrets/langfuse.initial_admin_password";
            };
          }
        );

        # The ClickHouse password substitution: a sops-rendered XML substitutions
        # file carrying the SHA-256 digest of the clickhouse password plaintext.
        # The operator stores both forms in the secret file (the template comment
        # in the secrets template shows the one-liner deriving one from the other);
        # ClickHouse reads it via include_from and the user fragment references it
        # by name.
        sops.templates."langfuse-clickhouse-substitutions" = lib.mkIf hasSecretFile {
          owner = "clickhouse";
          group = "clickhouse";
          mode = "0400";
          content = ''
            <clickhouse>
              <langfuse_ch_password>${config.sops.placeholder.langfuse_clickhouse_password_sha256}</langfuse_ch_password>
            </clickhouse>
          '';
        };

        virtualisation.podman.enable = true;

        systemd.services."podman-network-${cfg.networkName}" = {
          description = "Create Podman network ${cfg.networkName}";
          wantedBy = [ "multi-user.target" ];
          before = [ "podman-langfuse-worker.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${cfg.networkName} || ${pkgs.podman}/bin/podman network create --interface-name=langfuse0 --subnet=${cfg.networkSubnet} ${cfg.networkName}'";
            ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${cfg.networkName} || true'";
          };
        };

        # langfuse-web: the only role with a listener. It runs on the host network
        # namespace so its web port is an ordinary host socket filtered by the
        # firewall (tailnet-only via the foundation aspect's tailscale0 trust); a
        # published port would bypass the firewall on every interface.
        virtualisation.oci-containers.containers.langfuse-web = {
          autoStart = true;
          image = cfg.image;
          environment = {
            PORT = toString cfg.port;
            HOSTNAME = "0.0.0.0";
          };
          environmentFiles = lib.optionals hasSecretFile [
            config.sops.templates."langfuse.environment".path
          ];
          extraOptions = [ "--network=host" ];
          # No `ports`: host networking shares the host's own listener.
        };

        # langfuse-worker: drains the Redis queue into ClickHouse. No inbound
        # ports; it reaches ClickHouse, Redis, and PostgreSQL over the bridge
        # gateway.
        virtualisation.oci-containers.containers.langfuse-worker = {
          autoStart = true;
          image = cfg.workerImage;
          environmentFiles = lib.optionals hasSecretFile [
            config.sops.templates."langfuse.environment".path
          ];
          extraOptions = [
            "--network=${cfg.networkName}"
          ];
          dependsOn = [ "langfuse-web" ];
        };

        systemd = {
          tmpfiles.rules = [
            "d ${cfg.dataDir} 0755 root root - -"
            "z ${cfg.dataDir} 0755 root root - -"
          ];

          services = {
            "podman-langfuse-web" = {
              description = "Langfuse web (UI, ingestion API, OTLP endpoint)";
              wants = [ "network-online.target" ];
              after = [
                "network-online.target"
                "clickhouse.service"
                "redis-langfuse.service"
                "postgresql.service"
                "postgresql-provision.service"
              ];
              requires = [ "postgresql-provision.service" ];
              unitConfig.RequiresMountsFor = [ cfg.dataDir ];
            };

            "podman-langfuse-worker" = {
              description = "Langfuse worker (ingestion queue drain into ClickHouse)";
              wants = [ "network-online.target" ];
              after = [
                "network-online.target"
                "podman-network-${cfg.networkName}.service"
                "clickhouse.service"
                "redis-langfuse.service"
                "postgresql.service"
                "postgresql-provision.service"
              ];
              requires = [ "podman-network-${cfg.networkName}.service" ];
            };
          };
        };

        # No state-backups registration: the aspect owns no local durable state.
        # ClickHouse traces are regenerable under retention (design D9), Redis holds
        # no durable state, the containers are stateless, and the PostgreSQL
        # `langfuse` database rides the substrate's export-first dump contract.
      };
    };
}
