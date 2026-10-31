# BookOrbit on nixpkgs' native service. The shared PostgreSQL cluster provisions the
# database through its consumer registry. OIDC providers are configured in BookOrbit's own
# settings, so its OIDC client is declared in policy/identity.nix with no Nix secret.
_: {
  flake.modules.nixos.bookorbit =
    {
      config,
      lib,
      options,
      ...
    }:
    let
      cfg = config.services.bookorbit;
      route = config.repo.web.catalog.bookorbit or null;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      dataDir = "/srv/data/bookorbit";
      libraryRoot = "/srv/storage/media/books";
      # Names match pkgs/bookorbit-plugins; BookOrbit scans <APP_DATA_PATH>/plugins/indexers.
      pluginNames = [
        "libgen"
        "myanonamouse"
      ];
      plugins = config.repo.packages.bookorbit-plugins;
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
        ../database/postgres/_consumer.nix
      ];

      options.services.bookorbit.secretFiles.host =
        secretHelpers.mkSecretFileOption "bookorbit-host-secrets";

      config = lib.mkMerge [
        { services.bookorbit.enable = true; }

        {

          assertions = [
            {
              assertion = route != null;
              message = "services.bookorbit: canonical web-policy route 'repo.web.catalog.bookorbit' is missing; declare the bookorbit route in policy/web-services.nix.";
            }
            {
              assertion = localPostgres != null;
              message = "services.bookorbit: this host runs no PostgreSQL cluster; select the postgres aspect and declare services.postgres.instances.<name>.";
            }
          ];

          sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
            bookorbit_postgres_password = {
              key = "roles/bookorbit/password";
              path = "/run/secrets/bookorbit.postgres_password";
            };
            bookorbit_jwt_secret = {
              key = "app/jwt_secret";
              path = "/run/secrets/bookorbit.jwt_secret";
            };
            bookorbit_podcast_encryption_key = {
              key = "app/podcast_encryption_key";
              path = "/run/secrets/bookorbit.podcast_encryption_key";
            };
            bookorbit_setup_bootstrap_token = {
              key = "app/setup_bootstrap_token";
              path = "/run/secrets/bookorbit.setup_bootstrap_token";
            };
            bookorbit_book_request_encryption_key = {
              key = "app/book_request_encryption_key";
              path = "/run/secrets/bookorbit.book_request_encryption_key";
            };
            bookorbit_email_encryption_key = {
              key = "app/email_encryption_key";
              path = "/run/secrets/bookorbit.email_encryption_key";
            };
          };

          # The role password is interpolated into the connection string, so the generated
          # value must stay URL-safe.
          sops.templates."bookorbit.environment" = {
            owner = "root";
            group = "root";
            mode = "0400";
            content = ''
              DATABASE_URL=postgresql://bookorbit:${config.sops.placeholder.bookorbit_postgres_password}@127.0.0.1:${toString localPostgres.port}/bookorbit
              JWT_SECRET=${config.sops.placeholder.bookorbit_jwt_secret}
              PODCAST_ENCRYPTION_KEY=${config.sops.placeholder.bookorbit_podcast_encryption_key}
              SETUP_BOOTSTRAP_TOKEN=${config.sops.placeholder.bookorbit_setup_bootstrap_token}
              BOOK_REQUEST_ENCRYPTION_KEY=${config.sops.placeholder.bookorbit_book_request_encryption_key}
              EMAIL_ENCRYPTION_KEY=${config.sops.placeholder.bookorbit_email_encryption_key}
            '';
          };

          services.postgres.consumers.bookorbit = {
            database = "bookorbit";
            role = "bookorbit";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/bookorbit/password";
            };
            allowedCIDRs = [
              "127.0.0.1/32"
              "::1/128"
            ];
            extensions = ps: [ ps.pgvector ];
            setupSQL = ''
              CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
              CREATE EXTENSION IF NOT EXISTS pg_trgm;
              CREATE EXTENSION IF NOT EXISTS vector;
            '';
          };

          services.bookorbit = {
            # The consumer registration provisions the database, so the module's local cluster is off.
            createDatabaseLocally = false;
            environmentFile = config.sops.templates."bookorbit.environment".path;
            environment = {
              PORT = route.upstreamPort;
              APP_URL = route.publicUrl;
              APP_DATA_PATH = dataDir;
              LIBRARY_BROWSE_ROOT = libraryRoot;
            };
          };

          systemd = {
            tmpfiles.rules = [
              "d ${dataDir} 0750 bookorbit bookorbit - -"
              "d ${libraryRoot} 2775 bookorbit bookorbit - -"
              "d ${dataDir}/plugins 0750 bookorbit bookorbit - -"
              "d ${dataDir}/plugins/indexers 0750 bookorbit bookorbit - -"
            ]
            # tmpfiles refuses implicit root-owned parents under the bookorbit-owned data dir, so every
            # level is declared. Plugins are read-only from the store, so an in-app update cannot replace them.
            ++ lib.concatMap (name: [
              "d ${dataDir}/plugins/indexers/${name} 0750 bookorbit bookorbit - -"
              "L+ ${dataDir}/plugins/indexers/${name}/index.mjs - - - - ${plugins}/plugins/indexers/${name}/index.mjs"
            ]) pluginNames;

            services = {
              bookorbit = {
                unitConfig.RequiresMountsFor = [
                  dataDir
                  libraryRoot
                ];
                restartTriggers = [ plugins ];
              };
              bookorbit-migrate.unitConfig.RequiresMountsFor = [ dataDir ];
            };
          };

          services.state-backups.services.bookorbit = {
            enable = true;
            paths = [ dataDir ];
          };

          services.notify.events.bookorbit.failure = { };
        }
      ];
    };
}
