{
  lib,
  config,
  ...
}:
let
  appCfg = config.applications.admin;
  cfg = config.services.admin.homepage;
  homepageRoute = appCfg.policyServices."admin-homepage";
  listenPort = homepageRoute.origin.port;
  secretHelpers = import ../../../../lib/secrets.nix { inherit lib; };

  homepageData = import ./data.nix {
    inherit config;
    policyServices = appCfg.policyServices;
  };
in
{
  options.services.admin.homepage.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable admin-owned Homepage Dashboard wiring.";
  };

  options.services.admin.homepage.secretFiles.host =
    secretHelpers.mkSecretFileOption "homepage-host-secrets";

  config = lib.mkIf (appCfg.enable && cfg.enable) {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFiles.host;
        feature = "services.admin.homepage";
        label = "secretFiles.host";
      })
    ];

    sops.templates."homepage-auth.env" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        HOMEPAGE_VAR_TAILSCALE_DEVICEID=${config.sops.placeholder.homepage_tailscale_device_id}
        HOMEPAGE_VAR_TAILSCALE_API_KEY=${config.sops.placeholder.homepage_tailscale_api_key}
        HOMEPAGE_VAR_NAVIDROME_USER=${config.sops.placeholder.homepage_navidrome_user}
        HOMEPAGE_VAR_NAVIDROME_TOKEN=${config.sops.placeholder.homepage_navidrome_token}
        HOMEPAGE_VAR_NAVIDROME_SALT=${config.sops.placeholder.homepage_navidrome_salt}
        HOMEPAGE_VAR_SLSKD_KEY=${config.sops.placeholder.homepage_slskd_key}
        HOMEPAGE_VAR_BESZEL_USER=${config.sops.placeholder.homepage_beszel_username}
        HOMEPAGE_VAR_BESZEL_PASSWORD=${config.sops.placeholder.homepage_beszel_password}
      '';
    };

    sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
      homepage_tailscale_device_id = {
        key = "homepage/tailscale/device_id";
        path = "/run/secrets/homepage.tailscale.device_id";
        owner = "root";
        group = "root";
      };
      homepage_tailscale_api_key = {
        key = "homepage/tailscale/api_key";
        path = "/run/secrets/homepage.tailscale.api_key";
        owner = "root";
        group = "root";
      };
      homepage_navidrome_user = {
        key = "homepage/navidrome/user";
        path = "/run/secrets/homepage.navidrome.user";
        owner = "root";
        group = "root";
      };
      homepage_navidrome_token = {
        key = "homepage/navidrome/token";
        path = "/run/secrets/homepage.navidrome.token";
        owner = "root";
        group = "root";
      };
      homepage_navidrome_salt = {
        key = "homepage/navidrome/salt";
        path = "/run/secrets/homepage.navidrome.salt";
        owner = "root";
        group = "root";
      };
      homepage_slskd_key = {
        key = "homepage/slskd/key";
        path = "/run/secrets/homepage.slskd.key";
        owner = "root";
        group = "root";
      };
      homepage_beszel_username = {
        key = "homepage/beszel/username";
        path = "/run/secrets/homepage.beszel.username";
        owner = "root";
        group = "root";
      };
      homepage_beszel_password = {
        key = "homepage/beszel/password";
        path = "/run/secrets/homepage.beszel.password";
        owner = "root";
        group = "root";
      };
    };

    services.homepage-dashboard = {
      enable = true;
      openFirewall = false;
      inherit listenPort;
      allowedHosts = "localhost:${toString listenPort},127.0.0.1:${toString listenPort},${homepageRoute.publicHost}";
      environmentFiles = [
        config.sops.templates."homepage-auth.env".path
      ];
      inherit (homepageData)
        settings
        widgets
        services
        bookmarks
        ;
    };
  };
}
