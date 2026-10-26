# docs-mcp: grounded documentation index (container, tailnet-only).
{
  config,
  inputs,
  ...
}:
let
  resolver = inputs.nix-fleet.lib.serviceEndpoints.resolveEndpoint config.fleet;

  # Resolved from the canonical inventory so a provider move cannot leave a copy behind.
  canonicalPort =
    (resolver {
      service = "docs-mcp";
      endpoint = "mcp";
      via = "tailnet";
    }).port;
  canonicalEmbeddingBaseUrl =
    (resolver {
      service = "bifrost";
      endpoint = "embeddings";
      via = "tailnet";
    }).url;
in
{
  flake.modules.nixos.docs-mcp =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.docs-mcp;
      globals = import ../../policy/globals.nix;
      exportDir = "${config.services.state-backups.stagingRoot}/docs-mcp";

      # Prefer `localEndpoint` where the gateway runs here, probed through `options`. It is a bare
      # origin; the canonical route already carries /v1.
      hasLocalBifrost = lib.hasAttrByPath [ "services" "bifrost" "localEndpoint" ] options;
      defaultEmbeddingBaseUrl =
        if hasLocalBifrost then
          "${config.services.bifrost.localEndpoint.url}/v1"
        else
          canonicalEmbeddingBaseUrl;
    in
    {
      options.services.docs-mcp = {
        image = lib.mkOption {
          type = lib.types.str;
          default = config.repo.ociImages.docsMcpServer;
          description = "docs-mcp-server image reference (tag + digest).";
        };

        dataDir = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data/docs-mcp";
          description = "Host directory holding the document store and the rendered config.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = canonicalPort;
          description = "Port for MCP, the web interface, and the API (single-port unified mode; nix-fleet's canonical docs-mcp/mcp record).";
        };

        telemetry = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the server reports usage telemetry to PostHog.";
        };

        embedding = {
          baseUrl = lib.mkOption {
            type = lib.types.str;
            default = defaultEmbeddingBaseUrl;
            description = "OpenAI-compatible embeddings endpoint; defaults to this host's `services.bifrost.localEndpoint` when the gateway runs here, else the canonical bifrost/embeddings record (a host may point it at another gateway).";
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = globals.bifrost.aliases.embedding;
            description = "Model name sent to the embeddings endpoint; it must match the name recorded in the store.";
          };
        };
      };

      config = lib.mkMerge [
        # Selection is enablement.

        {
          virtualisation = {
            podman.enable = true;

            oci-containers.containers.docs-mcp = {
              autoStart = true;
              inherit (cfg) image;
              # Host networking, no publish: a published port bypasses the firewall on every
              # interface.
              extraOptions = [ "--network=host" ];
              # `--protocol http` is explicit because `auto` picks stdio when there is no TTY;
              # one process then serves both the MCP endpoint and the dashboard.
              cmd = [
                "server"
                "--protocol"
                "http"
              ];
              environment = {
                DOCS_MCP_PROTOCOL = "http";
                DOCS_MCP_STORE_PATH = "/data";
                DOCS_MCP_TELEMETRY = lib.boolToString cfg.telemetry;
                DOCS_MCP_EMBEDDING_MODEL = cfg.embedding.model;
                OPENAI_API_BASE = cfg.embedding.baseUrl;
                # The gateway takes no client credential; this is the placeholder
                # its other consumers pass.
                OPENAI_API_KEY = "bifrost-local";
              };
              volumes = [
                "${cfg.dataDir}/data:/data"
                "${cfg.dataDir}/config:/config"
              ];
            };
          };

          systemd = {
            tmpfiles.rules = [
              "d ${cfg.dataDir} 0755 root root - -"
              "z ${cfg.dataDir} 0755 root root - -"
              # uid/gid 1000 is the unprivileged `node` user the image runs as.
              "d ${cfg.dataDir}/data 0755 1000 1000 - -"
              "z ${cfg.dataDir}/data 0755 1000 1000 - -"
              "d ${cfg.dataDir}/config 0755 1000 1000 - -"
              "z ${cfg.dataDir}/config 0755 1000 1000 - -"
            ];

            services."podman-docs-mcp" = {
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              unitConfig.RequiresMountsFor = [ cfg.dataDir ];
            };
          };

          # SQLite cannot be copied coherently while being written, so the store is
          # exported through sqlite3's backup API; the config copies as it stands.
          services.state-backups.services.docs-mcp = {
            enable = true;
            mode = "export";
            paths = [ "${cfg.dataDir}/config" ];
            exportPaths = [ "${exportDir}/documents.db" ];
            prepareCommands = [
              "${pkgs.coreutils}/bin/mkdir -p ${exportDir}"
              "${pkgs.sqlite}/bin/sqlite3 ${cfg.dataDir}/data/documents.db ${lib.escapeShellArg ".backup ${exportDir}/documents.db"}"
            ];
            cleanupCommands = [ "${pkgs.coreutils}/bin/rm -rf ${exportDir}" ];
          };
        }
      ];
    };
}
