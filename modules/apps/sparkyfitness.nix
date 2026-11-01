# SparkyFitness: upstream's frontend/backend pair on the fleet's PostgreSQL substrate. The
# frontend image keeps its nginx, which serves the SPA and proxies /api, /uploads, /mcp and the
# discovery routes to the backend on the same origin.
_: {
  flake.modules.nixos.sparkyfitness =
    {
      config,
      lib,
      options,
      pkgs,
      ...
    }:
    let
      cfg = config.services.sparkyfitness;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      readiness = import ../containers/_readiness.nix { inherit lib; };
      serviceNetwork = (import ../../policy/globals.nix).serviceNetwork;
      identityPolicy = import ../../policy/identity.nix;
      # The provider binds each application role to the first group it may hold that this client
      # admits, and the application compares its admin claim against that same name.
      adminGroups = identityPolicy.providers.${identityPolicy.provider}.appRoles.admin;
      admittedGroups = lib.attrNames identityPolicy.clients.sparkyfitness.access;
      grantedAdminGroup = lib.findFirst (group: lib.elem group admittedGroups) null adminGroups;
      noAdminGroupMessage = "services.sparkyfitness.adminGroup: client 'sparkyfitness' admits none of the provider's admin groups (${lib.concatStringsSep ", " adminGroups}); add one to its access in policy/identity.nix or set the option";

      networkName = "sparkyfitness";
      backendContainer = "sparkyfitness-server";
      frontendContainer = "sparkyfitness-frontend";
      backendPort = 3010;

      # Uploads are the durable files; `backup` is where the application writes its own dumps,
      # which the substrate's export already covers.
      dataDir = "/srv/data/sparkyfitness";
      uploadsDir = "${dataDir}/uploads";
      appBackupDir = "${dataDir}/backup";

      catalog = config.repo.web.catalog or { };
      route =
        catalog.sparkyfitness
          or (throw "services.sparkyfitness: the web-policy route 'sparkyfitness' is not declared; add it to policy/web-services.nix");

      oidcClient = config.services.identity.oidc.clients.sparkyfitness or null;

      # Probed through `options` so the read is total on a host without the mechanism.
      localPostgres =
        if lib.hasAttrByPath [ "services" "postgres" "localEndpoint" ] options then
          config.services.postgres.localEndpoint
        else
          null;
      noClusterMessage = "services.sparkyfitness: this host runs no PostgreSQL cluster; select the postgres aspect with an instance.";

      # The backend is bridged, so it reaches the cluster's service-address listener, not loopback.
      databaseHost = serviceNetwork.hostName;
      databasePort = if localPostgres == null then throw noClusterMessage else localPostgres.port;

      restartUnits = [ "podman-${backendContainer}.service" ];
    in
    {
      # Declaration-only: each evaluates on hosts without the mechanism.
      imports = [
        ../database/postgres/_consumer.nix
        ../backups/state-backups/_consumer.nix
        ../identity/_oidc.nix
      ];

      options.services.sparkyfitness = {
        secretFiles = {
          host = secretHelpers.mkSecretFileOptionWithDefault "sparkyfitness-host-secrets" ../../secrets/services/sparkyfitness.yaml;
          oidc = secretHelpers.mkSecretFileOption "sparkyfitness-oidc-secrets";
        };

        publicUrl = lib.mkOption {
          type = lib.types.str;
          default =
            if route.published or false then
              route.publicUrl
            else
              throw "services.sparkyfitness.publicUrl: the web-policy route 'sparkyfitness' is not published; set the origin the application is served from";
          description = "Origin the browser, the API and the OIDC callback share (SPARKY_FITNESS_FRONTEND_URL).";
        };

        adminGroup = lib.mkOption {
          type = lib.types.str;
          default = if grantedAdminGroup != null then grantedAdminGroup else throw noAdminGroupMessage;
          defaultText = lib.literalExpression "the provider's first admin group the client admits";
          description = "Identity-provider group whose members receive application administrator access.";
        };

        adminEmail = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "owner@example.com";
          description = ''
            Account that may reach the admin panel regardless of its identity-provider
            claims. Set it to the retained local administrator so break-glass access is
            administrative, not merely authenticated.
          '';
        };

        disablePasswordLogin = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Hide the application's own email/password login, leaving the identity provider as
            the sign-in path. Set false together with a deploy to sign in as the retained local
            administrator while the identity provider is unavailable, then revert.
          '';
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
              assertion = oidcClient != null;
              message = "services.sparkyfitness: canonical OIDC client 'sparkyfitness' is missing; check clients.sparkyfitness in policy/identity.nix.";
            }
            {
              # Hiding the local login while the route has OIDC off would leave no way in.
              assertion = !(cfg.disablePasswordLogin && !route.access.oidc.enabled);
              message = "services.sparkyfitness: disablePasswordLogin hides the local login while the route has access.oidc disabled, so nobody could sign in; enable one of them";
            }
          ];

          systemd.tmpfiles.rules = [
            "d ${dataDir} 0700 root root - -"
            "d ${uploadsDir} 0700 root root - -"
            "d ${appBackupDir} 0700 root root - -"
          ];

          # The backend dials from its own bridge, so the ACL carries the container supernet;
          # loopback is included for a host-networked dialer.
          services.postgres.consumers.sparkyfitness = {
            database = "sparkyfitness";
            role = "sparkyfitness";
            auth = "scram";
            password = {
              file = cfg.secretFiles.host;
              key = "roles/sparkyfitness/password";
            };
            allowedCIDRs = [
              "127.0.0.1/32"
              serviceNetwork.containerSourceCIDR
            ];
            additionalRoles.sparkyfitness_app.password = {
              file = cfg.secretFiles.host;
              key = "roles/sparkyfitness-app/password";
            };
            # PostgreSQL 15+ owns the public schema through the database owner; upstream's
            # external-database guide grants it explicitly.
            setupSQL = ''
              GRANT ALL ON SCHEMA public TO "sparkyfitness";
            '';
          };

          # The database is recovered from the substrate's export; only uploaded files are ours.
          services.state-backups.services.sparkyfitness = {
            enable = true;
            paths = [ uploadsDir ];
          };

          sops.secrets =
            secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              sparkyfitness_db_password = {
                key = "roles/sparkyfitness/password";
                path = "/run/secrets/sparkyfitness.db_password";
                inherit restartUnits;
              };
              sparkyfitness_app_db_password = {
                key = "roles/sparkyfitness-app/password";
                path = "/run/secrets/sparkyfitness.app_db_password";
                inherit restartUnits;
              };
              sparkyfitness_api_encryption_key = {
                key = "app/encryption_key";
                path = "/run/secrets/sparkyfitness.api_encryption_key";
                inherit restartUnits;
              };
              sparkyfitness_better_auth_secret = {
                key = "app/better_auth_secret";
                path = "/run/secrets/sparkyfitness.better_auth_secret";
                inherit restartUnits;
              };
            }
            // secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
              sparkyfitness_oidc_client_secret = {
                key = "sparkyfitness/client_secret";
                path = "/run/secrets/sparkyfitness.oidc_client_secret";
                inherit restartUnits;
              };
            };

          sops.templates."sparkyfitness.env" = {
            mode = "0400";
            restartUnits = restartUnits;
            content = ''
              SPARKY_FITNESS_DB_PASSWORD=${config.sops.placeholder.sparkyfitness_db_password}
              SPARKY_FITNESS_APP_DB_PASSWORD=${config.sops.placeholder.sparkyfitness_app_db_password}
              SPARKY_FITNESS_API_ENCRYPTION_KEY=${config.sops.placeholder.sparkyfitness_api_encryption_key}
              BETTER_AUTH_SECRET=${config.sops.placeholder.sparkyfitness_better_auth_secret}
              SPARKY_FITNESS_OIDC_CLIENT_SECRET=${config.sops.placeholder.sparkyfitness_oidc_client_secret}
            '';
          };

          services.notify.events = {
            "podman-${backendContainer}" = {
              failure = { };
            };
            "podman-${frontendContainer}" = {
              failure = { };
            };
          };

          systemd.services."podman-network-${networkName}" = {
            description = "Create Podman network ${networkName}";
            wantedBy = [ "multi-user.target" ];
            before = [
              "podman-${frontendContainer}.service"
              "podman-${backendContainer}.service"
            ];
            after = [ "network.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${networkName} || ${pkgs.podman}/bin/podman network create ${networkName}'";
              ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${networkName} || true'";
            };
          };

          virtualisation.oci-containers.containers.${backendContainer} = lib.mkMerge [
            (readiness.mkReadyProbe {
              cmd = "curl -fsS http://127.0.0.1:${toString backendPort}/api/health";
              startPeriod = "30s";
            })
            {
              image = config.repo.ociImages.sparkyFitnessServer;
              # Bridged with no published port: only the frontend reaches it, by name.
              extraOptions = [
                "--network=${networkName}"
                # Podman's DNS does not resolve the service name on this network.
                "--add-host=${databaseHost}:${serviceNetwork.address}"
              ];
              environmentFiles = [ config.sops.templates."sparkyfitness.env".path ];
              volumes = [
                "${uploadsDir}:/app/SparkyFitnessServer/uploads"
                "${appBackupDir}:/app/SparkyFitnessServer/backup"
              ];
              environment = {
                NODE_ENV = "production";
                SPARKY_FITNESS_SERVER_PORT = toString backendPort;
                SPARKY_FITNESS_FRONTEND_URL = cfg.publicUrl;
                SPARKY_FITNESS_LOG_LEVEL = "ERROR";

                SPARKY_FITNESS_DB_HOST = databaseHost;
                SPARKY_FITNESS_DB_PORT = toString databasePort;
                SPARKY_FITNESS_DB_NAME = "sparkyfitness";
                SPARKY_FITNESS_DB_USER = "sparkyfitness";
                SPARKY_FITNESS_APP_DB_USER = "sparkyfitness_app";

                SPARKY_FITNESS_OIDC_AUTH_ENABLED = lib.boolToString route.access.oidc.enabled;
                SPARKY_FITNESS_OIDC_PROVIDER_SLUG = identityPolicy.provider;
                SPARKY_FITNESS_OIDC_PROVIDER_NAME = oidcClient.providerName;
                SPARKY_FITNESS_OIDC_ISSUER_URL = oidcClient.issuerUrl;
                SPARKY_FITNESS_OIDC_CLIENT_ID = oidcClient.clientId;
                SPARKY_FITNESS_OIDC_SCOPE = builtins.concatStringsSep " " oidcClient.scopes;
                SPARKY_FITNESS_OIDC_AUTO_REGISTER = "true";
                SPARKY_FITNESS_OIDC_ADMIN_GROUP = cfg.adminGroup;

                SPARKY_FITNESS_DISABLE_EMAIL_LOGIN = lib.boolToString cfg.disablePasswordLogin;
                # Interactive MFA belongs to the identity provider; a local passkey is a second
                # sign-in path the fleet does not want beside it.
                SPARKY_FITNESS_DISABLE_PASSKEY_LOGIN = "true";
              }
              // lib.optionalAttrs (cfg.adminEmail != null) {
                SPARKY_FITNESS_ADMIN_EMAIL = cfg.adminEmail;
              };
            }
          ];

          virtualisation.oci-containers.containers.${frontendContainer} = {
            image = config.repo.ociImages.sparkyFitness;
            extraOptions = [ "--network=${networkName}" ];
            # The image's nginx serves the SPA and proxies the API, uploads, /mcp and the
            # discovery routes to the backend; the route dials this loopback listener.
            ports = [ "127.0.0.1:${toString route.upstreamPort}:80" ];
            environment = {
              SPARKY_FITNESS_FRONTEND_URL = cfg.publicUrl;
              SPARKY_FITNESS_SERVER_HOST = backendContainer;
              SPARKY_FITNESS_SERVER_PORT = toString backendPort;
            };
            dependsOn = [ backendContainer ];
          };
          # podman's unit sets the start timeout to 0, so an unpassed probe would hang activation.
          # The backend applies migrations on start, so it gets the longer budget.
          systemd.services."podman-${backendContainer}".serviceConfig.TimeoutStartSec = lib.mkForce 300;
        }
      ];
    };
}
