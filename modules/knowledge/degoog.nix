# degoog: private search front end. The pinned upstream module owns the
# `services.degoog.*` runtime surface; this aspect adds the fleet contract.
{
  inputs,
  lib,
  ...
}:
{
  flake-file.inputs.degoog = {
    # A release, not a branch: the tag is what Renovate's custom regex manager
    # tracks (renovate.json). A tag bump that changes `bun.lock` must regenerate
    # `pkgs/degoog/bun.nix` in the same change, or `check-degoog-bun-deps` fails.
    url = "github:degoog-org/degoog/1.1.0";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.flake-parts.follows = "flake-parts";
  };

  # `pkgs/degoog/bun.nix` is generated data: a lock bump without a regenerated
  # expression builds the previous package set, so the file and the pin it
  # derives from are compared. Both sides are formatted first, so `nix fmt`
  # over the repository cannot invalidate the comparison.
  perSystem =
    { pkgs, system, ... }:
    {
      checks.check-degoog-bun-deps = pkgs.runCommandLocal "check-degoog-bun-deps" { } ''
        ${lib.getExe inputs.bun2nix.packages.${system}.default} \
          --lock-file ${inputs.degoog}/bun.lock --output-file bun.nix
        ${lib.getExe pkgs.nixfmt} bun.nix

        if ! diff -u ${../../pkgs/degoog/bun.nix} bun.nix; then
          echo "degoog: pkgs/degoog/bun.nix does not match the pinned lockfile" >&2
          echo "regenerate with: nix run .#update-packages -- degoog" >&2
          exit 1
        fi

        touch $out
      '';
    };

  flake.modules.nixos.degoog =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.degoog;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      # Upstream's unit is a DynamicUser under ProtectSystem=strict, so state
      # cannot move to /srv/data.
      stateDir = "/var/lib/degoog";
      # Two-step bootstrap: the host binds the path before the operator has
      # encrypted anything, so "has secrets" means the file is really there.
      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;
    in
    {
      imports = [ inputs.degoog.nixosModules.default ];

      options.services.degoog.secretFiles.host = secretHelpers.mkSecretFileOption "degoog-host-secrets";

      config = lib.mkMerge [
        # Selection is enablement. The package comes from this repository: the
        # upstream default generates its dependency expression during evaluation.
        {
          services.degoog.enable = true;
          services.degoog.package = config.repo.packages.degoog;
        }

        (lib.mkIf cfg.enable {
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
            # Behind Caddy, which does forward X-Forwarded-*; the flag is inverted
            # against its name (the app trusts a proxy only for "false"/"0").
            environment = {
              DEGOOG_PUBLIC_INSTANCE = false;
              DEGOOG_DISTRUST_PROXY = false;
            };

            environmentFile = lib.mkIf hasSecretFile config.sops.templates."degoog.environment".path;
          };

          services.state-backups.services.degoog = {
            enable = true;
            mode = "live";
            paths = [ stateDir ];
          };
        })
      ];
    };
}
