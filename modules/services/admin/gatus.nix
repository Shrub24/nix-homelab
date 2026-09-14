# Gatus monitoring composition (decoupled from the `applications.admin`
# namespace in decouple-identity-admin-capabilities 3.2): the policy origin,
# the catalog-derived endpoint sweep, and the alert transport come from the
# canonical web policy (`repo.web.currentHost.services`).
{
  lib,
  config,
  ...
}:
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

  config = lib.mkIf cfg.enable {
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
  };
}
