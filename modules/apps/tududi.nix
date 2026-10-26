# tududi: image from policy, port and origin from the canonical route, OpenID from the
# identity contract. Loopback only, so the edge reaches it through `direct`.
_: {
  flake.modules.nixos.tududi =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.tududi;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      route = config.repo.web.catalog.tududi or null;
      oidcClient = config.services.identity.oidc.clients.tududi or null;

      # Upstream's entrypoint drops to uid/gid 1001 because the image declares no
      # USER, so the mounted state must be owned by that identity.
      dataDir = "/srv/data/tududi";
      containerPort = 3002;
      # The image defaults DB_FILE to the same path; it is set explicitly so the
      # container, the mount and the backup export share one definition.
      dbName = "production.sqlite3";
      containerDbFile = "/app/db/${dbName}";
      hostDbFile = "${dataDir}/db/${dbName}";
      exportDir = "${config.services.state-backups.stagingRoot}/tududi";
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
      ];

      options.services.tududi = {

        secretFiles = {
          host = secretHelpers.mkSecretFileOption "tududi-host-secrets";
          oidc = secretHelpers.mkSecretFileOption "tududi-oidc-secrets";
        };
      };

      config = lib.mkMerge [
        # Selection is enablement.

        {

          assertions = [
            {
              assertion = route != null;
              message = "services.tududi: canonical web-policy route 'repo.web.catalog.tududi' is missing; declare the tududi route under its host in policy/web-services.nix.";
            }
            {
              assertion = oidcClient != null;
              message = "services.tududi: canonical OIDC client 'tududi' is missing from services.identity.oidc.clients; check clients.tududi in policy/identity.nix.";
            }
          ];

          sops.templates."tududi.environment" = {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              TUDUDI_SESSION_SECRET=${config.sops.placeholder.tududi_session_secret}
              TUDUDI_USER_PASSWORD=${config.sops.placeholder.tududi_admin_password}
              OIDC_CLIENT_SECRET=${config.sops.placeholder.tududi_oidc_client_secret}
              TUDUDI_USER_EMAIL=${config.sops.placeholder.tududi_admin_email}
            '';
          };

          sops.secrets =
            secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              tududi_session_secret = {
                key = "tududi/session_secret";
                path = "/run/secrets/tududi.session_secret";
              };
              tududi_admin_email = {
                key = "tududi/admin_email";
                path = "/run/secrets/tududi.admin_email";
              };
              tududi_admin_password = {
                key = "tududi/admin_password";
                path = "/run/secrets/tududi.admin_password";
              };
            }
            // secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
              tududi_oidc_client_secret = {
                key = "tududi/client_secret";
                path = "/run/secrets/tududi.oidc_client_secret";
              };
            };

          virtualisation = {
            podman.enable = true;

            oci-containers.containers.tududi = {
              autoStart = true;
              image = config.repo.ociImages.tududi;
              # Loopback publish: the socket stays edge-local, so the route is `direct`.
              ports = [ "127.0.0.1:${toString route.upstreamPort}:${toString containerPort}" ];
              environment = {
                PORT = toString containerPort;
                DB_FILE = containerDbFile;
                TUDUDI_UPLOAD_PATH = "/app/uploads";
                TUDUDI_BACKUP_PATH = "/app/backups";
                BASE_URL = route.publicUrl;
                TUDUDI_ALLOWED_ORIGINS = route.publicUrl;
                # The only hop in front is the edge's proxy on this host.
                TUDUDI_TRUST_PROXY = "true";
                OIDC_ENABLED = "true";
                OIDC_PROVIDER_NAME = oidcClient.providerName;
                # The slug is the client id and forms its own callback path.
                OIDC_PROVIDER_SLUG = oidcClient.clientId;
                OIDC_ISSUER_URL = oidcClient.issuerUrl;
                OIDC_CLIENT_ID = oidcClient.clientId;
                OIDC_SCOPE = builtins.concatStringsSep " " oidcClient.scopes;
              };
              environmentFiles = [ config.sops.templates."tududi.environment".path ];
              volumes = [
                "${dataDir}/db:/app/db"
                "${dataDir}/uploads:/app/uploads"
                "${dataDir}/backups:/app/backups"
              ];
            };
          };

          systemd = {
            tmpfiles.rules = [
              "d ${dataDir} 0750 1001 1001 - -"
              "z ${dataDir} 0750 1001 1001 - -"
              "d ${dataDir}/db 0750 1001 1001 - -"
              "z ${dataDir}/db 0750 1001 1001 - -"
              "d ${dataDir}/uploads 0750 1001 1001 - -"
              "z ${dataDir}/uploads 0750 1001 1001 - -"
              "d ${dataDir}/backups 0750 1001 1001 - -"
              "z ${dataDir}/backups 0750 1001 1001 - -"
            ];

            services."podman-tududi" = {
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              # The restart budget is the foundation's per-container default.
              unitConfig.RequiresMountsFor = [ dataDir ];
            };
          };

          # WAL mode, so the database is exported through sqlite3's backup API; uploads are static
          # and captured as they stand. `-readonly` stops a missing database being created empty.
          services.state-backups.services.tududi = {
            enable = true;
            mode = "export";
            paths = [
              "${dataDir}/uploads"
              "${dataDir}/backups"
            ];
            exportPaths = [ "${exportDir}/${dbName}" ];
            prepareCommands = [
              "${pkgs.coreutils}/bin/mkdir -p ${exportDir}"
              "${pkgs.sqlite}/bin/sqlite3 -readonly ${hostDbFile} ${lib.escapeShellArg ".backup ${exportDir}/${dbName}"}"
            ];
            cleanupCommands = [ "${pkgs.coreutils}/bin/rm -rf ${exportDir}" ];
          };
        }
      ];
    };
}
