# Homarr is the user-facing dashboard; its boards and users are managed in the
# application, while this aspect owns the runtime, OIDC wiring and persistence.
_: {
  flake.modules.nixos.homarr =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.homarr;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      route = config.repo.web.catalog.homarr or null;
      oidcClient = config.services.identity.oidc.clients.homarr or null;
      # `publish` is a posture the module reads, not progress it tracks: withheld keeps the
      # private origin and credentials login, published is OIDC-only.
      published = if route == null then true else route.publish;

      dataDir = "/srv/data/homarr";
      containerPort = 7575;
      containerUid = 1001;
      containerGid = 1001;
      hostDbFile = "${dataDir}/db/db.sqlite";
      exportDir = "${config.services.state-backups.stagingRoot}/homarr";
      exportDbFile = "${exportDir}/db.sqlite";
    in
    {
      imports = [ ../backups/state-backups/_consumer.nix ];

      options.services.homarr = {
        enable = lib.mkEnableOption "Homarr user-facing service dashboard";

        secretFiles = {
          host = secretHelpers.mkSecretFileOption "homarr-host-secrets";
          oidc = secretHelpers.mkSecretFileOption "homarr-oidc-secrets";
        };

      };

      config = lib.mkMerge [
        # Selection is enablement.
        { services.homarr.enable = true; }

        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion = route != null;
              message = "services.homarr: canonical route 'repo.web.catalog.homarr' is missing; declare Homarr in policy/web-services.nix.";
            }
            {
              assertion = oidcClient != null;
              message = "services.homarr: canonical OIDC client 'homarr' is missing; check systems.oauth2.homarr in policy/identity.json.";
            }
            {
              assertion = route != null && route.exposureMode == "tailscale-serve";
              message = "services.homarr: route must use tailscale-serve so the private OIDC callback remains reachable.";
            }
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
              file = cfg.secretFiles.host;
              feature = "services.homarr";
              label = "secretFiles.host";
            })
            (secretHelpers.mkRequiredSecretAssertion {
              inherit (cfg) enable;
              file = cfg.secretFiles.oidc;
              feature = "services.homarr";
              label = "secretFiles.oidc";
            })
          ];

          # NEXTAUTH_URL stays unset so Auth.js derives the callback from forwarded headers.
          sops.templates."homarr.environment" = {
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "podman-homarr.service" ];
            content = ''
              AUTH_SECRET=${config.sops.placeholder.homarr_auth_secret}
              SECRET_ENCRYPTION_KEY=${config.sops.placeholder.homarr_secret_encryption_key}
              BASE_URL=${
                if published then
                  route.publicUrl
                else
                  "https://${route.endpoint.host}:${toString route.endpoint.port}"
              }
              # Only while withheld: they create the first administrator.
              AUTH_PROVIDERS=${if published then "oidc" else "credentials,oidc"}
              AUTH_OIDC_ISSUER=${oidcClient.issuerUrl}
              AUTH_OIDC_CLIENT_ID=${oidcClient.clientId}
              AUTH_OIDC_CLIENT_NAME=Kanidm
              AUTH_OIDC_CLIENT_SECRET=${config.sops.placeholder.homarr_oidc_client_secret}
              # Unquoted on purpose: the env-file parser keeps quotes in the value, and a quoted
              # list fails Kanidm's scope regex as invalid_scope. groups_name yields bare names.
              AUTH_OIDC_SCOPE_OVERWRITE=openid email profile groups_name
              AUTH_OIDC_GROUPS_ATTRIBUTE=groups
              # false: memberships follow the claim. Sync is authoritative both ways, so every
              # group an OIDC user keeps must exist in Kanidm under the same name.
              AUTH_OIDC_GROUPS_LOCAL_MANAGEMENT=false
              AUTH_OIDC_ENABLE_DANGEROUS_CREDENTIALS_LINKING=false
            '';
          };

          sops.secrets =
            secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              homarr_auth_secret = {
                key = "auth_secret";
                path = "/run/secrets/homarr.auth_secret";
              };
              homarr_secret_encryption_key = {
                key = "secret_encryption_key";
                path = "/run/secrets/homarr.secret_encryption_key";
              };
            }
            // secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
              homarr_oidc_client_secret = {
                key = "homarr/client_secret";
                path = "/run/secrets/homarr.oidc_client_secret";
              };
            };

          virtualisation = {
            podman.enable = true;

            oci-containers.containers.homarr = {
              autoStart = true;
              image = config.repo.ociImages.homarr;
              ports = [ "127.0.0.1:${toString route.upstreamPort}:${toString containerPort}" ];
              environment = {
                PUID = toString containerUid;
                PGID = toString containerGid;
              };
              environmentFiles = [ config.sops.templates."homarr.environment".path ];
              volumes = [ "${dataDir}:/appdata" ];
              # No HEALTHCHECK in the image; sdnotify=healthy makes After= mean "listening".
              # The probe dials containerPort inside the container, never the host-mapped port.
              podman.sdnotify = "healthy";
              extraOptions = [
                "--health-cmd=wget -q --spider http://127.0.0.1:${toString containerPort}/api/health/ready"
                "--health-interval=5s"
                "--health-timeout=3s"
                "--health-retries=10"
                "--health-start-period=5s"
              ];
            };
          };

          systemd = {
            tmpfiles.rules = [
              "d ${dataDir} 0750 ${toString containerUid} ${toString containerGid} - -"
              "z ${dataDir} 0750 ${toString containerUid} ${toString containerGid} - -"
            ];

            services."podman-homarr" = {
              # sops-install-secrets installs the template before this unit starts.
              wants = [ "sops-install-secrets.service" ];
              after = [ "sops-install-secrets.service" ];
              unitConfig.RequiresMountsFor = [ dataDir ];
              # The container module sets TimeoutStartSec=0 and readiness now blocks on the
              # healthcheck, so bound the wait: an app that never becomes healthy fails the
              # unit instead of hanging the switch.
              serviceConfig.TimeoutStartSec = lib.mkForce 120;
            };
          };

          # Keep the same SQLite CLI available to verify a staged restore.
          environment.systemPackages = [ pkgs.sqlite ];

          # SQLite: export through the online backup API, and exclude the directory so WAL
          # sidecars stay out of the raw capture.
          services.state-backups.services.homarr = {
            enable = true;
            mode = "export";
            paths = [ dataDir ];
            exclude = [ "${dataDir}/db" ];
            exportPaths = [ exportDbFile ];
            prepareCommands = [
              "${pkgs.coreutils}/bin/mkdir -p ${exportDir}"
              "${pkgs.sqlite}/bin/sqlite3 -readonly ${hostDbFile} ${lib.escapeShellArg ".backup ${exportDbFile}"}"
            ];
            cleanupCommands = [ "${pkgs.coreutils}/bin/rm -rf ${exportDir}" ];
          };
        })
      ];
    };
}
