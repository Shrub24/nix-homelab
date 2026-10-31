# Homarr app bookmarks, converged from web policy through Homarr's HTTP API.
_: {
  flake.modules.nixos.homarr =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.homarr;
      route = config.repo.web.catalog.homarr or null;
      catalog = config.repo.web.catalog;

      apps = lib.filterAttrs (
        name: service:
        (service.category == "app" || service.category == "admin")
        && (service.publish or true)
        && service.publicHost != null
      ) catalog;

      iconSlugs = {
        paperless = "paperless-ngx";
        actual = "actual-budget";
        search = "degoog";
        admin-homepage = "homepage";
        ntfy-admin = "ntfy";
        termix-admin = "termix";
        vaultwarden-admin = "vaultwarden";
        webhook-admin = "webhook";
        beszel-admin = "beszel";
        gatus-admin = "gatus";
        syncthing-home-forge = "syncthing";
        syncthing-oci-melb-1 = "syncthing";
      };
      iconSlug = name: iconSlugs.${name} or name;

      titleCase =
        name:
        lib.concatMapStrings (
          word: lib.toUpper (builtins.substring 0 1 word) + builtins.substring 1 (-1) word
        ) (lib.splitString "-" name);

      desired = pkgs.writeText "homarr-apps.json" (
        builtins.toJSON {
          apps = lib.mapAttrsToList (name: service: {
            name = titleCase name;
            href = "https://${service.publicHost}";
            iconUrl = "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/${iconSlug name}.png";
            description = service.publicHost;
          }) apps;
        }
      );
    in
    {
      config = {
        sops.secrets.homarr_api_key = {
          key = "api_key";
          path = "/run/secrets/homarr.api_key";
          sopsFile = cfg.secretFiles.host;
        };

        # The API key is the one operator step: without it the unit converges nothing.
        systemd.services."homarr-apps" = {
          description = "Sync Homarr app bookmarks with the fleet web policy";
          wantedBy = [ "multi-user.target" ];
          wants = [
            "podman-homarr.service"
            "sops-install-secrets.service"
          ];
          after = [
            "podman-homarr.service"
            "sops-install-secrets.service"
          ];
          restartTriggers = [ desired ];
          unitConfig = {
            StartLimitIntervalSec = 300;
            StartLimitBurst = 5;
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = 15;
            Environment = [
              "HOMARR_BASE_URL=http://127.0.0.1:${toString route.upstreamPort}"
              "HOMARR_API_KEY_FILE=/run/secrets/homarr.api_key"
              "HOMARR_DESIRED_FILE=${desired}"
            ];
            ExecStart = "${pkgs.python3}/bin/python3 ${./homarr/reconcile.py}";
          };
        };

        services.notify.events."homarr-apps".failure = { };
      };
    };
}
