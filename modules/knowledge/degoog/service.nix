# Sibling contributor to the `degoog` aspect: the fleet contract and body for the
# capability, published as the same `flake.modules.nixos.degoog` name that
# ../degoog.nix declares. Discovery reaches it; the aspect owner imports nothing
# from here.
{
  flake.modules.nixos.degoog =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.degoog;
      secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
      stateDir = "/var/lib/degoog";
      # Two-step sops bootstrap: the host binds the path before the operator has
      # encrypted anything, so "has secrets" means the file is really there.
      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;
    in
    {
      options.services.degoog.secretFiles.host = secretHelpers.mkSecretFileOption "degoog-host-secrets";

      config = lib.mkIf cfg.enable {
        assertions = [
          (secretHelpers.mkRequiredSecretAssertion {
            inherit (cfg) enable;
            file = cfg.secretFiles.host;
            feature = "services.degoog";
            label = "secretFiles.host";
          })
        ];

        sops.templates."degoog.environment" = lib.mkIf hasSecretFile {
          owner = "root";
          group = "root";
          mode = "0400";
          content = ''
            DEGOOG_SETTINGS_PASSWORDS=${config.sops.placeholder.degoog_settings_password}
          '';
        };

        sops.secrets = lib.mkIf hasSecretFile (
          secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
            degoog_settings_password = {
              key = "settings_password";
              path = "/run/secrets/degoog.settings_password";
            };
          }
        );

        services.degoog = {
          # A single-operator instance behind the edge proxy: no public-instance
          # flags, no first-run wizard, and the proxy in front of it is trusted.
          environment = {
            DEGOOG_PUBLIC_INSTANCE = false;
            DEGOOG_WIZARD = false;
            DEGOOG_DISTRUST_PROXY = true;
          };

          environmentFile = lib.mkIf hasSecretFile config.sops.templates."degoog.environment".path;
        };

        services.state-backups.services.degoog = {
          enable = true;
          mode = "live";
          paths = [ stateDir ];
        };
      };
    };
}
