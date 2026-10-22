# Memos: listener and public URL from the canonical route; its OpenID provider lives in
# instance settings in Memos' own database.
_: {
  flake.modules.nixos.memos =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.memos;
      route = config.repo.web.catalog.memos or null;
      oidcClient = config.services.identity.oidc.clients.memos or null;
      providerName = "memos-idp-kanidm.json";
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      dataDir = "/srv/data/memos";
      # Upstream opens "<MEMOS_DATA>/memos_<MEMOS_MODE>.db" in WAL mode (store/db/sqlite),
      # so the live file and its WAL companions are excluded from the raw copy.
      dbName = "memos_${cfg.settings.MEMOS_MODE}.db";
      dbFile = "${dataDir}/${dbName}";
      exportDir = "${config.services.state-backups.stagingRoot}/memos";
    in
    {
      imports = [ ../backups/state-backups/_consumer.nix ];

      options.services.memos.secretFiles.oidc = secretHelpers.mkSecretFileOption "memos-oidc-secrets";

      config = lib.mkMerge [
        { services.memos.enable = true; }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = route != null;
              message = "services.memos: canonical web-policy route 'repo.web.catalog.memos' is missing; declare the memos route under its host in policy/web-services.nix.";
            }
            {
              assertion = oidcClient != null;
              message = "services.memos: identity client 'memos' is missing; declare it in policy/identity.json.";
            }
          ];

          sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
            memos_oidc_client_secret = {
              key = "memos/client_secret";
              path = "/run/secrets/memos.oidc_client_secret";
            };
          };

          # Memos reads providers only from /etc/secrets at startup. The shared directory stays
          # root-owned, so the unit gets a credential copy bound over it in its namespace.
          sops.templates.${providerName} = {
            restartUnits = [ "memos.service" ];
            content = builtins.toJSON {
              uid = "kanidm";
              name = "Kanidm";
              type = "OAUTH2";
              config.oauth2Config = {
                clientId = oidcClient.clientId;
                clientSecret = config.sops.placeholder.memos_oidc_client_secret;
                authUrl = oidcClient.authorizationUrl;
                tokenUrl = oidcClient.tokenUrl;
                userInfoUrl = oidcClient.userinfoUrl;
                scopes = [
                  "openid"
                  "profile"
                  "email"
                ];
                fieldMapping = {
                  identifier = "sub";
                  displayName = "name";
                  email = "email";
                  avatarUrl = "picture";
                };
              };
            };
          };

          systemd.services.memos = {
            # The provider template is rendered by sops, which the fleet's systemd
            # activation installs as its own unit, so the service orders after it.
            wants = [ "sops-install-secrets.service" ];
            after = [ "sops-install-secrets.service" ];
            serviceConfig = {
              LoadCredential = [ "${providerName}:${config.sops.templates.${providerName}.path}" ];
              # Literal path: %d is rejected in BindReadOnlyPaths. The credential
              # directory holds only the provider file, so this exposes nothing else.
              BindReadOnlyPaths = [ "/run/credentials/memos.service:/etc/secrets" ];
            };
          };

          # openFirewall stays unset: the loopback listener sits behind the edge,
          # and the upstream firewall branch reads an option the module never defines.
          services.memos = {
            inherit dataDir;
            settings = {
              MEMOS_MODE = "prod";
              MEMOS_ADDR = "127.0.0.1";
              MEMOS_PORT = route.upstreamPort;
              MEMOS_DATA = dataDir;
              MEMOS_DRIVER = "sqlite";
              MEMOS_INSTANCE_URL = route.publicUrl;
            };
          };

          # `-readonly` keeps a missing database from being created empty and then
          # adopted by Memos as its own state.
          services.state-backups.services.memos = {
            enable = true;
            mode = "export";
            paths = [ dataDir ];
            exclude = [
              dbFile
              "${dbFile}-wal"
              "${dbFile}-shm"
            ];
            exportPaths = [ "${exportDir}/${dbName}" ];
            prepareCommands = [
              "${pkgs.coreutils}/bin/mkdir -p ${exportDir}"
              "${pkgs.sqlite}/bin/sqlite3 -readonly ${dbFile} ${lib.escapeShellArg ".backup ${exportDir}/${dbName}"}"
            ];
            cleanupCommands = [ "${pkgs.coreutils}/bin/rm -rf ${exportDir}" ];
          };
        })
      ];
    };
}
