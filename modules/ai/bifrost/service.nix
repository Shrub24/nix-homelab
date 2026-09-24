# Consumer contributor for the `bifrost` aspect: this repository's providers,
# credentials and exposure policy over nix-fleet's gateway service.
#
# The mechanism moved upstream — the sibling owner ./bifrost.nix imports
# nix-fleet's `flake.modules.nixos.bifrost`. The fleet owns the runtime package,
# the `bifrost` service account, the application directory, the installation of
# the startup configuration, the unit lifecycle and the failure notification.
# Policy stays here: the provider and routing document, the plugin
# registrations, the SOPS-rendered environment, the container-facing ingress
# rule, the backup contract, the secret-rotation restart, and the URLs consumers
# dial. Import is deployment, so this file defines no `enable`.
#
# Networking follows the fleet's three-class rule: the gateway binds the host's
# own listener (no container network in between), so the NixOS firewall gates
# reachability. Tailnet peers arrive through the foundation aspect's tailscale0
# trust; containers arrive through the service address, which this module admits
# for podman's bridge supernet and nothing else.
{
  flake.modules.nixos.bifrost =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.bifrost;
      secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
      netHelpers = import ../../../lib/networking.nix { inherit lib; };

      # Containers dial the host's service address by name. `host.containers.internal`
      # resolves to whichever bridge gateway a container happens to have, and a
      # bridged container's traffic to the host arrives on the input chain, where
      # nothing admits it to this port.
      serviceNetwork = (import ../../../policy/globals.nix).serviceNetwork;

      # The repo-owned provider and routing document. Its `plugins` member is
      # dropped here because the configuration schema keeps exactly one owner for
      # that member — the options below, which is also the only place the native
      # plugin's path can be resolved from the fleet package.
      gatewaySettings = builtins.removeAttrs (builtins.fromJSON (
        builtins.readFile ../../../policy/bifrost-config.json
      )) [ "plugins" ];

      # The plugin has to be built from the same module graph and toolchain as
      # the binary; nix-fleet publishes both from one revision for that reason.
      voyagePlugin = "${config.repo.packages.bifrost-voyage-plugin}/lib/bifrost/voyage.so";

      appDir = cfg.dataDir;
      logsDir = "${appDir}/logs";
      logsDbPath = "${appDir}/logs.db";
      cacheDir = "${appDir}/cache";
      vectorDir = "${appDir}/vector";

      hostBase = "http://127.0.0.1:${toString cfg.port}";
      containerBase = "http://${serviceNetwork.hostName}:${toString cfg.port}";
    in
    {
      imports = [ ../../backups/state-backups/_consumer.nix ];

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
          # This fleet's state path, not the mechanism's default. It is the
          # application directory itself: the runtime resolves `config.json` and
          # all of its state against it.
          dataDir = lib.mkDefault "/srv/data/bifrost/app";

          # Consumers reach the gateway over the tailnet or through the service
          # address, and the firewall decides which of those is admitted, so the
          # listener has to take both.
          host = "0.0.0.0";

          settings = gatewaySettings;

          environmentFile = config.sops.templates."bifrost.environment".path;

          plugins = {
            # The gateway's own OTLP exporter. `collector_url` is the AI lane's
            # canonical endpoint, set by the aspect owner (the relay shape: no
            # collector is co-hosted); HTTP because that is the receiver path the
            # runtime accepts. Span metadata and `llm.call` only — no prompt or
            # completion content reaches the store.
            otel = {
              config = {
                enabled = true;
                traces_enabled = true;
                protocol = "http";
                trace_type = "genai_extension";
                service_name = "bifrost";
                export_timeout = 5;
                disable_content_logging = true;
              };
            };

            # The normalizer strips the `encoding_format: "float"` field Voyage
            # rejects and maps `dimensions` to `output_dimension` — the one place
            # docs-mcp's hardcoded field is repaired for every consumer (D-078).
            voyage-normalizer = {
              path = voyagePlugin;
              placement = "post_builtin";
            };
          };
        };

        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            enable = true;
            file = cfg.secretFiles.host;
            feature = "services.bifrost";
            label = "secretFiles.host";
          })
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

        # A container reaches the gateway only through the service address: the
        # rule is source-scoped to podman's supernet and destination-scoped to
        # that address and port, so it admits nothing else.
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
          # The runtime's own scratch and state areas — the directories the
          # backup above excludes. The application directory itself is the fleet
          # module's.
          tmpfiles.rules = [
            "d ${logsDir} 0700 bifrost bifrost - -"
            "d ${cacheDir} 0700 bifrost bifrost - -"
            "d ${vectorDir} 0700 bifrost bifrost - -"
          ];

          # What recreates the process on a credential rotation: the rendered
          # environment file sits at a stable path, so systemd cannot see its
          # content change — the blind spot D-077 records for containers applies
          # to a native unit too, and `container-env` does not reach it. The
          # fleet's own `restartTriggers` covers the rendered configuration; this
          # half is the consumer's, because the secret file is.
          services.bifrost.restartTriggers = [ cfg.secretFiles.host ];
        };
      };
    };
}
