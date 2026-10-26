# Bifrost: the fleet's OpenAI-compatible gateway. Selection is deployment (no
# enable flag); nix-fleet provides the mechanism, this file the repository policy.
{
  config,
  inputs,
  ...
}:
let
  # The listen port and AI-lane collector are canonical records: a move is an
  # upstream edit plus a relock, not a local change.
  canonicalPort =
    (inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet {
      service = "bifrost";
      endpoint = "embeddings";
      via = "tailnet";
    }).port;

  otlpGateway =
    (inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet {
      service = "otel-collector";
      endpoint = "ai-otlp";
      via = "tailnet";
    }).url;
in
{
  flake.modules.nixos.bifrost =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.bifrost;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      netHelpers = import ../../lib/networking.nix { inherit lib; };

      # Containers dial the service address, not host.containers.internal: that
      # name resolves to a bridge gateway the input chain does not admit.
      serviceNetwork = (import ../../policy/globals.nix).serviceNetwork;

      # `plugins` is owned by services.bifrost.plugins below, so it is dropped here.
      gatewaySettings = builtins.removeAttrs (builtins.fromJSON (
        builtins.readFile ../../policy/bifrost-config.json
      )) [ "plugins" ];

      appDir = cfg.dataDir;
      logsDir = "${appDir}/logs";
      logsDbPath = "${appDir}/logs.db";
      cacheDir = "${appDir}/cache";
      vectorDir = "${appDir}/vector";

      hostBase = "http://127.0.0.1:${toString cfg.port}";
      containerBase = "http://${serviceNetwork.hostName}:${toString cfg.port}";
    in
    {
      imports = [
        inputs.nix-fleet.modules.nixos.bifrost
        ../backups/state-backups/_consumer.nix
      ];

      options.services.bifrost = {
        secretFiles.host = secretHelpers.mkSecretFileOption "bifrost-host-secrets";

        endpoint.hostBaseUrl = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "${hostBase}/v1";
        };

        endpoint.containerBaseUrl = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          default = "${containerBase}/v1";
        };
      };

      config = {
        services.bifrost = {
          port = lib.mkDefault canonicalPort;

          # The application directory itself: the runtime resolves config.json and its state here.
          dataDir = lib.mkDefault "/srv/data/bifrost/app";

          # Tailnet peers and the service address both reach this listener; the firewall picks which are admitted.
          host = "0.0.0.0";

          settings = gatewaySettings;

          environmentFile = config.sops.templates."bifrost.environment".path;

          plugins = {
            otel = {
              config = {
                enabled = true;
                traces_enabled = true;
                protocol = "http";
                trace_type = "genai_extension";
                service_name = "bifrost";
                export_timeout = 5;
                disable_content_logging = true;
                collector_url = lib.mkDefault "${otlpGateway}/v1/traces";
              };
            };

            # Strips `encoding_format: "float"`, which Voyage rejects; docs-mcp hardcodes it.
            voyage-normalizer = {
              path = "${config.repo.packages.bifrost-voyage-plugin}/lib/bifrost/voyage.so";
              placement = "post_builtin";
            };
          };
        };

        assertions = [
        ];

        sops.templates."bifrost.environment" = {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            BIFROST_ENCRYPTION_KEY=${config.sops.placeholder.bifrost_encryption_key}
            BIFROST_ADMIN_USERNAME=${config.sops.placeholder.bifrost_admin_username}
            BIFROST_ADMIN_PASSWORD=${config.sops.placeholder.bifrost_admin_password}
            GEMINI_API_KEY=${config.sops.placeholder.bifrost_gemini_api_key}
            DEEPSEEK_API_KEY=${config.sops.placeholder.bifrost_deepseek_api_key}
            OPENCODE_API_KEY=${config.sops.placeholder.bifrost_opencode_api_key}
            OPENCODE_API_KEY_2=${config.sops.placeholder.bifrost_opencode_api_key_2}
            OPENROUTER_API_KEY=${config.sops.placeholder.bifrost_openrouter_api_key}
            VOYAGE_API_KEY=${config.sops.placeholder.bifrost_voyage_api_key}
          '';
        };

        sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
          bifrost_encryption_key = {
            key = "bifrost/encryption_key";
            path = "/run/secrets/bifrost.encryption_key";
          };
          bifrost_admin_username = {
            key = "bifrost/admin_username";
            path = "/run/secrets/bifrost.admin_username";
          };
          bifrost_admin_password = {
            key = "bifrost/admin_password";
            path = "/run/secrets/bifrost.admin_password";
          };
          bifrost_gemini_api_key = {
            key = "bifrost/gemini_api_key";
            path = "/run/secrets/bifrost.gemini_api_key";
          };
          bifrost_deepseek_api_key = {
            key = "bifrost/deepseek_api_key";
            path = "/run/secrets/bifrost.deepseek_api_key";
          };
          bifrost_opencode_api_key = {
            key = "bifrost/opencode_api_key";
            path = "/run/secrets/bifrost.opencode_api_key";
          };
          bifrost_opencode_api_key_2 = {
            key = "bifrost/opencode_api_key_2";
            path = "/run/secrets/bifrost.opencode_api_key_2";
          };
          bifrost_openrouter_api_key = {
            key = "bifrost/openrouter_api_key";
            path = "/run/secrets/bifrost.openrouter_api_key";
          };
          bifrost_voyage_api_key = {
            key = "bifrost/voyage_api_key";
            path = "/run/secrets/bifrost.voyage_api_key";
          };
        };

        networking.firewall.extraCommands = netHelpers.mkServiceIngressRule {
          sourceCIDR = serviceNetwork.containerSourceCIDR;
          address = serviceNetwork.address;
          ports = [ cfg.port ];
        };

        services.state-backups.services.bifrost = {
          enable = true;
          mode = "live";
          paths = [ appDir ];
          exclude = [
            logsDir
            logsDbPath
            "${logsDbPath}-shm"
            "${logsDbPath}-wal"
            cacheDir
            vectorDir
          ];
        };

        systemd = {
          tmpfiles.rules = [
            "d ${logsDir} 0700 bifrost bifrost - -"
            "d ${cacheDir} 0700 bifrost bifrost - -"
            "d ${vectorDir} 0700 bifrost bifrost - -"
          ];

          # systemd cannot see the rendered env file's content change at its stable path, so a rotation restarts the unit here.
          services.bifrost.restartTriggers = [ cfg.secretFiles.host ];

          # The env file is installed by sops-install-secrets; start only after it.
          services.bifrost = {
            wants = [ "sops-install-secrets.service" ];
            after = [ "sops-install-secrets.service" ];
          };
        };
      };
    };
}
