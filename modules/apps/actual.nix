# Actual Budget: route, identity contract and OIDC secret are all read, never restated.
_: {
  flake.modules.nixos.actual =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.actual;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      route = config.repo.web.catalog.actual or null;
      oidcClient = config.services.identity.oidc.clients.actual;
      dataDir = "/srv/data/actual";
      exportDir = "${config.services.state-backups.stagingRoot}/actual";
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
        ../identity/_oidc.nix
      ];

      options.services.actual.secretFiles.oidc = secretHelpers.mkSecretFileOption "actual-oidc";

      config = {

        assertions = [
          {
            assertion = route != null;
            message = "services.actual: canonical web-policy route 'repo.web.catalog.actual' is missing; declare the actual route under its host in policy/web-services.nix.";
          }
        ];

        sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
          actual_oidc_client_secret = {
            key = "actual/client_secret";
            path = "/run/secrets/actual.oidc_client_secret";
            owner = "actual";
            group = "actual";
            # config.json is rendered once per start as this user, so a rotated secret needs a restart.
            restartUnits = [ "actual.service" ];
          };
        };

        users.users.actual = {
          description = "Actual Budget service user";
          isSystemUser = true;
          group = "actual";
        };
        users.groups.actual = { };

        systemd.tmpfiles.rules = [
          "d ${dataDir} 0700 actual actual - -"
        ];

        services.actual = {
          enable = true;
          user = "actual";
          group = "actual";

          settings = {
            inherit dataDir;
            hostname = "127.0.0.1";
            port = route.upstreamPort;
            loginMethod = "openid";
            allowedLoginMethods = [ "openid" ];
            openId = {
              discoveryURL = oidcClient.wellknownUrl;
              client_id = oidcClient.clientId;
              client_secret._secret = config.sops.secrets.actual_oidc_client_secret.path;
              # Upstream builds the callback as new URL('/openid/callback', server_hostname),
              # so this must be the full origin, not a host name.
              server_hostname = route.publicUrl;
            };
          };
        };

        # account.sqlite is live: exported through the online backup API, never copied raw.
        services.state-backups.services.actual = {
          enable = true;
          mode = "export";
          paths = [ cfg.settings.userFiles ];
          exportPaths = [ "${exportDir}/account.sqlite" ];
          prepareCommands = [
            "${pkgs.coreutils}/bin/mkdir -p ${exportDir}"
            "${pkgs.sqlite}/bin/sqlite3 -readonly ${cfg.settings.serverFiles}/account.sqlite ${lib.escapeShellArg ".backup ${exportDir}/account.sqlite"}"
          ];
          cleanupCommands = [ "${pkgs.coreutils}/bin/rm -rf ${exportDir}" ];
        };
      };
    };
}
