# Actual Budget deployment aspect: selection supplies enablement; the listener
# port and public URL come from the canonical `actual` route, the OpenID client
# from the identity contract, and the client secret from the host-scoped OIDC
# source. A static account keeps the state path owned on its own mount.
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
      oidcClient = config.services.identity.oidc.clients.actual or null;
      dataDir = "/srv/data/actual";
      exportDir = "${config.services.state-backups.stagingRoot}/actual";
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
        ../identity/_oidc.nix
      ];

      options.services.actual.secretFiles.oidc = secretHelpers.mkSecretFileOption "actual-oidc";

      config = lib.mkMerge [
        { services.actual.enable = true; }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = route != null;
              message = "services.actual: canonical web-policy route 'repo.web.catalog.actual' is missing; declare the actual route under its host in policy/web-services.nix.";
            }
            {
              assertion = oidcClient != null;
              message = "services.actual: canonical OIDC client 'actual' is missing from services.identity.oidc.clients; check systems.oauth2.actual in policy/identity.json.";
            }
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
              file = cfg.secretFiles.oidc;
              feature = "services.actual";
              label = "secretFiles.oidc";
            })
          ];

          sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
            actual_oidc_client_secret = {
              key = "actual/client_secret";
              path = "/run/secrets/actual.oidc_client_secret";
              # The unit's preStart renders config.json as the service user.
              owner = "actual";
              group = "actual";
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
            user = "actual";
            group = "actual";

            settings = {
              inherit dataDir;
              hostname = "127.0.0.1";
              port = route.upstreamPort;
              loginMethod = "openid";
              # OpenID is upstream-preview, so password stays available.
              allowedLoginMethods = [
                "password"
                "openid"
              ];
              openId = {
                discoveryURL = oidcClient.wellknownUrl;
                client_id = oidcClient.clientId;
                client_secret._secret = config.sops.secrets.actual_oidc_client_secret.path;
                # Upstream builds the callback as new URL('/openid/callback', server_hostname),
                # so this is the full public origin, not a bare host name.
                server_hostname = route.publicUrl;
              };
            };
          };

          # account.sqlite is a live database: it is exported with sqlite's online
          # backup API, never copied raw. The per-budget user files are captured
          # as they are on disk.
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
        })
      ];
    };
}
