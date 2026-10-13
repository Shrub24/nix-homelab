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

        credentialsBootstrap = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Temporarily enable Homarr's local credentials provider for private
            first-administrator setup. This also selects the private Tailscale
            Serve origin for BASE_URL. Keep the public route withheld, create and
            promote the Kanidm-backed account, then disable this before release.
          '';
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

          # BASE_URL follows the browser's current private/public phase. Leave
          # NEXTAUTH_URL unset so Auth.js derives its OIDC callback from forwarded headers.
          sops.templates."homarr.environment" = {
            owner = "root";
            group = "root";
            mode = "0400";
            restartUnits = [ "podman-homarr.service" ];
            content = ''
              AUTH_SECRET=${config.sops.placeholder.homarr_auth_secret}
              SECRET_ENCRYPTION_KEY=${config.sops.placeholder.homarr_secret_encryption_key}
              BASE_URL=${
                if cfg.credentialsBootstrap then
                  "https://${route.endpoint.host}:${toString route.endpoint.port}"
                else
                  route.publicUrl
              }
              AUTH_PROVIDERS=${if cfg.credentialsBootstrap then "credentials,oidc" else "oidc"}
              AUTH_OIDC_ISSUER=${oidcClient.issuerUrl}
              AUTH_OIDC_CLIENT_ID=${oidcClient.clientId}
              AUTH_OIDC_CLIENT_NAME=Kanidm
              AUTH_OIDC_CLIENT_SECRET=${config.sops.placeholder.homarr_oidc_client_secret}
              AUTH_OIDC_SCOPE_OVERWRITE="openid email profile"
              AUTH_OIDC_GROUPS_LOCAL_MANAGEMENT=true
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
            };
          };

          systemd = {
            tmpfiles.rules = [
              "d ${dataDir} 0750 ${toString containerUid} ${toString containerGid} - -"
              "z ${dataDir} 0750 ${toString containerUid} ${toString containerGid} - -"
            ];

            services."podman-homarr" = {
              # The environment file is a sops template, which the fleet's systemd
              # activation installs before this unit starts. The container module
              # already orders on network-online.target.
              wants = [ "sops-install-secrets.service" ];
              after = [ "sops-install-secrets.service" ];
              unitConfig.RequiresMountsFor = [ dataDir ];
            };
          };

          # Keep the same SQLite CLI available to verify a staged restore.
          environment.systemPackages = [ pkgs.sqlite ];

          # Homarr uses SQLite. Export with SQLite's online backup API instead of
          # copying the live database file; exclude its entire directory so WAL or
          # journal sidecars can never enter the raw restic capture.
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
