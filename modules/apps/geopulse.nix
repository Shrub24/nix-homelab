# GeoPulse: PostgreSQL consumer, and two digest-pinned containers — the native backend and the
# nginx UI that serves the SPA and proxies the API.
{ ... }:
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
      readiness = import ../containers/_readiness.nix { inherit lib; };
      serviceNetwork = (import ../../policy/globals.nix).serviceNetwork;

      networkName = "geopulse";
      backendContainer = "geopulse-backend";
      uiContainer = "geopulse-ui";

      catalog = config.repo.web.catalog or { };
      frontendRoute =
        catalog.geopulse
          or (throw "geopulse: required web-policy route 'repo.web.catalog.\"geopulse\"' is missing for host '${
            config.networking.hostName or "?"
          }'");
      frontendPort = frontendRoute.upstreamPort;

      publicOriginMessage = "services.geopulse: the web-policy route 'geopulse' must publish a public identity (subdomain with a public exposure mode), because the OIDC callback and the issued-token issuer both present that origin.";
      browserOrigin =
        let
          url = frontendRoute.publicUrl or null;
        in
        if url == null then throw publicOriginMessage else url;

      hasLocalCluster = lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options;
      localPostgres = if hasLocalCluster then config.services.postgres.localEndpoint else null;
      noClusterMessage = "services.geopulse: this host runs no PostgreSQL cluster; select the postgres aspect with an instance.";
      # The backend is bridged, so it reaches the cluster's service-address listener, not loopback.
      localPostgresUrl =
        if localPostgres == null then
          throw noClusterMessage
        else
          "jdbc:postgresql://${serviceNetwork.hostName}:${toString localPostgres.port}/geopulse";

      hasSecretFile = cfg.secretFiles.host != null;
      oidcClient = config.services.identity.oidc.clients.geopulse or null;
      oidcEnabled = oidcClient != null && cfg.secretFiles.oidc != null;

      # Mounted into the backend at the path its `GEOPULSE_AI_ENCRYPTION_KEY_LOCATION` names.
      aiKeyFile = "/run/secrets/geopulse/ai-encryption-key.txt";

    in
    {
      # Declaration-only: evaluates on hosts without the mechanism.
      imports = [
        ../database/postgres/_consumer.nix
        ../backups/state-backups/_consumer.nix
        ../identity/_oidc.nix
      ];

      options.services.geopulse = {
        secretFiles.host = secretHelpers.mkSecretFileOptionWithDefault "geopulse-host-secrets" ../../secrets/services/geopulse.yaml;

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
          description = "Mutable GeoPulse state: database backup files and the import drop folder.";
        };
      };

      config = lib.mkMerge [
        {
          assertions = [
            {
              assertion = localPostgres != null;
              message = noClusterMessage;
            }
            {
              assertion = (frontendRoute.publicUrl or null) != null;
              message = publicOriginMessage;
            }
          ];

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0700 root root - -"
            "d ${cfg.dataDir}/backups 0700 root root - -"
            "d ${cfg.dataDir}/backups/.work 0700 root root - -"
            "d ${cfg.dataDir}/import 0700 root root - -"
            "d ${cfg.dataDir}/import/tmp 0700 root root - -"
            "d ${cfg.dataDir}/import/chunks 0700 root root - -"
          ];

          # The backend dials from its own bridge, so the ACL carries the container supernet as
          # well as loopback (a host-networked dialer would arrive as the service address).
          services.postgres.consumers.geopulse = lib.mkIf hasSecretFile {
            database = "geopulse";
            role = "geopulse";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/geopulse/password";
            };
            allowedCIDRs = [
              "127.0.0.1/32"
              serviceNetwork.containerSourceCIDR
            ];
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
            lib.optionalAttrs hasSecretFile {
              # The container runs as root so a 0400 root-owned mount is readable to it.
              "geopulse/ai-encryption-key" = {
                key = "ai/encryption_key";
                sopsFile = cfg.secretFiles.host;
                path = aiKeyFile;
                mode = "0400";
                owner = "root";
                group = "root";
              };
              "geopulse/postgres-password" = {
                key = "roles/geopulse/password";
                sopsFile = cfg.secretFiles.host;
                restartUnits = [ "podman-${backendContainer}.service" ];
              };
            }
            // lib.optionalAttrs oidcEnabled {
              # Keeps the client secret out of the container's declared environment.
              "geopulse/oidc-client-secret" = {
                key = "geopulse/client_secret";
                sopsFile = cfg.secretFiles.oidc;
                mode = "0400";
                owner = "root";
                group = "root";
                restartUnits = [ "podman-${backendContainer}.service" ];
              };
            };

          sops.templates =
            lib.optionalAttrs hasSecretFile {
              "geopulse.env" = {
                mode = "0400";
                restartUnits = [ "podman-${backendContainer}.service" ];
                content = ''
                  GEOPULSE_POSTGRES_PASSWORD=${config.sops.placeholder."geopulse/postgres-password"}
                '';
              };
            }
            // lib.optionalAttrs oidcEnabled {
              "geopulse.oidc.env" = {
                mode = "0400";
                restartUnits = [ "podman-${backendContainer}.service" ];
                content = ''
                  GEOPULSE_OIDC_PROVIDER_AUTHENTIK_CLIENT_SECRET=${
                    config.sops.placeholder."geopulse/oidc-client-secret"
                  }
                '';
              };
            };

          services.notify.events = {
            "podman-${backendContainer}" = {
              failure = { };
            };
            "podman-${uiContainer}" = {
              failure = { };
            };
          };

          systemd.services = {
            "podman-network-${networkName}" = {
              description = "Create Podman network ${networkName}";
              wantedBy = [ "multi-user.target" ];
              before = [
                "podman-${backendContainer}.service"
                "podman-${uiContainer}.service"
              ];
              after = [ "network.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${networkName} || ${pkgs.podman}/bin/podman network create ${networkName}'";
                ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${networkName} || true'";
              };
            };
          };

          virtualisation.oci-containers.containers.${backendContainer} = lib.mkMerge [
            (readiness.mkReadyProbe {
              cmd = "curl -fsS http://127.0.0.1:8080/api/v1/system/health";
              startPeriod = "10s";
            })
            {
              image = config.repo.ociImages.geopulseBackend;
              # Bridged with no published port: the UI reaches it by name on the shared network.
              extraOptions = [
                "--network=${networkName}"
                # Podman's DNS does not resolve the service name on this network.
                "--add-host=${serviceNetwork.hostName}:${serviceNetwork.address}"
                # The image's own user cannot read a 0400 root-owned key mount.
                "--user=0"
              ];
              environmentFiles = [
                config.sops.templates."geopulse.env".path
              ]
              ++ lib.optional oidcEnabled config.sops.templates."geopulse.oidc.env".path;
              volumes = [
                "${cfg.dataDir}/backups:/data/geopulse-backups"
                "${cfg.dataDir}/import:/data/geopulse-import"
                "${aiKeyFile}:/app/keys/ai-encryption-key.txt:ro"
              ];
              environment = {
                QUARKUS_HTTP_HOST = "0.0.0.0";
                GEOPULSE_POSTGRES_URL = localPostgresUrl;
                GEOPULSE_POSTGRES_USERNAME = "geopulse";
                GEOPULSE_AI_ENCRYPTION_KEY_LOCATION = "file:/app/keys/ai-encryption-key.txt";

                # A database that ran the retired source build records a repeatable migration the
                # image no longer ships; undone, Flyway's start-time validation crash-loops.
                QUARKUS_FLYWAY_IGNORE_MIGRATION_PATTERNS = "repeatable:missing";

                GEOPULSE_AUTH_SECURE_COOKIES = "true";
                GEOPULSE_PUBLIC_BASE_URL = browserOrigin;

                GEOPULSE_MQTT_ENABLED = "false";
                GEOPULSE_AI_LOGGING_ENABLED = "false";

                GEOPULSE_BACKUP_WORK_PATH = "/data/geopulse-backups/.work";
                # The image carries PostgreSQL 17 and 18 clients and picks the matching major.
                GEOPULSE_BACKUP_MAINTENANCE_DATABASE = "geopulse";
                GEOPULSE_IMPORT_DROP_FOLDER_PATH = "/data/geopulse-import";
                GEOPULSE_IMPORT_TEMP_DIR = "/data/geopulse-import/tmp";
                GEOPULSE_IMPORT_CHUNKS_DIR = "/data/geopulse-import/chunks";
              }
              // lib.optionalAttrs (cfg.adminEmail != null) {
                GEOPULSE_ADMIN_EMAIL = cfg.adminEmail;
              }
              // lib.optionalAttrs oidcEnabled {
                GEOPULSE_OIDC_ENABLED = "true";
                GEOPULSE_OIDC_CALLBACK_BASE_URL = browserOrigin;
                GEOPULSE_OIDC_AUTO_LINK_ACCOUNTS = "true";
                # Admission is the provider's group binding, so auto-creation adds no access.
                GEOPULSE_AUTH_OIDC_REGISTRATION_ENABLED = "true";

                GEOPULSE_OIDC_PROVIDER_AUTHENTIK_ENABLED = "true";
                GEOPULSE_OIDC_PROVIDER_AUTHENTIK_NAME = oidcClient.providerName;
                GEOPULSE_OIDC_PROVIDER_AUTHENTIK_CLIENT_ID = oidcClient.clientId;
                GEOPULSE_OIDC_PROVIDER_AUTHENTIK_DISCOVERY_URL = oidcClient.wellknownUrl;
              };
            }
          ];

          virtualisation.oci-containers.containers.${uiContainer} = lib.mkMerge [
            (readiness.mkReadyProbe { cmd = "wget -q --spider http://127.0.0.1:80/"; })
            {
              image = config.repo.ociImages.geopulseUi;
              # The image is nginx on Alpine, so the probe is busybox wget on its own port.
              extraOptions = [
                "--network=${networkName}"
              ];
              # The image's nginx renders config.js, proxies /api and /mcp, serves the SPA and
              # proxies OSM tiles; the route dials this loopback listener.
              ports = [ "127.0.0.1:${toString frontendPort}:80" ];
              environment = {
                GEOPULSE_BACKEND_URL = "http://${backendContainer}:8080";
                CLIENT_MAX_BODY_SIZE = "200M";
              };
              dependsOn = [ backendContainer ];
            }
          ];
          # Dials the cluster on the service address, so it starts after the cluster and its
          # provisioning are current; the budget is explicit because podman's unit sets it to 0.
          systemd.services."podman-${backendContainer}" = {
            wants = [ "network-online.target" ];
            after = [
              "podman-network-${networkName}.service"
              "postgresql.service"
              "postgresql-provision.service"
            ];
            requires = [
              "podman-network-${networkName}.service"
              "postgresql-provision.service"
            ];
            serviceConfig.TimeoutStartSec = lib.mkForce 300;
          };
          systemd.services."podman-${uiContainer}".serviceConfig.TimeoutStartSec = lib.mkForce 120;
        }
      ];
    };
}
