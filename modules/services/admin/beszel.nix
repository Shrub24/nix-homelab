# Beszel hub composition (decoupled from the `applications.admin` namespace in
# decouple-identity-admin-capabilities 3.2): the policy public URL and origin
# host/port come from the canonical web policy (`repo.web.currentHost.services`).
{
  lib,
  config,
  ...
}:
let
  cfg = config.services.admin.beszel;

  # Named dependency failure (same pattern as gatus/vaultwarden/termix): a host
  # consuming this leaf without the canonical web-policy route must fail
  # through this throw, not a raw missing-attribute error. The safe `or { }`
  # lookup keeps the guard independent of any sibling `repo.web` declaration.
  webServices = config.repo.web.currentHost.services or { };
  beszelRoute =
    if webServices ? "beszel-admin" then
      webServices."beszel-admin"
    else
      throw "beszel: required canonical web-policy route 'repo.web.currentHost.services.\"beszel-admin\"' is missing for host '${
        config.networking.hostName or "?"
      }'";

  appUrl = beszelRoute.publicUrl;
  host = beszelRoute.origin.host;
  port = beszelRoute.origin.port;
in
{
  options.services.admin.beszel.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable admin-owned Beszel hub service wiring.";
  };

  config = lib.mkIf cfg.enable {
    services.beszel.hub = {
      enable = true;
      inherit host port;
      environment = {
        APP_URL = appUrl;
        DISABLE_PASSWORD_AUTH = "false";
        USER_CREATION = "true";
      };
    };

    services.state-backups.services.beszel = {
      enable = true;
      mode = "live";
      # dataDir is a symlink -> /var/lib/private/<basename> (systemd DynamicUser/StateDirectory remap); restic does not follow symlinks.
      paths = [ "/var/lib/private/${baseNameOf config.services.beszel.hub.dataDir}" ];
    };
  };
}
