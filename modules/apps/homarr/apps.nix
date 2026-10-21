# Homarr's app bookmarks, projected from the fleet's web policy.
#
# An app is the part of Homarr that is tedious to keep true: a name, a URL and an
# icon that go stale whenever a route is renamed or a service moves. Boards are
# taste — a person assembles one in the UI from these apps — so this module owns
# the inventory of apps and nothing else.
#
# Homarr has no declarative configuration format, so the apps are converged
# through its HTTP API by a oneshot unit: Nix compiles the desired set from
# `policy/web-services.nix`, and `reconcile.py` creates what is missing and
# patches what drifted. Editing the policy is therefore the whole gesture.
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

      # Two distinctions decide the set. `category` separates what a person opens
      # from machine endpoints: an infrastructure route (a metrics store, an
      # ingest listener, the cache's write API) is something software dials, so it
      # earns no app. `publish` separates a link from a placeholder: the edge
      # serves nothing for a withheld route, so an app for it would be dead until
      # release.
      apps = lib.filterAttrs (
        name: service:
        (service.category == "app" || service.category == "admin")
        && (service.publish or true)
        && service.publicHost != null
      ) catalog;

      # dashboard-icons slugs differ from our service ids where the upstream
      # project renamed itself, or where our route is named for its role rather
      # than the product. A wrong slug costs a broken icon, not a broken app.
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

        # Reconciled with the API key an administrator mints once in the UI:
        # Homarr has no headless login, so the key is the one operator step. Until
        # it exists the unit logs why it did nothing, because an unminted key is a
        # prepared state rather than a fault.
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
            ExecStart = "${pkgs.python3}/bin/python3 ${./reconcile.py}";
          };
        };

        services.notify.events."homarr-apps".failure = { };
      };
    };
}
