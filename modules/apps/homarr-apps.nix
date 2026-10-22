# Homarr's app bookmarks, projected from web policy. Homarr has no declarative format,
# so a oneshot unit converges them through its HTTP API; boards stay the user's.
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

      # `category` separates what a person opens from machine endpoints; `publish`
      # separates a link from a placeholder for a withheld route.
      apps = lib.filterAttrs (
        name: service:
        (service.category == "app" || service.category == "admin")
        && (service.publish or true)
        && service.publicHost != null
      ) catalog;

      # Slugs diverge where upstream renamed or the route is named for its role.
      iconSlugs = {
        paperless = "paperless-ngx";
        actual = "actual-budget";
        search = "degoog";
        admin-homepage = "homepage";
        cockpit-oci-melb-1 = "cockpit";
        ntfy-admin = "ntfy";
        termix-admin = "termix";
        vaultwarden-admin = "vaultwarden";
        webhook-admin = "webhook";
        beszel-admin = "beszel";
        gatus-admin = "gatus";
        kanidm-admin = "kanidm";
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
      config = lib.mkIf cfg.enable {
        sops.secrets.homarr_api_key = {
          key = "api_key";
          path = "/run/secrets/homarr.api_key";
          sopsFile = cfg.secretFiles.host;
        };

        # The key is the one operator step (no headless login); until it exists the unit
        # logs why it did nothing.
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
          # The sync is a oneshot: a failure means it could not converge, which
          # is worth retrying a few times before it is reported.
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
