{
  lib,
  config,
  ...
}:
let
  appCfg = config.applications.admin;
  cfg = config.services.admin.beszel;
  beszelRoute = appCfg.policyServices."beszel-admin";
  appUrl = beszelRoute.publicUrl;
  host = beszelRoute.origin.host;
  port = beszelRoute.origin.port;
in
{
  options.services.admin.beszel.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable admin-owned Beszel hub service wiring.";
  };

  config = lib.mkIf (appCfg.enable && cfg.enable) {
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
