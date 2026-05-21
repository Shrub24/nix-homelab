{
  lib,
  config,
  ...
}:
let
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

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
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
  };
}
