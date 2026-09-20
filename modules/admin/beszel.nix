# Beszel hub deployment aspect (dendritic Stage 7, D-053; self-contained placement aspect since D-054). Published from this
# discovered contributor and selected only on `la-admin-1` (explicit
# `aspects.beszel`). Selecting the aspect imports the Beszel leaf and owns its
# enablement; the runtime composition — policy public URL, origin host/port,
# and the state-backups registration — stays in the leaf.
#
# Dependency direction (decouple-identity-admin-capabilities 3.2): the aspect
# and its leaf consume only the canonical web policy
# (`repo.web.currentHost.services`) and never read the
# `applications.admin` option namespace.
#
# Named dependency failure (feature-topology/admin-module-structure): a
# selection without the canonical `beszel-admin` web-policy route must fail
# through the leaf's named throw identifying the missing contract, not a raw
# missing-attribute error.

# Beszel hub composition (decoupled from the `applications.admin` namespace in
# decouple-identity-admin-capabilities 3.2): the policy public URL and origin
# host/port come from the canonical web policy (`repo.web.currentHost.services`).

{ ... }:
{
  flake.modules.nixos.beszel =
    { lib, config, ... }:
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
          # Selecting this aspect is the capability's top-level enablement.
          services.admin.beszel.enable = true;
        })
      ];
    };
}
