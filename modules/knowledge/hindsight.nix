# hindsight: agent memory (container + PostgreSQL consumer, tailnet-only).
{
  config,
  inputs,
  ...
}:
let
  # Resolved from the canonical inventory so a provider move cannot leave a copy behind.
  canonicalApiPort =
    (inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet {
      service = "hindsight";
      endpoint = "api";
      via = "tailnet";
    }).port;
in
{
  flake.modules.nixos.hindsight =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      cfg = config.services.hindsight;
      globals = import ../../policy/globals.nix;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      environmentFile = config.sops.templates."hindsight.environment".path;
      # Two-step bootstrap: the host binds the path before the operator has
      # encrypted anything, so "has secrets" means the file is really there.
      hasSecretFile = cfg.secretFiles.host != null;
      # Probed through `options`: reading an undeclared option path raises NixOS'
      # "did you mean" error rather than returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
    in
    {
      # Declaration-only contract: the registration below evaluates on a host
      # that does not run the mechanism.
      imports = [ ../database/postgres/_consumer.nix ];

      options.services.hindsight = {
        image = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.hindsight;
          description = "Hindsight container image reference (tag + digest).";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data/hindsight";
          description = "Host directory holding runtime state.";
        };

        apiPort = lib.mkOption {
          type = lib.types.port;
          default = canonicalApiPort;
          description = "Host and container port for the Hindsight API (nix-fleet's canonical hindsight/api record).";
        };

        controlPlanePort = lib.mkOption {
          type = lib.types.port;
          default = 9999;
          description = "Host and container port for the Hindsight control-plane UI.";
        };

        logLevel = lib.mkOption {
          type = lib.types.str;
          default = "info";
          description = "Hindsight API log level.";
        };

        shmSize = lib.mkOption {
          type = lib.types.str;
          default = "1g";
          description = "Shared-memory size for the container (upstream recommends at least 1g).";
        };

        vectorExtension = lib.mkOption {
          type = lib.types.str;
          default = "pgvector";
          description = "Vector extension backend the database must provide.";
        };

        database.host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Host address the co-located cluster is reached on.";
        };

        database.poolMaxSize = lib.mkOption {
          type = lib.types.int;
          # Upstream defaults to 100 — the whole cluster's max_connections on
          # a shared substrate also serving langfuse/paperless/latitude.
          default = 20;
          description = "Primary connection pool ceiling for the hindsight API.";
        };

        llm = {
          provider = lib.mkOption {
            type = lib.types.str;
            default = "openai";
            description = "Hindsight LLM provider; the fleet gateway is OpenAI-compatible.";
          };

          baseUrl = lib.mkOption {
            type = lib.types.str;
            default =
              let
                # Prefer `localEndpoint` where the gateway runs here: placement names the
                # provider, so the catalog alone would cross the tailnet for a local socket.
                hasLocalBifrost = lib.hasAttrByPath [ "services" "bifrost" "localEndpoint" ] options;
                catalogEndpoint = lib.attrByPath [ "repo" "web" "catalog" "bifrost" "endpoint" "url" ] "" config;
              in
              if hasLocalBifrost then
                "${config.services.bifrost.localEndpoint.url}/v1"
              else if catalogEndpoint == "" then
                ""
              else
                "${catalogEndpoint}/v1";
            description = "OpenAI-compatible base URL of the fleet gateway (default: this host's `services.bifrost.localEndpoint` when the gateway runs here, else the `bifrost` route's endpoint; either way plus /v1).";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = globals.bifrost.aliases.text;
            description = "Model alias Hindsight's LLM calls carry; the gateway resolves the alias to a provider.";
          };

          retainModel = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Router model for retain passes; null uses llm.model.";
          };

          reflectModel = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Router model for reflect passes; null uses llm.model.";
          };

          consolidationModel = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Router model for consolidation passes; null uses llm.model.";
          };

          apiKeyKey = lib.mkOption {
            type = lib.types.str;
            default = "llm/api_key";
            description = "SOPS YAML key path for the gateway credential inside secretFiles.host (the gateway authenticates no client; the value is a placeholder).";
          };
        };

        embeddings = {
          provider = lib.mkOption {
            type = lib.types.str;
            default = "litellm-sdk";
            description = "Hindsight embeddings provider (litellm-sdk covers Voyage direct and any OpenAI-compatible gateway).";
          };

          baseUrl = lib.mkOption {
            type = lib.types.str;
            default = "https://api.voyageai.com/v1";
            description = "Embeddings endpoint: Voyage's API directly (default), or an OpenAI-compatible gateway.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = globals.bifrost.aliases.embedding;
            description = "Model id carrying its provider prefix — `voyage/…` selects Voyage-native params (input_type per side, dimensions).";
          };

          apiKeyKey = lib.mkOption {
            type = lib.types.str;
            default = "embeddings/api_key";
            description = "SOPS YAML key path for the gateway API key inside secretFiles.host.";
          };
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "hindsight-host-secrets";
      };

      config = lib.mkMerge [
        # Selection is enablement.

        {
          assertions = [
            {
              assertion = cfg.llm.model != "";
              message = "services.hindsight.llm.model must name a model alias the gateway serves.";
            }
            {
              assertion = cfg.llm.baseUrl != "";
              message = "services.hindsight.llm.baseUrl is empty: the `bifrost` route is missing from policy/web-services.nix, or this host does not evaluate the web policy.";
            }
            {
              assertion = cfg.embeddings.baseUrl != "";
              message = "services.hindsight.embeddings.baseUrl must name the embeddings endpoint (Voyage's API, or a gateway).";
            }
            {
              assertion = localPostgres != null;
              message = "services.hindsight.enable is true but this host runs no PostgreSQL cluster (select the postgres aspect and declare services.postgres.instances.<name>).";
            }
          ];

          # The consumer owns its credential: the provider reads the same file and key
          # to provision the role, so the password has one authoritative source.
          services.postgres.consumers.hindsight = {
            database = "hindsight";
            role = "hindsight";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/hindsight/password";
            };
            allowedCIDRs = [
              "127.0.0.1/32"
              "::1/128"
            ];
            # Through the instance's extension set to match the server version; the SQL
            # name stays because extension packages carry no `passthru.extensionName`.
            extensions = ps: [ ps.pgvector ];
            setupSQL = "CREATE EXTENSION IF NOT EXISTS vector;";
          };

          # The role password is interpolated into the connection string, so the
          # generated value must stay URL-safe (the secret template says so).
          sops.templates."hindsight.environment" = lib.mkIf hasSecretFile {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              HINDSIGHT_API_DATABASE_URL=postgresql://hindsight:${config.sops.placeholder.hindsight_postgres_password}@${cfg.database.host}:${toString localPostgres.port}/hindsight
              HINDSIGHT_API_DB_POOL_MAX_SIZE=${toString cfg.database.poolMaxSize}
              HINDSIGHT_API_LLM_API_KEY=${config.sops.placeholder.hindsight_llm_api_key}
              HINDSIGHT_API_EMBEDDINGS_PROVIDER=litellm-sdk
              HINDSIGHT_API_EMBEDDINGS_LITELLM_SDK_API_KEY=${config.sops.placeholder.hindsight_embeddings_api_key}
              HINDSIGHT_API_EMBEDDINGS_LITELLM_SDK_MODEL=${cfg.embeddings.model}
              HINDSIGHT_API_EMBEDDINGS_LITELLM_SDK_API_BASE=${cfg.embeddings.baseUrl}
              # Empty means omit: litellm's OpenAI path re-injects encoding_format="float",
              # which Voyage rejects outright.
              HINDSIGHT_API_EMBEDDINGS_LITELLM_SDK_ENCODING_FORMAT=
              HINDSIGHT_API_RERANKER_LITELLM_SDK_API_KEY=${config.sops.placeholder.hindsight_embeddings_api_key}
              HINDSIGHT_API_MCP_AUTH_TOKEN=${config.sops.placeholder.hindsight_mcp_auth_token}
            '';
          };

          sops.secrets = lib.mkIf hasSecretFile (
            secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              hindsight_postgres_password = {
                key = "roles/hindsight/password";
                path = "/run/secrets/hindsight.postgres_password";
              };
              hindsight_llm_api_key = {
                key = cfg.llm.apiKeyKey;
                path = "/run/secrets/hindsight.llm_api_key";
              };
              hindsight_embeddings_api_key = {
                key = cfg.embeddings.apiKeyKey;
                path = "/run/secrets/hindsight.embeddings_api_key";
              };
              hindsight_mcp_auth_token = {
                key = "mcp/auth_token";
                path = "/run/secrets/hindsight.mcp_auth_token";
              };
            }
          );

          virtualisation = {
            podman.enable = true;

            oci-containers.containers.hindsight = {
              autoStart = true;
              inherit (cfg) image;
              extraOptions = [
                "--network=host"
                "--shm-size=${cfg.shmSize}"
              ];
              environment = {
                HINDSIGHT_API_HOST = "0.0.0.0";
                HINDSIGHT_API_PORT = toString cfg.apiPort;
                HINDSIGHT_API_LOG_LEVEL = cfg.logLevel;
                # Keep the API/control plane online but stop background job claims
                # until this worker is intentionally re-enabled.
                HINDSIGHT_API_WORKER_ENABLED = "false";
                # Stable worker identity: the default is the container hostname,
                # which changes each restart and orphans claimed tasks.
                HINDSIGHT_API_WORKER_ID = "hindsight";
                HINDSIGHT_API_VECTOR_EXTENSION = cfg.vectorExtension;
                # The -slim image ships no local reranker, so route through voyage/.
                HINDSIGHT_API_RERANKER_PROVIDER = "litellm-sdk";
                HINDSIGHT_API_RERANKER_LITELLM_SDK_MODEL = "voyage/rerank-3";
                HINDSIGHT_ENABLE_API = "true";
                HINDSIGHT_ENABLE_CP = "true";
                HINDSIGHT_CP_PORT = toString cfg.controlPlanePort;
                HINDSIGHT_CP_DATAPLANE_API_URL = "http://127.0.0.1:${toString cfg.apiPort}";
                HINDSIGHT_API_LLM_PROVIDER = cfg.llm.provider;
                HINDSIGHT_API_LLM_MODEL = cfg.llm.model;
                HINDSIGHT_API_LLM_BASE_URL = cfg.llm.baseUrl;
              }
              // lib.optionalAttrs (cfg.llm.retainModel != null) {
                HINDSIGHT_API_RETAIN_LLM_MODEL = cfg.llm.retainModel;
              }
              // lib.optionalAttrs (cfg.llm.reflectModel != null) {
                HINDSIGHT_API_REFLECT_LLM_MODEL = cfg.llm.reflectModel;
              }
              // lib.optionalAttrs (cfg.llm.consolidationModel != null) {
                HINDSIGHT_API_CONSOLIDATION_LLM_MODEL = cfg.llm.consolidationModel;
              };
              environmentFiles = lib.optionals hasSecretFile [ environmentFile ];
            };
          };

          systemd = {
            services."podman-hindsight" = {
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              unitConfig = {
                RequiresMountsFor = [ cfg.dataDir ];
              };
              serviceConfig.RestartSec = "15s";
              restartTriggers = lib.optionals hasSecretFile [ environmentFile ];
            };

            tmpfiles.rules = [
              "d ${cfg.dataDir} 0755 root root - -"
              "z ${cfg.dataDir} 0755 root root - -"
            ];
          };

          services.state-backups.services.hindsight = {
            enable = true;
            mode = "live";
            paths = [ cfg.dataDir ];
          };
        }
      ];
    };
}
