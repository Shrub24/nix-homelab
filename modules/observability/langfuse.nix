# LLM observability stack. Stateful roles run natively; the web and worker are
# digest-pinned containers. Selecting the aspect enables it.
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
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      hasSecretFile = cfg.secretFiles.host != null;

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
        # Attaches the identity to an account that already exists under the same verified
        # address. Without it NextAuth refuses the sign-in (OAuthAccountNotLinked) instead
        # of reaching the account the person already owns.
        AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING=true
      '';

      # Probed through `options`: reading an undeclared option path throws instead of returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;

      loopback = "127.0.0.1";
      globals = import ../../policy/globals.nix;
      serviceNetwork = globals.serviceNetwork;
      clickhouseHttpPort = globals.observability.clickhouseHttpPort;
      serviceAddress = serviceNetwork.address;
      serviceHost = serviceNetwork.hostName;
      containerSourceCIDR = serviceNetwork.containerSourceCIDR;
      netHelpers = import ../../lib/networking.nix { inherit lib; };

      # Fleet policy, not a literal: Home Assistant owns 8123 on home-forge.
      clickhouseUrl = "http://${serviceHost}:${toString clickhouseHttpPort}";
      clickhouseMigrationUrl = "clickhouse://${serviceHost}:9000";

      # include_from is read per loaded file, so the user fragment carries its own; it also restarts the unit.
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
        ../database/postgres/_consumer.nix
        ../identity/_oidc.nix
      ];

      options.services.langfuse = {
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
            default = if oidcClient == null then "" else oidcClient.providerName;
            defaultText = lib.literalExpression "services.identity.oidc.clients.langfuse.providerName";
            description = "Display name for the OIDC provider button (AUTH_CUSTOM_NAME).";
          };

          scope = lib.mkOption {
            type = lib.types.str;
            default = if oidcClient == null then "" else builtins.concatStringsSep " " oidcClient.scopes;
            defaultText = lib.literalExpression "services.identity.oidc.clients.langfuse.scopes";
            description = "OIDC scope string (AUTH_CUSTOM_SCOPE).";
          };

          idTokenSignedResponseAlg = lib.mkOption {
            type = lib.types.str;
            default = "ES256";
            description = ''
              Expected id_token signing algorithm. Kanidm signs ES256; openid-client
              defaults to RS256 and fails every callback when this is unset.
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

      config = lib.mkMerge [
        {

          assertions = [
            {
              assertion = localPostgres != null;
              message = "services.langfuse.enable is true but this host runs no PostgreSQL cluster (select the postgres aspect and declare services.postgres.instances.<name>).";
            }
            {
              assertion = config.services.clickhouse.enable;
              message = "services.langfuse.enable is true but the ClickHouse substrate is not selected (select the clickhouse aspect): its trace store has no server otherwise.";
            }
            {
              assertion = !cfg.oidc.enable || oidcClient != null;
              message = "services.langfuse.oidc: canonical OIDC client 'langfuse' is missing from services.identity.oidc.clients; check clients.langfuse in policy/identity.nix and the identity provider's published route.";
            }
            {
              assertion = !cfg.oidc.enable || cfg.oidc.clientId != null;
              message = "services.langfuse.oidc.clientId must be set when OIDC is enabled.";
            }
            {
              assertion = !cfg.oidc.enable || cfg.oidc.issuerUrl != "";
              message = "services.langfuse.oidc.issuerUrl must be set when OIDC is enabled.";
            }
          ];

          # Gated on the secret file: the two-step bootstrap binds the path before the operator encrypts it.
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

          # ClickHouse is the substrate, not this stack: the users fragment is
          # this consumer's whole contribution to the server.
          environment.etc."clickhouse-server/users.d/250-langfuse.xml" = lib.mkIf hasSecretFile {
            text = clickhouseUsers;
          };
          systemd.services.clickhouse.restartTriggers = lib.optional hasSecretFile clickhouseUsers;

          # Queue + cache only: no persistence, loopback + service address.
          services.redis.servers.langfuse = {
            enable = true;
            bind = "${loopback} ${serviceAddress}";
            port = 6379;
            # Passwordless only during evaluation: the required-secret assertion blocks deploy without the file.
            requirePassFile = if hasSecretFile then config.sops.secrets.langfuse_redis_password.path else null;
            save = [ ]; # no RDB snapshots: the queue is ephemeral
            appendOnly = false;
          };

          # svc0 appears only after networkd applies it, which no unit ordering expresses; retry the start.
          systemd.services."redis-langfuse".serviceConfig = {
            Restart = "on-failure";
            RestartSec = 5;
          };

          sops.templates."langfuse.environment" = lib.mkIf hasSecretFile {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              DATABASE_URL=postgresql://langfuse:${config.sops.placeholder.langfuse_postgres_password}@${serviceHost}:${toString localPostgres.port}/langfuse

              CLICKHOUSE_URL=${clickhouseUrl}
              CLICKHOUSE_MIGRATION_URL=${clickhouseMigrationUrl}
              CLICKHOUSE_USER=langfuse
              CLICKHOUSE_PASSWORD=${config.sops.placeholder.langfuse_clickhouse_password}
              CLICKHOUSE_CLUSTER_ENABLED=false

              REDIS_HOST=${serviceHost}
              REDIS_PORT=6379
              REDIS_AUTH=${config.sops.placeholder.langfuse_redis_password}

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

              ENCRYPTION_KEY=${config.sops.placeholder.langfuse_encryption_key}
              SALT=${config.sops.placeholder.langfuse_salt}
              NEXTAUTH_SECRET=${config.sops.placeholder.langfuse_nextauth_secret}
              NEXTAUTH_URL=${if publicUrl != null then publicUrl else "http://127.0.0.1:${toString cfg.port}"}
              TELEMETRY_ENABLED=false

              ${oidcEnv}

              # LANGFUSE_INIT_ORG_ID gates the whole seed block; without it upstream silently skips the user seed.
              LANGFUSE_INIT_ORG_ID=shrublab
              LANGFUSE_INIT_ORG_NAME=shrublab
              LANGFUSE_INIT_PROJECT_ID=shrublab
              LANGFUSE_INIT_PROJECT_NAME=shrublab
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
              # Digest of the same password, for the ClickHouse user fragment.
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

          # The operator stores both password forms in the secret file; ClickHouse references the digest by name.
          sops.templates."langfuse-clickhouse-substitutions" = lib.mkIf hasSecretFile {
            owner = "clickhouse";
            group = "clickhouse";
            mode = "0400";
            # The digest is read once at startup, so a rotation reaches the
            # running server only through this restart.
            restartUnits = [ "clickhouse.service" ];
            content = ''
              <clickhouse>
                <langfuse_ch_password>${config.sops.placeholder.langfuse_clickhouse_password_sha256}</langfuse_ch_password>
              </clickhouse>
            '';
          };

          # Restarting on rotation re-runs upstream's idempotent LANGFUSE_INIT seed.
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

          # Host network, not published ports: a published port would bypass the firewall on every interface.
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
          };

          # No inbound ports; reaches the native roles through the service address.
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

          # Container grants only: the Podman pool, not a bridge interface.
          networking.firewall.extraCommands = (
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

          # No state-backups registration: ClickHouse is regenerable, Redis is ephemeral, and the PostgreSQL database rides the substrate's export.
        }
      ];
    };
}
