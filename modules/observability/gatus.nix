# Gatus deployment aspect: selection imports the leaf and owns its enablement;
# the leaf reads only the canonical web policy and has no secrets or runtime
# paths.
_: {
  flake.modules.nixos.gatus =
    { lib, config, ... }:
    let
      cfg = config.services.admin.gatus;

      webServices = config.repo.web.catalog or { };
      gatusRoute =
        webServices."gatus-admin"
          or (throw "gatus: required canonical web-policy route 'repo.web.catalog.\"gatus-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'");

      webAddress = "0.0.0.0";
      webPort = gatusRoute.upstreamPort;

      # Probes target the published URL: the signal is "the route answers",
      # which is what an outage of either the edge or the origin breaks.
      # Cloudflare Access answers unauthenticated probes with a redirect, so an
      # Access-gated route counts as healthy when it reaches that gate.
      healthyStatuses =
        svc:
        if svc.access.requireCloudflareAccess or false then
          [
            200
            302
            401
            403
          ]
        else
          [ svc.health.expectedStatus ];

      mkEndpoint = serviceName: svc: {
        name = serviceName;
        url = svc.publicUrl;
        interval = "1m";
        conditions = [
          (lib.concatMapStringsSep " || " (status: "[STATUS] == ${toString status}") (healthyStatuses svc))
        ];
      };

      endpoints = lib.mapAttrsToList mkEndpoint (
        lib.filterAttrs (_: svc: svc.publicUrl != null) webServices
      );
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
                  severity = "[ALERT_TRIGGERED_OR_RESOLVED]";
                  title = "Gatus: [ENDPOINT_NAME]";
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
