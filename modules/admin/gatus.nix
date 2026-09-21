# Gatus deployment aspect: selection imports the leaf and owns its enablement;
# the leaf reads only the canonical web policy and has no secrets or runtime
# paths.
_: {
  flake.modules.nixos.gatus =
    { lib, config, ... }:
    let
      cfg = config.services.admin.gatus;

      webServices = config.repo.web.currentHost.services or { };
      gatusRoute =
        webServices."gatus-admin"
          or (throw "gatus: required canonical web-policy route 'repo.web.currentHost.services.\"gatus-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'");

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
        enable = lib.mkEnableOption "the Gatus service wiring";

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
        {
          services.admin.gatus.enable = true;
        }
      ];
    };
}
