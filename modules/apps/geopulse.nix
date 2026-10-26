# GeoPulse: PostgreSQL consumer, native backend and frontend, and the secrets contract.
# The front-end port is read from the private web-policy route, so declaration and socket cannot drift.
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

      # Loopback listener the edge dials; the port is stated once in policy/web-services.nix.
      catalog = config.repo.web.catalog or { };
      frontendRoute =
        catalog.geopulse
          or (throw "geopulse: required private web-policy route 'repo.web.catalog.\"geopulse\"' is missing for host '${
            config.networking.hostName or "?"
          }'");
      frontendPort = frontendRoute.upstreamPort;

      publicOriginMessage = "services.geopulse: the web-policy route 'geopulse' must publish a public identity (subdomain with a public exposure mode), because the OIDC callback, the issued-token issuer and the private bootstrap tunnel all present that origin.";

      # Browser origin comes from the route's published identity, so a subdomain change moves the callback too.
      publicOrigin =
        let
          url = frontendRoute.publicUrl or null;
        in
        if url == null then throw publicOriginMessage else url;

      # Published only: a withheld route keeps the Tailscale Serve origin, or the first OIDC login targets a host the edge does not serve.
      published = frontendRoute.publish == null || frontendRoute.publish;
      browserOrigin =
        if published then
          publicOrigin
        else
          "https://${frontendRoute.endpoint.host}:${toString frontendRoute.endpoint.port}";

      # A host without a local cluster is a configuration error; the address is built lazily so the requirement is named.
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

      # Upstream reads its approved clients from the environment, but a database row of the same
      # name shadows it: the row is the admin UI's copy, not state.
      oidcClient = config.services.identity.oidc.clients.geopulse or null;
      hasOidcSecret = cfg.secretFiles.oidc != null && builtins.pathExists cfg.secretFiles.oidc;
      oidcEnabled = oidcClient != null && hasOidcSecret;

      # Owner-scoped file: a rendered template sits under a 0750 root directory a non-root service cannot traverse.
      secrets = {
        postgresPassword = "/run/secrets/geopulse/postgres-password";
        aiKey = "/run/secrets/geopulse/ai-encryption-key.txt";
      };

      # Substrate and runtime read the same file and key, so a rotation moves both.
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

      # Upstream's entrypoint wrote this file; index.html loads it from the web root.
      frontendConfig = pkgs.writeTextDir "config.js" ''
        window.VUE_APP_CONFIG = {
          API_BASE_URL: '/api/v1',
        };
      '';

      # Handles are mutually exclusive and evaluated in order, so specific mappings precede the SPA catch-all.
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

        # Hostless: a site address is also a host matcher, which would reject the public host the edge forwards.
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

            # Fixed upstream tile host: nginx's default `a` subdomain, without a general-purpose proxy.
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

            # Hashed assets are immutable; the shell and SPA routes stay no-store, so a missing asset is not cached as the shell.
            handle /assets/* {
                header Cache-Control "public, max-age=31536000, immutable"
                root * ${cfg.frontendPackage}
                file_server
            }

            # SPA fallback: client routes return the app shell.
            handle {
                header Cache-Control "no-store"
                root * ${cfg.frontendPackage}
                try_files {path} /index.html
                file_server
            }

            # Upstream's body limit; the application accepts 2 GiB.
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

          # Read from its owner-scoped file at start, so the value never enters the store or the command line.
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

        # BUSL-1.1 is admitted by name, so no unfree override is needed.
        {
          services.geopulse.backendPackage = withSystem pkgs.stdenv.hostPlatform.system (
            { config, ... }: config.packages.geopulse-backend
          );
          services.geopulse.frontendPackage = withSystem pkgs.stdenv.hostPlatform.system (
            { config, ... }: config.packages.geopulse-frontend
          );
        }

        # Publication is one policy edit: `publish = false` in policy/web-services.nix until bootstrap finishes.

        {

          assertions = [
            {
              assertion = localPostgres != null;
              message = noClusterMessage;
            }
            {
              # The public identity is required while the route is private: the callback and tunnel both use it.
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

          # Same file and key as the provider. PostGIS SQL runs as the substrate admin: Flyway's CREATE EXTENSION needs privileges the app role lacks.
          services.postgres.consumers.geopulse = lib.mkIf hasSecretFile {
            database = "geopulse";
            role = "geopulse";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/geopulse/password";
            };
            # Loopback only: the cluster does not listen on IPv6; the catch-all reject follows.
            allowedCIDRs = [ "127.0.0.1/32" ];
            extensions = ps: [ ps.postgis ];
            setupSQL = ''
              CREATE EXTENSION IF NOT EXISTS postgis;
              CREATE EXTENSION IF NOT EXISTS postgis_topology;
            '';
          };

          # Mutable files only: the database is recovered from the substrate's export, not this raw capture.
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
              # The client secret stays out of the unit's environment, which lands in the store.
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

          # Five starts in five minutes end in `failed`, which fires OnFailure; the default start limit never trips at a 10s delay.
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
            # No start without the role, schema prerequisites and secret files.
            requires = [
              "postgresql-provision.service"
              "sops-install-secrets.service"
            ];
            unitConfig.RequiresMountsFor = [ cfg.dataDir ];
            environment = {
              QUARKUS_HTTP_HOST = "127.0.0.1";
              QUARKUS_HTTP_PORT = toString cfg.backendPort;
              # Quarkus enables localhost-only host validation on its own when the listener binds a
              # loopback address in prod, so any request carrying the front's forwarded public Host is
              # answered 400 before routing. Nothing validates the Host here: the listener is loopback
              # only and the front, not the client, is the sole reachable peer.
              QUARKUS_HTTP_HOST_VALIDATION_REQUIRE_LOCALHOST = "false";

              GEOPULSE_POSTGRES_URL = localPostgresUrl;
              GEOPULSE_POSTGRES_USERNAME = "geopulse";
              GEOPULSE_AI_ENCRYPTION_KEY_LOCATION = "file:${secrets.aiKey}";

              # The app is reached over HTTPS at the edge, so no plain-HTTP cookie.
              GEOPULSE_AUTH_SECURE_COOKIES = "true";
              # Upstream defaults the issuer and callback to the public base URL; both take the route's published origin.
              GEOPULSE_PUBLIC_BASE_URL = browserOrigin;

              # AI stays off: the environment cannot switch it off for users who enable it.
              GEOPULSE_MQTT_ENABLED = "false";
              GEOPULSE_AI_LOGGING_ENABLED = "false";

              GEOPULSE_BACKUP_WORK_PATH = "${cfg.dataDir}/backups/.work";
              GEOPULSE_BACKUP_BINARY_DIRECTORY = postgresBinDirectory;
              # Backup coordination takes an advisory lock, so it runs in the database the role may reach.
              GEOPULSE_BACKUP_MAINTENANCE_DATABASE = "geopulse";
              GEOPULSE_IMPORT_DROP_FOLDER_PATH = "${cfg.dataDir}/import";
              GEOPULSE_IMPORT_TEMP_DIR = "${cfg.dataDir}/import/tmp";
              GEOPULSE_IMPORT_CHUNKS_DIR = "${cfg.dataDir}/import/chunks";
            }
            // lib.optionalAttrs (cfg.adminEmail != null) {
              # 2.0 promotes this address on every login, so the administrator is declared, not claimed by first login.
              GEOPULSE_ADMIN_EMAIL = cfg.adminEmail;
            }
            // lib.optionalAttrs oidcEnabled {
              GEOPULSE_OIDC_ENABLED = "true";
              GEOPULSE_OIDC_CALLBACK_BASE_URL = browserOrigin;
              # Address ownership is the provider's claim, so an existing account links on it.
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
