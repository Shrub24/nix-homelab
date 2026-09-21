# Beszel hub deployment aspect: selection imports the leaf and owns its
# enablement; the runtime composition (policy public URL, origin host/port, and
# the state-backups registration) stays in the leaf, which reads only the
# canonical web policy.
{ ... }:
{
  flake.modules.nixos.beszel =
    { lib, config, ... }:
    let
      cfg = config.services.admin.beszel;

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
      imports = [ ../backups/state-backups/_consumer.nix ];
      options.services.admin.beszel.enable = lib.mkEnableOption "the Beszel hub service wiring";
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
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
        })
        ({
          services.admin.beszel.enable = true;
        })
      ];
    };
}
