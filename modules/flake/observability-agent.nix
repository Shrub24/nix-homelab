# Observability agent: Beszel agent authentication and enrollment. The aspect
# derives the conventional host secret path and gates enrollment on its
# existence; the Beszel hub remains an admin-service leaf.

_: {
  flake.modules.nixos.observability-agent =
    { config, lib, ... }:
    let
      hostSystemSecret = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSystemSecret;

      cfg = config.services.beszel-agent-auth;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
    in
    {
      options.services.beszel-agent-auth = {
        enable = lib.mkEnableOption "Beszel agent auth wiring";

        secretFiles.host = secretHelpers.mkSecretFileOption "beszel-agent-host-secrets";

        secretKeyPrefix = lib.mkOption {
          type = lib.types.str;
          default = "beszel";
          description = "SOPS key prefix for Beszel agent secrets.";
        };
      };
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          assertions = [
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
              file = cfg.secretFiles.host;
              feature = "services.beszel-agent-auth";
              label = "secretFiles.host";
            })
          ];

          sops.templates."beszel-agent.env" = {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              KEY=${config.sops.placeholder.beszel_agent_key}
              TOKEN=${config.sops.placeholder.beszel_agent_token}
            '';
          };

          sops.secrets =
            secretHelpers.mkSecretsFromMap ../../secrets/common.yaml {
              beszel_agent_key = {
                key = "beszel/key";
                path = "/run/secrets/beszel.agent.key";
              };
            }
            // secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              beszel_agent_token = {
                key = "${cfg.secretKeyPrefix}/token";
                path = "/run/secrets/beszel.agent.token";
              };
            };

          services.beszel.agent = {
            enable = true;
            environmentFile = config.sops.templates."beszel-agent.env".path;
          };
        })
        {
          services.beszel-agent-auth = lib.mkIf hasHostSecrets {
            enable = true;
            secretFiles.host = hostSystemSecret;
          };

          # This aspect owns the `beszel-agent` unit through the auth
          # leaf, so it also owns its monitoring participation. The unit only exists
          # once the conventional host secret exists, so the contribution is gated
          # on the same two-step bootstrap predicate (no phantom target).
          services.notification-daemon.monitor.units."beszel-agent" = lib.mkIf hasHostSecrets {
            onFailure = true;
            onStart = true;
            onStop = true;
          };
        }
      ];
    };
}
