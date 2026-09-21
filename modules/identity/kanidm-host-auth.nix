{ ... }:
{
  flake.modules.nixos.kanidm-host-auth =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.identity.hostAuth;
      kanidmPackages = import ./_kanidm-packages.nix { inherit pkgs; };
    in
    {
      imports = [ ./_oidc.nix ];

      options.services.identity.hostAuth = {
        enable = lib.mkEnableOption "Kanidm-backed host auth integration";

        sshIntegration = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable Kanidm-backed SSH key integration for this host.";
        };

        pamAllowedLoginGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Explicit Kanidm groups allowed to log in through PAM on this host.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.kanidm = {
          package = lib.mkDefault kanidmPackages.client;

          client = {
            enable = true;
            settings.uri = config.services.identity.oidc.providerUrl;
          };

          unix = {
            enable = true;
            inherit (cfg) sshIntegration;
            settings.kanidm.pam_allowed_login_groups = cfg.pamAllowedLoginGroups;
          };
        };

        assertions = [
          {
            assertion = config.services.identity.oidc.providerUrl != null;
            message = "services.identity.hostAuth.enable requires services.identity.oidc.providerUrl to be set.";
          }
          {
            assertion = cfg.pamAllowedLoginGroups != [ ];
            message = "services.identity.hostAuth.pamAllowedLoginGroups must be non-empty when host auth is enabled.";
          }
        ];
      };
    };
}
