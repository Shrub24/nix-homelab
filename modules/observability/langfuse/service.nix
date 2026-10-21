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
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.langfuse;
      secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;

      oidcClient = config.services.identity.oidc.clients.langfuse or null;

      # NextAuth builds redirects from this, so it must be the public route.
      publicUrl = config.repo.web.catalog.langfuse.publicUrl or null;

      # Hoisted: a nested ''-string here would defeat the template's indent stripping.
      oidcEnv = lib.optionalString cfg.oidc.enable ''
        AUTH_CUSTOM_CLIENT_ID=${cfg.oidc.clientId}
        AUTH_CUSTOM_CLIENT_SECRET=${config.sops.placeholder.langfuse_oidc_client_secret}
        AUTH_CUSTOM_ISSUER=${cfg.oidc.issuerUrl}
        AUTH_CUSTOM_NAME=${cfg.oidc.providerName}
        AUTH_CUSTOM_SCOPE=${cfg.oidc.scope}
        AUTH_CUSTOM_ID_TOKEN_SIGNED_RESPONSE_ALG=${cfg.oidc.idTokenSignedResponseAlg}
      '';

      # The cluster this host runs, when it runs one; probed through `options`
      # because reading an undeclared option path raises NixOS' "did you mean"
      # error rather than returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;

      # Stateful roles bind loopback + the service address. The worker keeps its own
      # bridge and dials the service name; web shares the host netns (it listens).
      loopback = "127.0.0.1";
      globals = import ../../../policy/globals.nix;
      serviceNetwork = globals.serviceNetwork;
      clickhouseHttpPort = globals.observability.clickhouseHttpPort;
      serviceAddress = serviceNetwork.address;
      serviceHost = serviceNetwork.hostName;
      containerSourceCIDR = serviceNetwork.containerSourceCIDR;
      netHelpers = import ../../../lib/networking.nix { inherit lib; };

      # Langfuse reaches ClickHouse over HTTP for queries and the native
      # protocol (9000) for migrations. The HTTP port is fleet policy, not a
      # literal: Home Assistant owns 8123 on the host that runs both (D-102).
      clickhouseUrl = "http://${serviceHost}:${toString clickhouseHttpPort}";
      clickhouseMigrationUrl = "clickhouse://${serviceHost}:9000";

      # Footgun (ClickHouse >= 26.8): include_from is read per separately-loaded
      # configuration file, so the users fragment needs its own. The fragment also
      # doubles as the unit's restart trigger (ClickHouse does not watch users.d).
      clickhouseUsers = lib.optionalString hasSecretFile ''
        <clickhouse>
          <include_from>${config.sops.templates."langfuse-clickhouse-substitutions".path}</include_from>
          <users>
            <langfuse>
              <profile>default</profile>
              <quota>default</quota>
              <networks><ip>127.0.0.1</ip><ip>::1</ip><ip>${serviceAddress}</ip><ip>${containerSourceCIDR}</ip></networks>
              <password_sha256_hex incl="langfuse_ch_password" optional="false"/>
            </langfuse>
          </users>
        </clickhouse>
      '';
    in
    {
      imports = [
        ../../database/postgres/_consumer.nix
        ../../identity/_oidc.nix
      ];

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
          default = config.repo.web.catalog.langfuse.endpoint.port;
          description = "Host port the web container serves the UI and the OTLP ingestion endpoint on; the web-policy langfuse origin declares it once.";
        };

        networkName = lib.mkOption {
          type = lib.types.str;
          default = "langfuse0";
          description = "Podman network the worker joins (the web role shares the host network namespace).";
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

        secretFiles.oidc = secretHelpers.mkSecretFileOption "langfuse-oidc-secrets";

        oidc = {
          enable = lib.mkEnableOption "OIDC login for Langfuse";

          clientId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = if oidcClient == null then null else oidcClient.clientId;
            defaultText = lib.literalExpression "services.identity.oidc.clients.langfuse.clientId";
            description = "Canonical OIDC client ID, defaulted from the canonical client record.";
          };

          issuerUrl = lib.mkOption {
            type = lib.types.str;
            default = if oidcClient == null then "" else oidcClient.issuerUrl;
            defaultText = lib.literalExpression "services.identity.oidc.clients.langfuse.issuerUrl";
            description = "OIDC issuer URL (AUTH_CUSTOM_ISSUER), defaulted from the canonical client record.";
          };

          providerName = lib.mkOption {
            type = lib.types.str;
            default = "Kanidm";
            description = "Display name for the OIDC provider button (AUTH_CUSTOM_NAME).";
          };

          scope = lib.mkOption {
            type = lib.types.str;
            default = "openid email profile";
            description = "OIDC scope string (AUTH_CUSTOM_SCOPE).";
          };

          idTokenSignedResponseAlg = lib.mkOption {
            type = lib.types.str;
            default = "ES256";
            description = ''
              Expected id_token signature algorithm
              (AUTH_CUSTOM_ID_TOKEN_SIGNED_RESPONSE_ALG). Kanidm signs ES256, while
              openid-client defaults the client to RS256 and rejects the token at
              its algorithm check -- before any JWKS fetch -- so leaving this unset
              fails every callback as OAUTH_CALLBACK_ERROR.
            '';
          };
        };

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
          {
            assertion = !cfg.oidc.enable || oidcClient != null;
            message = "services.langfuse.oidc: canonical OIDC client 'langfuse' is missing from services.identity.oidc.clients; check systems.oauth2.langfuse in policy/identity.json and the host's kanidm-admin web-policy route.";
          }
          {
            assertion = !cfg.oidc.enable || cfg.oidc.clientId != null;
            message = "services.langfuse.oidc.clientId must be set when OIDC is enabled.";
          }
          {
            assertion = !cfg.oidc.enable || cfg.oidc.issuerUrl != "";
            message = "services.langfuse.oidc.issuerUrl must be set when OIDC is enabled.";
          }
          (secretHelpers.mkRequiredSecretAssertion {
            enable = cfg.oidc.enable;
            file = cfg.secretFiles.oidc;
            feature = "services.langfuse.oidc";
            label = "secretFiles.oidc";
          })
        ];

        # Self-registration (D-058): the database, role, and credential this service
        # needs, declared next to the service that uses them. The provider reads the
        # same file and key to provision the role, so the password has one
        # authoritative source. The worker reaches the database over the bridge, so
        # the role accepts the bridge range; the web container shares the host
        # network namespace, so it arrives as the service address itself. No
        # extensions: upstream's compose installs none and Prisma manages the schema.
        # Gated on the secret file existing (the two-step sops bootstrap binds the
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
            serviceAddress
            containerSourceCIDR
          ];
        };

        # ClickHouse: declarative server and user configuration. The application
        # user's password reaches the server without entering the Nix store: the
        # server loads substitutions from a sops-rendered runtime file via the
        # user fragment's own include_from — never a global config.d
        # registration: a second substitution file shadows the first's
        # variables during incl resolution and auth parses as empty (observed
        # against latitude's fragment), and the user fragment references the
        # substitution by name (incl). ClickHouse
        # stores password_sha256_hex, so the substitution file carries the SHA-256
        # digest of the same plaintext the containers authenticate with.
        services.clickhouse = {
          enable = true;
          # The host package set's ClickHouse. The dedicated nixpkgs pin is gone:
          # this baseline pins LLVM 22 for the build, which is the condition the
          # pin worked around, and the package substitutes again (D-093).
          package = pkgs.clickhouse;
          serverConfig = {
            listen_host = [
              loopback
              serviceAddress
            ];
            http_port = clickhouseHttpPort;
            tcp_port = 9000;
          };
          usersConfig = { };
          extraUsersConfig = clickhouseUsers;
        };
        systemd.services.clickhouse.restartTriggers = lib.optional hasSecretFile clickhouseUsers;
        # Footgun: sops-install-secrets can leave /run/secrets/rendered
        # untraversable for non-root readers (0750 root:root observed in a live
        # deploy); clickhouse's loadConfiguration is the only such reader here.
        # NixOS has no /bin — reference the store path, or the ExecStartPre
        # itself fails the unit (observed: "Unable to locate executable
        # '/bin/chmod'").
        systemd.services.clickhouse.serviceConfig.ExecStartPre =
          lib.optional hasSecretFile "+${pkgs.coreutils}/bin/chmod 0755 /run/secrets/rendered";

        # Queue + cache only: no persistence, loopback + service address.
        services.redis.servers.langfuse = {
          enable = true;
          bind = "${loopback} ${serviceAddress}";
          port = 6379;
          # The secret file is absent during the two-step bootstrap window; the
          # fail-closed assertion blocks any deploy in that state, so the
          # passwordless fallback only ever exists in evaluation.
          requirePassFile = if hasSecretFile then config.sops.secrets.langfuse_redis_password.path else null;
          save = [ ]; # no RDB snapshots: the queue is ephemeral
          appendOnly = false;
        };

        # svc0 exists only once systemd-networkd has applied it — an ordering no unit
        # dependency can express — so a start that races the address retries.
        systemd.services.clickhouse.serviceConfig = {
          Restart = "on-failure";
          RestartSec = 5;
        };
        systemd.services."redis-langfuse".serviceConfig = {
          Restart = "on-failure";
          RestartSec = 5;
        };

        sops.templates."langfuse.environment" = lib.mkIf hasSecretFile {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            # --- authoritative metadata (PostgreSQL substrate) ---
            # One name for both containers (worker: across its bridge; web: host netns).
            DATABASE_URL=postgresql://langfuse:${config.sops.placeholder.langfuse_postgres_password}@${serviceHost}:${toString localPostgres.port}/langfuse

            # --- ClickHouse (traces/observations/scores) ---
            CLICKHOUSE_URL=${clickhouseUrl}
            CLICKHOUSE_MIGRATION_URL=${clickhouseMigrationUrl}
            CLICKHOUSE_USER=langfuse
            CLICKHOUSE_PASSWORD=${config.sops.placeholder.langfuse_clickhouse_password}
            CLICKHOUSE_CLUSTER_ENABLED=false

            # --- Redis (ingestion queue) ---
            REDIS_HOST=${serviceHost}
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
            NEXTAUTH_URL=${if publicUrl != null then publicUrl else "http://127.0.0.1:${toString cfg.port}"}
            TELEMETRY_ENABLED=false

            # --- OIDC (Kanidm): provider block only when enabled; secret via sops ---
            ${oidcEnv}

            # --- first-run bootstrap (operator rotates after first login) ---
            # The full seed set: LANGFUSE_INIT_ORG_ID gates the whole block —
            # without it upstream logs a warning and silently ignores the user
            # seed, which is how this instance started with no org, project or
            # keys. Idempotent upstream: resources are created only if absent.
            LANGFUSE_INIT_ORG_ID=shrublab
            LANGFUSE_INIT_ORG_NAME=Shrublab
            LANGFUSE_INIT_PROJECT_ID=shrublab
            LANGFUSE_INIT_PROJECT_NAME=Shrublab
            LANGFUSE_INIT_PROJECT_PUBLIC_KEY=${config.sops.placeholder.langfuse_otel_public_key}
            LANGFUSE_INIT_PROJECT_SECRET_KEY=${config.sops.placeholder.langfuse_otel_secret_key}
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
            langfuse_otel_public_key = {
              key = "otel/public_key";
              path = "/run/secrets/langfuse.otel_public_key";
            };
            langfuse_otel_secret_key = {
              key = "otel/secret_key";
              path = "/run/secrets/langfuse.otel_secret_key";
            };
          }
          // lib.optionalAttrs cfg.oidc.enable (
            secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
              langfuse_oidc_client_secret = {
                key = "langfuse/client_secret";
                path = "/run/secrets/langfuse.oidc_client_secret";
              };
            }
          )
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

        # The org/project/user seed (LANGFUSE_INIT_*) reads sops placeholders in
        # the environment template, so a langfuse restart re-runs upstream's
        # idempotent first-run init after a rotation.
        systemd.services.podman-langfuse-web.restartTriggers =
          lib.optional hasSecretFile
            config.sops.templates."langfuse.environment".path;

        virtualisation.podman.enable = true;

        systemd.services."podman-network-${cfg.networkName}" = {
          description = "Create Podman network ${cfg.networkName}";
          wantedBy = [ "multi-user.target" ];
          before = [ "podman-langfuse-worker.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${cfg.networkName} || ${pkgs.podman}/bin/podman network create ${cfg.networkName}'";
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
          extraOptions = [
            "--network=host"
            "--add-host=${serviceHost}:${serviceAddress}"
          ];
          # No `ports`: host networking shares the host's own listener. The add-host
          # entry lets the web role dial native services by the same stable name the
          # worker uses, whatever namespace it runs in.
        };

        # langfuse-worker: drains the Redis queue into ClickHouse. No inbound ports;
        # it keeps its own bridge, so it stays off the host network namespace, and
        # reaches the native stateful roles through the host's service address.
        virtualisation.oci-containers.containers.langfuse-worker = {
          autoStart = true;
          image = cfg.workerImage;
          environmentFiles = lib.optionals hasSecretFile [
            config.sops.templates."langfuse.environment".path
          ];
          extraOptions = [
            "--network=${cfg.networkName}"
            "--add-host=${serviceHost}:${serviceAddress}"
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
              requires = [
                "podman-network-${cfg.networkName}.service"
                "postgresql-provision.service"
              ];
            };
          };
        };

        # The stateful roles are reachable from the host itself (loopback) and from
        # containers through the service address; these are the only grants, scoped to
        # the Podman pool rather than to a bridge interface.
        networking.firewall.extraCommands = lib.mkIf cfg.enable (
          lib.concatStringsSep "\n" [
            (netHelpers.mkServiceIngressRule {
              sourceCIDR = containerSourceCIDR;
              address = serviceAddress;
              ports = [
                clickhouseHttpPort
                9000
              ];
            })
            (netHelpers.mkServiceIngressRule {
              sourceCIDR = containerSourceCIDR;
              address = serviceAddress;
              ports = [ 6379 ];
            })
          ]
        );

        # No state-backups registration: the aspect owns no local durable state.
        # ClickHouse traces are regenerable under retention (design D9), Redis holds
        # no durable state, the containers are stateless, and the PostgreSQL
        # `langfuse` database rides the substrate's export-first dump contract.
      };
    };
}
