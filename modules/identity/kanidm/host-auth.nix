# Kanidm-backed Unix/PAM/SSH integration. It resolves the Kanidm service from its own
# policy route, so application SSO may move to another provider without retargeting
# host login, and it selects no application identity client.
_: {
  flake.modules.nixos.kanidm-host-auth =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.identity.hostAuth;
      kanidmPackages = import ./_packages.nix { inherit pkgs; };
      identityPolicy = import ../../../policy/identity.nix;
      kanidmRouteKey = identityPolicy.providers.kanidm.route or null;
      kanidmUrl =
        if kanidmRouteKey == null then
          null
        else
          lib.attrByPath [
            "repo"
            "web"
            "catalog"
            kanidmRouteKey
            "publicUrl"
          ] null config;
    in
    {
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
            settings.uri = kanidmUrl;
          };

          unix = {
            enable = true;
            inherit (cfg) sshIntegration;
            settings.kanidm.pam_allowed_login_groups = cfg.pamAllowedLoginGroups;
          };
        };

        assertions = [
          {
            assertion = kanidmUrl != null;
            message = "services.identity.hostAuth.enable requires a published Kanidm route; policy/identity.nix names '${toString kanidmRouteKey}' and the host's web policy must publish it.";
          }
          {
            assertion = cfg.pamAllowedLoginGroups != [ ];
            message = "services.identity.hostAuth.pamAllowedLoginGroups must be non-empty when host auth is enabled.";
          }
        ];
      };
    };
}
