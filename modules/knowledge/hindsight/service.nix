# Sibling contributor to the `hindsight` aspect: the fleet contract and body for the
# capability, published as the same `flake.modules.nixos.hindsight` name that
# ../hindsight.nix declares. Discovery reaches it; the aspect owner imports nothing
# from here.
{
  flake.modules.nixos.hindsight =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      cfg = config.services.hindsight;
      secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
      cacheDir = "${cfg.dataDir}/cache";
      environmentFile = config.sops.templates."hindsight.environment".path;
      # Two-step sops bootstrap: the host binds the path before the operator has
      # encrypted anything, so "has secrets" means the file is really there.
      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;
      # The cluster this host runs, when it runs one; probed through `options`
      # because reading an undeclared option path raises NixOS' "did you mean"
      # error rather than returning null.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
    in
    {
      imports = [ ../../database/postgres/_consumer.nix ];

      options.services.hindsight = {
        enable = lib.mkEnableOption "Hindsight agent memory";

        image = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.hindsight;
          description = "Hindsight container image reference (tag + digest).";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data/hindsight";
          description = "Host directory holding runtime state and the model cache.";
        };

        apiPort = lib.mkOption {
          type = lib.types.port;
          default = 8888;
          description = "Host and container port for the Hindsight API.";
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

        llm = {
          provider = lib.mkOption {
            type = lib.types.str;
            default = "openai";
            description = "Hindsight LLM provider; the host-local router is OpenAI-compatible.";
          };

          baseUrl = lib.mkOption {
            type = lib.types.str;
            default = "http://127.0.0.1:20128/v1";
            description = "OpenAI-compatible base URL of the host-local model router.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Model name the router serves for Hindsight (required; the router's catalog is imperative).";
          };

          apiKeyKey = lib.mkOption {
            type = lib.types.str;
            default = "llm/api_key";
            description = "SOPS YAML key path for the router API key inside secretFiles.host.";
          };
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "hindsight-host-secrets";
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            inherit (cfg) enable;
            file = cfg.secretFiles.host;
            feature = "services.hindsight";
            label = "secretFiles.host";
          })
          {
            assertion = cfg.llm.model != "";
            message = "services.hindsight.llm.model must name a model the host-local router serves.";
          }
          {
            assertion = !cfg.enable || localPostgres != null;
            message = "services.hindsight.enable is true but this host runs no PostgreSQL cluster (select the postgres aspect and declare services.postgres.instances.<name>).";
          }
        ];

        # Register with the PostgreSQL substrate (D-058). The consumer owns its
        # credential: the provider reads the same file and key to provision the
        # role, so the password has one authoritative source. Loopback-only
        # reachability, because the container runs on the host network namespace.
        services.postgres.consumers.hindsight = lib.mkIf (cfg.enable && hasSecretFile) {
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
          # Server-side package, composed through the instance's own extension set
          # so it always matches the server version; the SQL name stays here
          # because extension packages carry no `passthru.extensionName`.
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
            HINDSIGHT_API_LLM_API_KEY=${config.sops.placeholder.hindsight_llm_api_key}
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
              HINDSIGHT_API_VECTOR_EXTENSION = cfg.vectorExtension;
              HINDSIGHT_ENABLE_API = "true";
              HINDSIGHT_ENABLE_CP = "true";
              HINDSIGHT_CP_PORT = toString cfg.controlPlanePort;
              HINDSIGHT_CP_DATAPLANE_API_URL = "http://127.0.0.1:${toString cfg.apiPort}";
              HINDSIGHT_API_LLM_PROVIDER = cfg.llm.provider;
              HINDSIGHT_API_LLM_MODEL = cfg.llm.model;
              HINDSIGHT_API_LLM_BASE_URL = cfg.llm.baseUrl;
            };
            environmentFiles = lib.optionals hasSecretFile [ environmentFile ];
            volumes = [ "${cacheDir}:/home/hindsight/.cache" ];
          };
        };

        systemd = {
          services."podman-hindsight" = {
            wants = [ "network-online.target" ];
            after = [ "network-online.target" ];
            unitConfig = {
              RequiresMountsFor = [ cfg.dataDir ];
              # Crash-loop budget: slow systemd-driven restarts to 15s and cap them
              # at 5 per hour so a persistent crash fails the unit (and alerts via
              # svc-monitor) instead of looping silently.
              StartLimitIntervalSec = 3600;
              StartLimitBurst = 5;
            };
            serviceConfig.RestartSec = "15s";
            restartTriggers = lib.optionals hasSecretFile [ environmentFile ];
          };

          tmpfiles.rules = [
            "d ${cfg.dataDir} 0755 root root - -"
            "z ${cfg.dataDir} 0755 root root - -"
            # The image runs as its own unprivileged user, UID/GID 1000.
            "d ${cacheDir} 0755 1000 1000 - -"
            "z ${cacheDir} 0755 1000 1000 - -"
          ];
        };

        services.state-backups.services.hindsight = {
          enable = true;
          mode = "live";
          paths = [ cfg.dataDir ];
          exclude = [ cacheDir ];
        };
      };
    };
}
