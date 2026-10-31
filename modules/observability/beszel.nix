# Beszel hub: selection imports the leaf and owns its enablement; the runtime composition
# reads only the canonical web policy.
_: {
  flake.modules.nixos.beszel =
    { lib, config, ... }:
    let
      cfg = config.services.admin.beszel;

      webServices = config.repo.web.catalog or { };
      beszelRoute =
        webServices."beszel-admin"
          or (throw "beszel: required canonical web-policy route 'repo.web.catalog.\"beszel-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'");

      appUrl = beszelRoute.publicUrl;
      host = "0.0.0.0";
      port = beszelRoute.upstreamPort;
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
      ];
      config = {

        services.beszel.hub = {
          enable = true;
          inherit host port;
          environment = {
            APP_URL = appUrl;
            # End users sign in through the identity provider only. PocketBase's superusers
            # collection is unaffected, so the hub's own console stays the break-glass path.
            DISABLE_PASSWORD_AUTH = "true";
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
    };
}
