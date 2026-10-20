# GeoPulse location-history platform: PostgreSQL consumer registration, the
# native backend/frontend runtime and the secrets contract.
#
# Selection is enablement: the host supplies only the encrypted secret file path.
# The runtime owns its listeners, state directories and environment, and the
# front-end listener port is read from the private web-policy route so the
# declaration and the socket cannot drift.
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

      # The private route declares the loopback listener the edge dials, and the
      # port is stated once (policy/web-services.nix).
      catalog = config.repo.web.catalog or { };
      frontendRoute =
        catalog.geopulse
          or (throw "geopulse: required private web-policy route 'repo.web.catalog.\"geopulse\"' is missing for host '${
            config.networking.hostName or "?"
          }'");
      frontendPort = frontendRoute.upstreamPort;

      publicOriginMessage = "services.geopulse: the web-policy route 'geopulse' must publish a public identity (subdomain with a public exposure mode), because the OIDC callback, the issued-token issuer and the private bootstrap tunnel all present that origin.";

      # The browser-facing origin is the route's published identity, never a
      # literal, so a placement or subdomain change moves the callback with it.
      publicOrigin =
        let
          url = frontendRoute.publicUrl or null;
        in
        if url == null then throw publicOriginMessage else url;

      # The backend dials the host's own cluster on loopback: a host without one is
      # a configuration error, not a case to fall back from. The address is built
      # here so any path that forces it reports the requirement by name instead of
      # failing on a missing attribute.
      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      noClusterMessage = "services.geopulse: this host runs no PostgreSQL cluster; the backend dials the local cluster on loopback, so select the postgres aspect with an instance.";
      localPostgresUrl =
        if localPostgres == null then
          throw noClusterMessage
        else
          "jdbc:postgresql://127.0.0.1:${toString localPostgres.port}/geopulse";
      # The application's own backup feature shells out to a matching client, and
      # the running cluster's binaries are the only version-correct source, so this
      # belongs to the same requirement (and stays unforced without a cluster).
      postgresBinDirectory =
        if localPostgres == null then
          throw noClusterMessage
        else
          "${config.services.postgresql.finalPackage}/bin";

      # Two-step bootstrap: the host binds the path and the operator encrypts the
      # file afterwards. Projecting the registrations only while the file is really
      # there keeps an unbound path away from the path-typed options, and the
      # assertion below turns "selected without credentials" into a named failure.
      hasSecretFile = cfg.secretFiles.host != null && builtins.pathExists cfg.secretFiles.host;

      # Owner-scoped files under the sops secrets mount. It is traversable (0751)
      # while the values stay readable only by the service account; a rendered
      # template cannot be used here because its parent is 0750 root:root, which a
      # non-root service cannot traverse.
      secrets = {
        postgresPassword = "/run/secrets/geopulse/postgres-password";
        privateKey = "/run/secrets/geopulse/jwt-private-key.pem";
        publicKey = "/run/secrets/geopulse/jwt-public-key.pem";
        aiKey = "/run/secrets/geopulse/ai-encryption-key.txt";
      };

      # Both the substrate and the runtime read the database password from the same
      # file and key, so a rotation moves them together.
      secretEntries = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
        "geopulse/postgres-password" = {
          key = "roles/geopulse/password";
          path = secrets.postgresPassword;
          owner = "geopulse";
          group = "geopulse";
        };
        "geopulse/jwt-private-key" = {
          key = "jwt/private_key";
          path = secrets.privateKey;
          owner = "geopulse";
          group = "geopulse";
        };
        "geopulse/jwt-public-key" = {
          key = "jwt/public_key";
          path = secrets.publicKey;
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

      # Upstream's entrypoint wrote the same non-secret file and index.html loads
      # it from the web root.
      frontendConfig = pkgs.writeTextDir "config.js" ''
        window.VUE_APP_CONFIG = {
          API_BASE_URL: '/api',
        };
      '';

      # The front end reproduces upstream's nginx surface on the Caddy runtime the
      # fleet already ships. Handles are mutually exclusive and evaluated in order,
      # so the specific mappings come before the SPA catch-all.
      caddyfile = pkgs.writeText "Caddyfile" ''
        {
            # Nothing reconfigures this instance at runtime, and the edge's Caddy
            # already owns the default admin endpoint (localhost:2019).
            admin off
            # Plain HTTP on loopback: TLS terminates at the edge, the only client.
            auto_https off
            # The edge forwards the client address and the scheme it terminated; the
            # second hop keeps them only if loopback is trusted. Loopback alone, so
            # no other client can claim those headers.
            servers {
                trusted_proxies static 127.0.0.1
            }
        }

        # Hostless on purpose: a site address is also a request-host matcher, and
        # naming a loopback host here would reject the canonical public host the edge
        # forwards. `bind` is what keeps the socket loopback-only.
        http://:${toString frontendPort} {
            bind 127.0.0.1

            handle /config.js {
                header Cache-Control "no-store"
                root * ${frontendConfig}
                file_server
            }

            # The API surface. /mcp is mirrored for parity with upstream's nginx
            # config but no route publishes it (design GP-5).
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

            # Fixed tile proxy, mirroring upstream's rewrite
            # (/osm/tiles/a/19/299420/178830.png -> a.tile.openstreetmap.org/19/299420/178830.png).
            # nginx picked the a/b/c subdomain for browser parallelism; one fixed
            # upstream collapses that to nginx's own default `a`. This is the only
            # outbound mapping here, not a general-purpose proxy.
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

            # Content-hashed build assets are immutable; the shell, the PWA entry
            # points and every SPA route must stay fresh. Upstream split the same
            # way (a one-year regex location, no-store for `location /`), and the
            # split also keeps a missing asset from being cached as the shell.
            handle /assets/* {
                header Cache-Control "public, max-age=31536000, immutable"
                root * ${cfg.frontendPackage}
                file_server
            }

            # SPA fallback: /oidc/callback and every client-side route come back as
            # the app shell.
            handle {
                header Cache-Control "no-store"
                root * ${cfg.frontendPackage}
                try_files {path} /index.html
                file_server
            }

            # Upstream's nginx client_max_body_size; the application itself accepts
            # 2 GiB, and the listener is reachable through the edge only.
            request_body {
                max_size 200MB
            }
        }
      '';

      startBackend = pkgs.writeShellApplication {
        name = "geopulse-backend";
        text = ''
          # An operator who bootstrapped the file but left the keys empty would
          # otherwise only see the JVM's own stack traces.
          for file in ${secrets.postgresPassword} ${secrets.privateKey} ${secrets.publicKey} ${secrets.aiKey}; do
            if [ ! -s "$file" ]; then
              echo "geopulse: delivered secret '$file' is missing or empty; fill secrets/services/geopulse.yaml with 'sops edit' and redeploy" >&2
              exit 1
            fi
          done

          # The password is an environment value rather than a path (see the
          # shipped application.properties), so it is read from its owner-scoped
          # file at start and never enters the store or the command line.
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
      # Declaration-only contract: the registration below evaluates on a host
      # that does not run the mechanism.
      imports = [
        ../database/postgres/_consumer.nix
        ../backups/state-backups/_consumer.nix
      ];

      options.services.geopulse = {
        enable = lib.mkEnableOption "the GeoPulse location-history platform";

        secretFiles.host = secretHelpers.mkSecretFileOption "geopulse-host-secrets";

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
        # Selection is enablement.
        { services.geopulse.enable = true; }

        # The repository instantiates both outputs in a package set that admits
        # their BUSL-1.1 licence by name, so a host needs no unfree override and
        # both halves stay derived from one release.
        {
          services.geopulse.backendPackage = withSystem pkgs.stdenv.hostPlatform.system (
            { config, ... }: config.packages.geopulse-backend
          );
          services.geopulse.frontendPackage = withSystem pkgs.stdenv.hostPlatform.system (
            { config, ... }: config.packages.geopulse-frontend
          );
        }

        # Publication is a policy fact: `policy/web-services.nix` declares the route
        # with `publish = false` until the private bootstrap is finished, and
        # releasing it is that one edit.

        (lib.mkIf cfg.enable {
          assertions = [
            {
              # Intended as a two-step bootstrap, never as a silent absence: the
              # operator creates the encrypted file first, and a host that selects
              # the aspect before that fails here instead of starting without
              # credentials.
              assertion = hasSecretFile;
              message = "services.geopulse: secretFiles.host must be bound and be the encrypted secrets/services/geopulse.yaml; bootstrap it with 'just secrets bootstrap secrets/services/geopulse.yaml' before selecting the aspect.";
            }
            {
              assertion = localPostgres != null;
              message = noClusterMessage;
            }
            {
              # The public identity is a precondition, not a consequence of the
              # gate: the browser callback and the tunneled bootstrap both need it
              # while the route is still private.
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

          # The provider reads this same file and key to provision the role, so the
          # password has one authoritative source. PostGIS is a server-side package
          # from the instance's own extension set (so it always matches the cluster
          # version) and its SQL runs in the consumer's database as the substrate
          # administrator: Flyway's own `CREATE EXTENSION` runs as the application
          # role, which owns no extension privilege.
          services.postgres.consumers.geopulse = lib.mkIf hasSecretFile {
            database = "geopulse";
            role = "geopulse";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/geopulse/password";
            };
            # The backend is a native service on this host and dials loopback (the
            # cluster does not listen on IPv6), so no other source range is
            # allowed; the mechanism adds the role's catch-all reject after it.
            allowedCIDRs = [ "127.0.0.1/32" ];
            extensions = ps: [ ps.postgis ];
            setupSQL = ''
              CREATE EXTENSION IF NOT EXISTS postgis;
              CREATE EXTENSION IF NOT EXISTS postgis_topology;
            '';
          };

          # Mutable files only (design GP-6). The database itself is recovered from
          # the substrate's pg_dumpall export, never from this raw capture. Work
          # scratch and heap dumps are not state, so they stay out of the payload.
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

          sops.secrets = lib.mkIf hasSecretFile (
            builtins.mapAttrs (
              _: entry: entry // { restartUnits = [ "geopulse-backend.service" ]; }
            ) secretEntries
          );

          # A crash loop must reach `failed` to be visible: with the 10s restart
          # delay, the default start limit (5 starts in 10s) never trips, so the unit
          # sat in auto-restart and OnFailure never fired. Five starts in five minutes
          # now end in `failed`, which runs the notification handler.
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
            # No start without the role, the schema prerequisites, and the
            # delivered secret files.
            requires = [
              "postgresql-provision.service"
              "sops-install-secrets.service"
            ];
            unitConfig.RequiresMountsFor = [ cfg.dataDir ];
            environment = {
              QUARKUS_HTTP_HOST = "127.0.0.1";
              QUARKUS_HTTP_PORT = toString cfg.backendPort;

              GEOPULSE_POSTGRES_URL = localPostgresUrl;
              GEOPULSE_POSTGRES_USERNAME = "geopulse";
              GEOPULSE_JWT_PRIVATE_KEY_LOCATION = "file:${secrets.privateKey}";
              GEOPULSE_JWT_PUBLIC_KEY_LOCATION = "file:${secrets.publicKey}";
              GEOPULSE_AI_ENCRYPTION_KEY_LOCATION = "file:${secrets.aiKey}";

              # The browser reaches the app over HTTPS at the edge, and the private
              # bootstrap keeps that origin (design GP-4): no plain-HTTP cookie.
              GEOPULSE_AUTH_SECURE_COOKIES = "true";

              # Upstream defaults the issuer to http://localhost:8080 and builds
              # the OIDC callback from the public base URL, so both take the route's
              # published origin. The gate does not switch them off: the private
              # bootstrap presents that same HTTPS origin through a tunnel.
              GEOPULSE_PUBLIC_BASE_URL = publicOrigin;
              GEOPULSE_JWT_ISSUER = publicOrigin;

              # No broker and no AI configuration in this deployment (design
              # non-goals); AI stays off until a user enables it in their own
              # settings, which the environment cannot switch off for them.
              GEOPULSE_MQTT_ENABLED = "false";
              GEOPULSE_AI_LOGGING_ENABLED = "false";

              GEOPULSE_BACKUP_WORK_PATH = "${cfg.dataDir}/backups/.work";
              GEOPULSE_BACKUP_BINARY_DIRECTORY = postgresBinDirectory;
              # The maintenance connection only takes a cluster-wide advisory lock for
              # backup coordination, so it belongs in the database the role may reach.
              GEOPULSE_BACKUP_MAINTENANCE_DATABASE = "geopulse";
              GEOPULSE_IMPORT_DROP_FOLDER_PATH = "${cfg.dataDir}/import";
              GEOPULSE_IMPORT_TEMP_DIR = "${cfg.dataDir}/import/tmp";
              GEOPULSE_IMPORT_CHUNKS_DIR = "${cfg.dataDir}/import/chunks";
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
              # The store basename carries a hash prefix, so Caddy cannot infer the
              # adapter from the file name.
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
        })
      ];
    };
}
