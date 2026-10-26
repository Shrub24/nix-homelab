# Memos: listener and public URL from the canonical route; its OpenID provider and its
# instance access policy are deployment-managed files, which Memos reads at startup.
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
      # Memos scans /etc/secrets for `memos-idp-<label>.json`; the label is the client id.
      providerFile = "memos-idp-${if oidcClient == null then "idp" else oidcClient.clientId}.json";
      # Deployment-managed instance settings. Memos merges these files over its stored settings
      # at every startup, so the instance posture is declared here rather than clicked in the UI.
      accessFile = "memos-instance-setting-access.json";
      generalFile = "memos-instance-setting-general.json";
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      dataDir = "/srv/data/memos";
      # Upstream opens "<MEMOS_DATA>/memos_<MEMOS_MODE>.db" in WAL mode (store/db/sqlite),
      # so the live file and its WAL companions are excluded from the raw copy.
      dbName = "memos_${cfg.settings.MEMOS_MODE}.db";
      dbFile = "${dataDir}/${dbName}";
      exportDir = "${config.services.state-backups.stagingRoot}/memos";
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
      ];

      options.services.memos.secretFiles.oidc = secretHelpers.mkSecretFileOption "memos-oidc-secrets";

      config = lib.mkMerge [

        {

          assertions = [
            {
              assertion = route != null;
              message = "services.memos: canonical web-policy route 'repo.web.catalog.memos' is missing; declare the memos route under its host in policy/web-services.nix.";
            }
            {
              assertion = oidcClient != null;
              message = "services.memos: identity client 'memos' is missing; declare it in policy/identity.nix.";
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
          sops.templates.${providerFile} = {
            restartUnits = [ "memos.service" ];
            content = builtins.toJSON {
              uid = oidcClient.clientId;
              name = oidcClient.providerName;
              type = "OAUTH2";
              config.oauth2Config = {
                clientId = oidcClient.clientId;
                clientSecret = config.sops.placeholder.memos_oidc_client_secret;
                authUrl = oidcClient.authorizationUrl;
                tokenUrl = oidcClient.tokenUrl;
                userInfoUrl = oidcClient.userinfoUrl;
                scopes = oidcClient.scopes;
                fieldMapping = {
                  identifier = "sub";
                  displayName = "name";
                  email = "email";
                  avatarUrl = "picture";
                };
              };
            };
          };

          # The instance is private: anonymous browsing is denied, while an explicit memo
          # share link keeps its own share policy. Only the admin role may fall back to a
          # password, which is the break-glass path if the provider is unreachable.
          sops.templates.${accessFile} = {
            restartUnits = [ "memos.service" ];
            content = builtins.toJSON {
              key = "ACCESS";
              accessSetting.accessMode = "INSTANCE_ACCESS_MODE_PRIVATE";
            };
          };

          sops.templates.${generalFile} = {
            restartUnits = [ "memos.service" ];
            content = builtins.toJSON {
              key = "GENERAL";
              generalSetting.disallowPasswordAuth = true;
            };
          };

          systemd.services.memos = {
            # The templates are rendered by sops, which the fleet's systemd activation
            # installs as its own unit, so the service orders after it.
            wants = [ "sops-install-secrets.service" ];
            after = [ "sops-install-secrets.service" ];
            serviceConfig = {
              LoadCredential = [
                "${providerFile}:${config.sops.templates.${providerFile}.path}"
                "${accessFile}:${config.sops.templates.${accessFile}.path}"
                "${generalFile}:${config.sops.templates.${generalFile}.path}"
              ];
              # Literal path: %d is rejected in BindReadOnlyPaths. The credential
              # directory holds only these three files, so this exposes nothing else.
              BindReadOnlyPaths = [ "/run/credentials/memos.service:/etc/secrets" ];
            };
          };

          # openFirewall stays unset: the loopback listener sits behind the edge,
          # and the upstream firewall branch reads an option the module never defines.
          services.memos = {
            inherit dataDir;
            enable = true;

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
        }
      ];
    };
}
