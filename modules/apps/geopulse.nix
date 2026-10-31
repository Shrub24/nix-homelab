# GeoPulse: PostgreSQL consumer, native backend and frontend, front-end port from the route.
{
  withSystem,
  ...
}:
{
  flake.modules.nixos.geopulse =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.geopulse;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };

      catalog = config.repo.web.catalog or { };
      frontendRoute =
        catalog.geopulse
          or (throw "geopulse: required private web-policy route 'repo.web.catalog.\"geopulse\"' is missing for host '${
            config.networking.hostName or "?"
          }'");
      frontendPort = frontendRoute.upstreamPort;

      publicOriginMessage = "services.geopulse: the web-policy route 'geopulse' must publish a public identity (subdomain with a public exposure mode), because the OIDC callback, the issued-token issuer and the private bootstrap tunnel all present that origin.";

      publicOrigin =
        let
          url = frontendRoute.publicUrl or null;
        in
        if url == null then throw publicOriginMessage else url;

      # Published only: on a withheld route the first OIDC login would target an origin the
      # edge does not serve.
      published = frontendRoute.publish == null || frontendRoute.publish;
      browserOrigin =
        if published then
          publicOrigin
        else
          "https://${frontendRoute.endpoint.host}:${toString frontendRoute.endpoint.port}";

      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      noClusterMessage = "services.geopulse: this host runs no PostgreSQL cluster; the backend dials the local cluster on loopback, so select the postgres aspect with an instance.";
      localPostgresUrl =
        if localPostgres == null then
          throw noClusterMessage
        else
          "jdbc:postgresql://127.0.0.1:${toString localPostgres.port}/geopulse";
      # The backup client must match the running cluster's binaries.
      postgresBinDirectory =
        if localPostgres == null then
          throw noClusterMessage
        else
          "${config.services.postgresql.finalPackage}/bin";

      # Projected only once the secret file exists, so an unbound path never reaches a path-typed option.
      hasSecretFile = cfg.secretFiles.host != null;

      # A database row of the same name shadows the environment's approved client, so the
      # admin UI's copy must not survive a redeploy.
      oidcClient = config.services.identity.oidc.clients.geopulse or null;
      hasOidcSecret = cfg.secretFiles.oidc != null && builtins.pathExists cfg.secretFiles.oidc;
      oidcEnabled = oidcClient != null && hasOidcSecret;

      # Owner-scoped: a rendered template sits under a 0750 root directory the service cannot traverse.
      secrets = {
        postgresPassword = "/run/secrets/geopulse/postgres-password";
        aiKey = "/run/secrets/geopulse/ai-encryption-key.txt";
      };

      # Substrate and runtime read the same file and key, so one rotation moves both.
      secretEntries = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
        "geopulse/postgres-password" = {
          key = "roles/geopulse/password";
          path = secrets.postgresPassword;
          owner = "geopulse";
          group = "geopulse";
        };
        "geopulse/ai-encryption-key" = {
          key = "ai/encryption_key";
          path = secrets.aiKey;
          owner = "geopulse";
          group = "geopulse";
        };
      };

      frontendConfig = pkgs.writeTextDir "config.js" ''
        window.VUE_APP_CONFIG = {
          API_BASE_URL: '/api/v1',
        };
      '';

      # Handles are mutually exclusive and evaluated in order, so specific mappings precede
      # the SPA catch-all.
      caddyfile = pkgs.writeText "Caddyfile" ''
        {
            # Caddy already owns the default admin endpoint on localhost:2019.
            admin off
            auto_https off
            # Trust forwarded headers from loopback only, so no other client can claim them.
            servers {
                trusted_proxies static 127.0.0.1
            }
        }

        # Hostless: a site address is also a host matcher, which would reject the forwarded public host.
        http://:${toString frontendPort} {
            bind 127.0.0.1

            handle /config.js {
                header Cache-Control "no-store"
                root * ${frontendConfig}
                file_server
            }

            # /mcp is mirrored for parity; no route publishes it.
            handle /api/* {
                reverse_proxy 127.0.0.1:${toString cfg.backendPort} {
                    header_up Host {host}
                }
            }

            handle /mcp* {
                reverse_proxy 127.0.0.1:${toString cfg.backendPort} {
                    header_up Host {host}
                }
            }

            # Fixed tile host: nginx's default `a` subdomain, with no general-purpose proxy.
            handle /osm/tiles/* {
                @tile path_regexp ^/osm/tiles/(a|b|c)/(.*)$
                rewrite @tile /{re.tile.2}
                header Cache-Control "public, max-age=2592000"
                reverse_proxy https://a.tile.openstreetmap.org {
                    header_up Host a.tile.openstreetmap.org
                    header_up User-Agent "GeoPulse/${cfg.frontendPackage.version}"
                    header_up -Cookie
                    header_up -Authorization
                }
            }

            # Hashed assets are immutable; the shell stays no-store so a missing asset is not
            # cached in its place.
            handle /assets/* {
                header Cache-Control "public, max-age=31536000, immutable"
                root * ${cfg.frontendPackage}
                file_server
            }

            handle {
                header Cache-Control "no-store"
                root * ${cfg.frontendPackage}
                try_files {path} /index.html
                file_server
            }

            # Matches the application's 2 GiB body limit.
            request_body {
                max_size 200MB
            }
        }
      '';

      startBackend = pkgs.writeShellApplication {
        name = "geopulse-backend";
        text = ''
          # Without this an empty key surfaces only as JVM stack traces.
          for file in ${secrets.postgresPassword} ${secrets.aiKey}; do
            if [ ! -s "$file" ]; then
              echo "geopulse: delivered secret '$file' is missing or empty; fill secrets/services/geopulse.yaml with 'sops edit' and redeploy" >&2
              exit 1
            fi
          done

          # Read from an owner-scoped file at start, so the value never enters the store or argv.
          export GEOPULSE_POSTGRES_PASSWORD
          GEOPULSE_POSTGRES_PASSWORD="$(cat ${secrets.postgresPassword})"

          exec ${pkgs.jdk25}/bin/java \
            -XX:+ExitOnOutOfMemoryError \
            -XX:HeapDumpPath=${cfg.dataDir}/dumps/ \
            -jar ${cfg.backendPackage}/quarkus-app/quarkus-run.jar
        '';
      };
    in
    {
      # Declaration-only: evaluates on hosts without the mechanism.
      imports = [
        ../database/postgres/_consumer.nix
        ../backups/state-backups/_consumer.nix
        ../identity/_oidc.nix
      ];

      options.services.geopulse = {
        secretFiles.host = secretHelpers.mkSecretFileOption "geopulse-host-secrets";

        secretFiles.oidc = secretHelpers.mkSecretFileOption "geopulse-oidc-secrets";

        adminEmail = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "owner@example.com";
          description = ''
            The account GeoPulse treats as administrator. When set, that address
            is promoted on start and on login, so the admin is a declared fact
            rather than whichever account registered first. Leave null to accept
            the upstream first-user bootstrap.
          '';
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/srv/data/geopulse";
          description = "Mutable GeoPulse state: database backup files, import drop folder and heap dumps.";
        };

        backendPort = lib.mkOption {
          type = lib.types.port;
          default = 8086;
          description = "Loopback listener of the GeoPulse backend. It is never published: the front end proxies to it on the same host.";
        };

        backendPackage = lib.mkOption {
          type = lib.types.package;
          description = "GeoPulse backend (Quarkus fast-jar) from the repository's package projection, injected per system.";
        };

        frontendPackage = lib.mkOption {
          type = lib.types.package;
          description = "GeoPulse static front end from the repository's package projection, injected per system.";
        };
      };

      config = lib.mkMerge [

        {
          services.geopulse.backendPackage = withSystem pkgs.stdenv.hostPlatform.system (
            { config, ... }: config.packages.geopulse-backend
          );
          services.geopulse.frontendPackage = withSystem pkgs.stdenv.hostPlatform.system (
            { config, ... }: config.packages.geopulse-frontend
          );
        }

        {

          assertions = [
            {
              assertion = localPostgres != null;
              message = noClusterMessage;
            }
            {
              # Required even while the route is private: the callback and the tunnel both use it.
              assertion = (frontendRoute.publicUrl or null) != null;
              message = publicOriginMessage;
            }
          ];

          users.groups.geopulse = { };
          users.users.geopulse = {
            isSystemUser = true;
            group = "geopulse";
            home = cfg.dataDir;
            description = "GeoPulse backend service account";
          };

          users.groups.geopulse-web = { };
          users.users.geopulse-web = {
            isSystemUser = true;
            group = "geopulse-web";
            home = "/var/empty";
            description = "GeoPulse static front-end service account";
          };

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0750 geopulse geopulse - -"
            "d ${cfg.dataDir}/backups 0750 geopulse geopulse - -"
            "d ${cfg.dataDir}/backups/.work 0750 geopulse geopulse - -"
            "d ${cfg.dataDir}/import 0750 geopulse geopulse - -"
            "d ${cfg.dataDir}/import/tmp 0750 geopulse geopulse - -"
            "d ${cfg.dataDir}/import/chunks 0750 geopulse geopulse - -"
            "d ${cfg.dataDir}/dumps 0750 geopulse geopulse - -"
          ];

          # Same file and key as the provider. PostGIS SQL runs as the substrate admin, because
          # Flyway's CREATE EXTENSION needs a privilege the app role lacks.
          services.postgres.consumers.geopulse = lib.mkIf hasSecretFile {
            database = "geopulse";
            role = "geopulse";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/geopulse/password";
            };
            # Loopback only: the cluster does not listen on IPv6, so the catch-all reject follows.
            allowedCIDRs = [ "127.0.0.1/32" ];
            extensions = ps: [ ps.postgis ];
            setupSQL = ''
              CREATE EXTENSION IF NOT EXISTS postgis;
              CREATE EXTENSION IF NOT EXISTS postgis_topology;
            '';
          };

          # Mutable files only: the database is recovered from the substrate's export.
          services.state-backups.services.geopulse = {
            enable = true;
            paths = [
              "${cfg.dataDir}/backups"
              "${cfg.dataDir}/import"
            ];
            exclude = [
              "${cfg.dataDir}/backups/.work"
              "${cfg.dataDir}/import/tmp"
              "${cfg.dataDir}/import/chunks"
            ];
          };

          sops.secrets =
            lib.optionalAttrs hasSecretFile (
              builtins.mapAttrs (
                _: entry: entry // { restartUnits = [ "geopulse-backend.service" ]; }
              ) secretEntries
            )
            // lib.optionalAttrs oidcEnabled {
              # Keeps the client secret out of the unit environment, which lands in the store.
              "geopulse/oidc-client-secret" = {
                key = "geopulse/client_secret";
                sopsFile = cfg.secretFiles.oidc;
                mode = "0400";
                owner = "geopulse";
                group = "geopulse";
                restartUnits = [ "geopulse-backend.service" ];
              };
            };

          sops.templates = lib.mkIf oidcEnabled {
            "geopulse.oidc.env" = {
              owner = "geopulse";
              group = "geopulse";
              mode = "0400";
              content = ''
                GEOPULSE_OIDC_PROVIDER_AUTHENTIK_CLIENT_SECRET=${
                  config.sops.placeholder."geopulse/oidc-client-secret"
                }
              '';
            };
          };

          # Five starts in five minutes reach `failed` and fire OnFailure; the default limit
          # never trips at a 10s restart delay.
          services.notify.events = {
            geopulse-backend.failure = { };
            geopulse-web.failure = { };
          };

          systemd.services.geopulse-backend = {
            description = "GeoPulse backend (location history and API)";
            wantedBy = [ "multi-user.target" ];
            after = [
              "network.target"
              "postgresql.service"
              "postgresql-provision.service"
              "sops-install-secrets.service"
            ];
            requires = [
              "postgresql-provision.service"
              "sops-install-secrets.service"
            ];
            unitConfig.RequiresMountsFor = [ cfg.dataDir ];
            environment = {
              QUARKUS_HTTP_HOST = "127.0.0.1";
              QUARKUS_HTTP_PORT = toString cfg.backendPort;
              # Quarkus enables localhost-only host validation itself on a loopback listener in prod,
              # answering 400 before routing to a request carrying the forwarded public Host.
              QUARKUS_HTTP_HOST_VALIDATION_REQUIRE_LOCALHOST = "false";

              GEOPULSE_POSTGRES_URL = localPostgresUrl;
              GEOPULSE_POSTGRES_USERNAME = "geopulse";
              GEOPULSE_AI_ENCRYPTION_KEY_LOCATION = "file:${secrets.aiKey}";

              GEOPULSE_AUTH_SECURE_COOKIES = "true";
              GEOPULSE_PUBLIC_BASE_URL = browserOrigin;

              GEOPULSE_MQTT_ENABLED = "false";
              GEOPULSE_AI_LOGGING_ENABLED = "false";

              GEOPULSE_BACKUP_WORK_PATH = "${cfg.dataDir}/backups/.work";
              GEOPULSE_BACKUP_BINARY_DIRECTORY = postgresBinDirectory;
              # Backup coordination takes an advisory lock, so it runs in a database the role reaches.
              GEOPULSE_BACKUP_MAINTENANCE_DATABASE = "geopulse";
              GEOPULSE_IMPORT_DROP_FOLDER_PATH = "${cfg.dataDir}/import";
              GEOPULSE_IMPORT_TEMP_DIR = "${cfg.dataDir}/import/tmp";
              GEOPULSE_IMPORT_CHUNKS_DIR = "${cfg.dataDir}/import/chunks";
            }
            // lib.optionalAttrs (cfg.adminEmail != null) {
              # 2.0 promotes this address on every login, so declare the administrator.
              GEOPULSE_ADMIN_EMAIL = cfg.adminEmail;
            }
            // lib.optionalAttrs oidcEnabled {
              GEOPULSE_OIDC_ENABLED = "true";
              GEOPULSE_OIDC_CALLBACK_BASE_URL = browserOrigin;
              GEOPULSE_OIDC_AUTO_LINK_ACCOUNTS = "true";

              GEOPULSE_OIDC_PROVIDER_AUTHENTIK_ENABLED = "true";
              GEOPULSE_OIDC_PROVIDER_AUTHENTIK_NAME = oidcClient.providerName;
              GEOPULSE_OIDC_PROVIDER_AUTHENTIK_CLIENT_ID = oidcClient.clientId;
              GEOPULSE_OIDC_PROVIDER_AUTHENTIK_DISCOVERY_URL = oidcClient.wellknownUrl;
            };
            unitConfig = {
              StartLimitIntervalSec = 300;
              StartLimitBurst = 5;
            };
            serviceConfig = {
              User = "geopulse";
              Group = "geopulse";
              ExecStart = "${startBackend}/bin/geopulse-backend";
              Restart = "on-failure";
              RestartSec = "10s";
              ReadWritePaths = [ cfg.dataDir ];
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              PrivateDevices = true;
              NoNewPrivileges = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
            }
            // lib.optionalAttrs oidcEnabled {
              EnvironmentFile = config.sops.templates."geopulse.oidc.env".path;
            };
          };

          systemd.services.geopulse-web = {
            description = "GeoPulse static front end (loopback listener)";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            unitConfig = {
              StartLimitIntervalSec = 300;
              StartLimitBurst = 5;
            };
            serviceConfig = {
              User = "geopulse-web";
              Group = "geopulse-web";
              # Caddy cannot infer the adapter from a hashed store basename.
              ExecStart = "${pkgs.caddy}/bin/caddy run --adapter caddyfile --config ${caddyfile}";
              Restart = "on-failure";
              RestartSec = "10s";
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
              PrivateDevices = true;
              NoNewPrivileges = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
            };
          };
        }
      ];
    };
}
