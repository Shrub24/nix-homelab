# Sibling contributor to the `docs-mcp` aspect: the fleet contract and body for the
# capability, published as the same `flake.modules.nixos.docs-mcp` name that
# ../docs-mcp.nix declares. Discovery reaches it; the aspect owner imports nothing
# from here.
{
  flake.modules.nixos.docs-mcp =
    {
      config,
      lib,
      pkgs,
      ...
    }:

    let
      cfg = config.services.docs-mcp;
      globals = import ../../../policy/globals.nix;
      exportDir = "${config.services.state-backups.stagingRoot}/docs-mcp";
    in
    {
      options.services.docs-mcp = {
        enable = lib.mkEnableOption "docs-mcp-server (grounded documentation index)";

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
          default = 6280;
          description = "Port for MCP, the web interface, and the API (single-port standalone mode).";
        };

        telemetry = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the server reports usage telemetry to PostHog.";
        };

        embedding = {
          baseUrl = lib.mkOption {
            type = lib.types.str;
            description = ''
              OpenAI-compatible embeddings endpoint, without the trailing /v1 path
              requirement imposed by a client library. The host states which endpoint
              it uses because the gateway is a physical cross-host service and the
              web catalog deliberately exposes no origins.
            '';
          };

          model = lib.mkOption {
            type = lib.types.str;
            default = globals.bifrost.aliases.embedding;
            description = ''
              Model name sent to the embeddings endpoint. It must equal the name
              recorded in the database; see the migration notes above.
            '';
          };
        };
      };

      config = lib.mkIf cfg.enable {
        virtualisation = {
          podman.enable = true;

          oci-containers.containers.docs-mcp = {
            autoStart = true;
            inherit (cfg) image;
            # Host networking, no port publish. A published port bypasses the NixOS
            # firewall on every interface, and podman cannot scope a publish to the
            # tailnet interface without a bind address this repository does not know
            # at evaluation time. On the host network namespace the server's own
            # listener is an ordinary host socket, and the firewall filters it: the
            # foundation aspect trusts `tailscale0` and default-denies the rest, so
            # the service ends up tailnet-only with no extra configuration.
            extraOptions = [ "--network=host" ];
            environment = {
              DOCS_MCP_PROTOCOL = "http";
              DOCS_MCP_STORE_PATH = "/data";
              DOCS_MCP_TELEMETRY = lib.boolToString cfg.telemetry;
              DOCS_MCP_EMBEDDING_MODEL = cfg.embedding.model;
              OPENAI_API_BASE = cfg.embedding.baseUrl;
              # The gateway on the private network takes no client credential; this
              # value is the placeholder its other consumers already pass.
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

        # SQLite cannot be copied coherently while it is being written, so the store
        # is exported through sqlite3's own backup API and restic captures the
        # export; the rendered config is small enough to copy as it stands.
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
      };
    };
}
