# Cockpit deployment aspect (dendritic Stage 7, D-053). Published from this
# discovered contributor and selected on both `oci-melb-1` and `la-admin-1`
# (S7-2). Selecting the aspect imports the Cockpit leaf — whose `enable`
# default is true — and owns only wiring that is common to both hosts:
# the dedicated service user and the common service-user secret registration.
#
# Host variants stay explicit: `publicHost`/`urlRoot` (OCI mkForce overrides)
# and `loopbackTls.enable` (LA) remain host-local. The secret is registered
# under the same two-step gate the OCI host used: the conventional
# `secrets/hosts/<hostName>/system.yaml` must exist before the secret is
# declared, which is identical in effect for both selected hosts (LA's
# registration was unconditional and its file exists).
{ ... }:
{
  flake.modules.nixos.cockpit =
    {
      lib,
      config,
      ...
    }:
    let
      hostSecretFile = ../../secrets/hosts + "/${config.networking.hostName}/system.yaml";
      hasHostSecrets = builtins.pathExists hostSecretFile;
    in
    {
      imports = [ ../services/admin/cockpit.nix ];

      services.admin.cockpit = {
        serviceUser = {
          enable = true;
          name = "cockpit-svc";
          hashedPasswordFile = config.sops.secrets.cockpit_service_user_password_hash.path;
        };

        tailscaleServe.enable = true;
      };

      sops.secrets = lib.optionalAttrs hasHostSecrets {
        cockpit_service_user_password_hash = {
          sopsFile = hostSecretFile;
          key = "cockpit/service_user/password_hash";
          path = "/run/secrets/cockpit.service_user.password_hash";
          owner = "root";
          group = "root";
          mode = "0400";
        };
      };
    };
}
