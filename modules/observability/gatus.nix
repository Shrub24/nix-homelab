# Gatus deployment aspect: selection imports the leaf and owns its enablement; the leaf reads only the
# canonical web policy and has no secrets or runtime paths.
_: {
  flake.modules.nixos.gatus =
    { lib, config, ... }:
    let
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      cfg = config.services.admin.gatus;

      webServices = config.repo.web.catalog or { };
      gatusRoute =
        webServices."gatus-admin"
          or (throw "gatus: required canonical web-policy route 'repo.web.catalog.\"gatus-admin\"' is missing for host '${
            config.networking.hostName or "?"
          }'");

      webAddress = "0.0.0.0";
      webPort = gatusRoute.upstreamPort;

      # Probes target the published URL, so an outage of either the edge or the origin shows.
      # Access answers an unauthenticated probe with a redirect, which says nothing about the
      # origin: a service token makes the probe a real one. The file arrives after the OpenTofu
      # apply, so its presence decides, and until then the gate counts as healthy.
      hasToken = cfg.secretFiles.accessToken != null && builtins.pathExists cfg.secretFiles.accessToken;
      healthyStatuses =
        svc:
        if (svc.access.requireCloudflareAccess or false) && !hasToken then
          [
            200
            302
            401
            403
          ]
        else
          [ svc.health.expectedStatus ];

      mkEndpoint =
        serviceName: svc:
        {
          name = serviceName;
          url = svc.publicUrl;
          interval = "1m";
          conditions = [
            (lib.concatMapStringsSep " || " (status: "[STATUS] == ${toString status}") (healthyStatuses svc))
          ];
        }
        // lib.optionalAttrs (hasToken && (svc.access.requireCloudflareAccess or false)) {
          # Only Access-gated routes need the token, and only they may receive it. Gatus
          # expands environment variables over its whole configuration, so it stays out of the store.
          headers = {
            "CF-Access-Client-Id" = "\${CF_ACCESS_CLIENT_ID}";
            "CF-Access-Client-Secret" = "\${CF_ACCESS_CLIENT_SECRET}";
          };
        };

      endpoints = lib.mapAttrsToList mkEndpoint (
        lib.filterAttrs (_: svc: svc.publicUrl != null) webServices
      );
    in
    {
      options.services.admin.gatus = {
        secretFiles.accessToken = secretHelpers.mkSecretFileOption "gatus-access-token-secrets";

      };
      config = {
        # A rendered secret file has to be owned by a resolvable account, and a dynamic one
        # has no name to own it.
        users.groups.gatus = lib.mkIf hasToken { };
        users.users.gatus = lib.mkIf hasToken {
          isSystemUser = true;
          group = "gatus";
        };

        sops.secrets = lib.mkIf hasToken {
          "gatus/cf_access_client_id" = {
            sopsFile = cfg.secretFiles.accessToken;
            key = "cf_access/client_id";
          };
          "gatus/cf_access_client_secret" = {
            sopsFile = cfg.secretFiles.accessToken;
            key = "cf_access/client_secret";
          };
        };

        sops.templates."gatus-access-token.env" = lib.mkIf hasToken {
          owner = "gatus";
          group = "gatus";
          mode = "0400";
          content = ''
            CF_ACCESS_CLIENT_ID=${config.sops.placeholder."gatus/cf_access_client_id"}
            CF_ACCESS_CLIENT_SECRET=${config.sops.placeholder."gatus/cf_access_client_secret"}
          '';
        };

        systemd.services.gatus.serviceConfig = lib.mkIf hasToken {
          DynamicUser = lib.mkForce false;
        };

        services.gatus = {
          enable = true;
          openFirewall = false;
          environmentFile = lib.mkIf hasToken config.sops.templates."gatus-access-token.env".path;
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
      };
    };
}
