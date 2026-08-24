{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.identity.hostAuth;
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
    services.kanidm.package = lib.mkDefault pkgs.kanidm_1_11;

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

    services.kanidm.client = {
      enable = true;
      settings.uri = config.services.identity.oidc.providerUrl;
    };

    services.kanidm.unix = {
      enable = true;
      sshIntegration = cfg.sshIntegration;
      settings.kanidm.pam_allowed_login_groups = cfg.pamAllowedLoginGroups;
    };
  };
}
