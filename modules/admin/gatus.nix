# Gatus deployment aspect (dendritic Stage 7, D-053; self-contained placement aspect since D-054). Published from this
# discovered contributor and selected only on `la-admin-1` (explicit
# `aspects.gatus`). Selecting the aspect imports the Gatus leaf and owns its
# enablement; the runtime composition — policy origin host/port, the
# catalog-derived endpoint sweep, and the notification-daemon alert transport
# — stays in the leaf.
#
# Dependency direction (decouple-identity-admin-capabilities 3.2): the aspect
# and its leaf consume only the canonical web policy
# (`repo.web.currentHost.services`) and never read the
# `applications.admin` option namespace. Gatus has no secrets and no runtime
# paths.
#
# Named dependency failure (feature-topology/admin-module-structure): a
# selection without the canonical `gatus-admin` web-policy route must fail
# through the leaf's named throw identifying the missing contract, not a raw
# missing-attribute error.

# Gatus monitoring composition (decoupled from the `applications.admin`
# namespace in decouple-identity-admin-capabilities 3.2): the policy origin,
# the catalog-derived endpoint sweep, and the alert transport come from the
# canonical web policy (`repo.web.currentHost.services`).

{ ... }:
{
  flake.modules.nixos.gatus =
    { lib, config, ... }:
    let
      cfg = config.services.admin.gatus;

      # Named dependency failure (same pattern as vaultwarden/termix): a host
      # consuming this leaf without the canonical web-policy route must fail
      # through this throw, not a raw missing-attribute error. The safe `or { }`
      # lookup keeps the guard independent of whether any sibling declared
      # `repo.web`.
      webServices = config.repo.web.currentHost.services or { };
      gatusRoute =
        if webServices ? "gatus-admin" then
          webServices."gatus-admin"
        else
          throw "gatus: required canonical web-policy route 'repo.web.currentHost.services.\"gatus-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'";

      webAddress = gatusRoute.origin.host;
      webPort = gatusRoute.origin.port;

      mkEndpoint = serviceName: svc: {
        name = serviceName;
        url = svc.healthUrl;
        interval = "1m";
        conditions = [ "[STATUS] == ${toString svc.health.expectedStatus}" ];
      };

      endpoints = lib.mapAttrsToList mkEndpoint webServices;
    in
    {
      options.services.admin.gatus = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable admin-owned Gatus service wiring.";
        };

      };
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          services.gatus = {
            enable = true;
            openFirewall = false;
            settings = {
              web.address = webAddress;
              web.port = webPort;
              inherit endpoints;
              alerting.custom = {
                url = "http://127.0.0.1:5555/notify";
                method = "POST";
                headers = {
                  Content-Type = "application/json";
                };
                placeholders = {
                  ALERT_TRIGGERED_OR_RESOLVED = {
                    TRIGGERED = "warning";
                    RESOLVED = "info";
                  };
                };
                body = builtins.toJSON {
                  tier = "[ALERT_TRIGGERED_OR_RESOLVED]";
                  title = "Gatus: [ENDPOINT_NAME]";
                  type = "[ALERT_TRIGGERED_OR_RESOLVED]";
                  message = "[ALERT_DESCRIPTION]";
                  topic = "web";
                };
              };
            };
          };
        })
        ({
          # Selecting this aspect is the capability's top-level enablement.
          services.admin.gatus.enable = true;
        })
      ];
    };
}
