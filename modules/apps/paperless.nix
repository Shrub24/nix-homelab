# Paperless runtime sibling of the `paperless` aspect: deferredModule values
# merge across sibling files, so the host selects one aspect name.
{ inputs, ... }:
{
  flake.modules.nixos.paperless =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.paperless;
      secretHelpers = import ../../lib/secrets.nix { inherit lib; };
      repoPackages = config.repo.packages;
      oidcEnabled = cfg.oidc.enable;
      # This application's canonical client record is the single source for its
      # issuer endpoints; the host supplies enablement and credentials only.
      oidcClient = config.services.identity.oidc.clients.paperless or null;
      socialAccountProvidersJson = builtins.toJSON {
        openid_connect = {
          # Scopes and label come from the client contract, not the application.
          SCOPE = if oidcClient == null then [ ] else oidcClient.scopes;
          OAUTH_PKCE_ENABLED = true;
          # The provider gates login on a verified address, so a same-email link to an account
          # that predates it is trusted rather than refused as a duplicate.
          VERIFIED_EMAIL = true;
          EMAIL_AUTHENTICATION = true;
          APPS = [
            {
              provider_id = if oidcClient == null then "" else oidcClient.clientId;
              name = if oidcClient == null then "" else oidcClient.providerName;
              client_id = cfg.oidc.clientId;
              secret = config.sops.placeholder.paperless_oidc_client_secret;
              settings = {
                server_url = cfg.oidc.wellknownUrl;
              };
            }
          ];
        };
      };
      socialAccountProvidersEnv =
        builtins.replaceStrings [ "\\" "\"" "\n" ] [ "\\\\" "\\\"" "" ]
          socialAccountProvidersJson;

      postConsumeScript = pkgs.writeShellScriptBin "paperless-post-consume" ''
        DOCUMENT_TITLE="''${DOCUMENT_TITLE:-}"
        if [ -z "$DOCUMENT_TITLE" ]; then
          DOCUMENT_TITLE="''${DOCUMENT_FILE_NAME:-Unknown}"
        fi

        echo "New document: $DOCUMENT_TITLE" | ${repoPackages.notify}/bin/notify send info "Paperless" --topic services || true
      '';

      groupSeedScript = pkgs.writeText "paperless-group-seed.py" ''
        import os, sys, json

        os.environ.setdefault("DJANGO_SETTINGS_MODULE", "paperless.settings")
        import django
        django.setup()

        from django.contrib.auth.models import Group
        social_groups = json.loads("""${builtins.toJSON cfg.socialGroups}""")
        for name in social_groups:
            group, created = Group.objects.get_or_create(name=name)
            print(f"{'Created' if created else 'Exists'} group: {name}")
      '';
    in
    {
      imports = [
        ../backups/state-backups/_consumer.nix
        ../identity/_oidc.nix
      ];
      options.services.paperless = {
        dataRoot = lib.mkOption {
          type = lib.types.str;
          default = "/srv/data";
          description = "Top-level data root for Paperless dirs (data, media, consumption, paperless-gpt, docling).";
        };

        secretFiles.host = secretHelpers.mkSecretFileOption "paperless-host-secrets";

        secretFiles.oidc = secretHelpers.mkSecretFileOption "paperless-oidc-secrets";

        oidc = {
          enable = lib.mkEnableOption "OIDC login for Paperless";

          wellknownUrl = lib.mkOption {
            type = lib.types.str;
            default = if oidcClient == null then "" else oidcClient.wellknownUrl;
            defaultText = lib.literalExpression "services.identity.oidc.clients.paperless.wellknownUrl";
            description = "OIDC provider .well-known/openid-configuration URL, defaulted from the canonical client record.";
          };

          clientId = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = if oidcClient == null then null else oidcClient.clientId;
            defaultText = lib.literalExpression "services.identity.oidc.clients.paperless.clientId";
            description = "OIDC client ID registered with the identity provider, defaulted from the canonical client record.";
          };
        };

        socialGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "service-admins"
            "users"
          ];
          description = "Django groups to pre-seed for OIDC sync. Provider groups matching these names have membership synced.";
        };
      };

      config = lib.mkMerge [
        # Base package from the pinned revision; the nixpkgs module's own override (checks off)
        # still applies to it, which is what the running 3.3.1 generation was built from.
        {
          nixpkgs.overlays = [
            (_final: prev: {
              paperless-ngx =
                inputs.nixpkgs-paperless.legacyPackages.${prev.stdenv.hostPlatform.system}.paperless-ngx;
            })
          ];
        }
        # Selection is enablement: the aspect supplies the leaf's enable flag.
        { services.paperless.enable = true; }

        {

          # The post-consume hook is the one non-root notify caller here, so it joins the daemon's
          # group; services.notify.cliGroup stays null because access is per caller.
          users.users.paperless.extraGroups = lib.mkAfter (
            lib.optionals (config.users.groups ? notify) [ "notify" ]
          );

          assertions = [
            {
              assertion = !oidcEnabled || oidcClient != null;
              message = "services.paperless.oidc: canonical OIDC client 'paperless' is missing from services.identity.oidc.clients; check clients.paperless in policy/identity.nix and the identity provider's published route.";
            }
            {
              assertion = !oidcEnabled || cfg.oidc.clientId != null;
              message = "services.paperless.oidc.clientId must be set when OIDC is enabled.";
            }
            {
              assertion = !oidcEnabled || cfg.oidc.wellknownUrl != "";
              message = "services.paperless.oidc.wellknownUrl must be set when OIDC is enabled.";
            }
            {
              assertion = !oidcEnabled || cfg.secretFiles.oidc != null;
              message = "services.paperless.secretFiles.oidc must be set when OIDC is enabled (wellknownUrl and clientId are configured).";
            }
          ];

          sops.secrets =
            secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
              paperless_secret_key = {
                key = "paperless/secret_key";
                path = "/run/secrets/paperless.secret_key";
              };
              paperless_admin_pass = {
                key = "paperless/admin_pass";
                path = "/run/secrets/paperless.admin_pass";
              };
            }
            // (lib.optionalAttrs oidcEnabled (
              secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
                paperless_oidc_client_secret = {
                  key = "paperless/client_secret";
                  path = "/run/secrets/paperless.oidc_client_secret";
                };
              }
            ));

          sops.templates."paperless-environment" = {
            owner = "paperless";
            group = "paperless";
            mode = "0400";
            # Every paperless unit reads this file; a rendered-content change is invisible to
            # switch-to-configuration, so without this a stale environment survives a deploy.
            restartUnits = [
              "paperless-web.service"
              "paperless-consumer.service"
              "paperless-task-queue.service"
              "paperless-scheduler.service"
            ];
            content = ''
              PAPERLESS_SECRET_KEY=${config.sops.placeholder.paperless_secret_key}
            ''
            + lib.optionalString oidcEnabled ''
              PAPERLESS_SOCIALACCOUNT_PROVIDERS="${socialAccountProvidersEnv}"
            '';
          };

          systemd.tmpfiles.rules = [
            "d ${cfg.dataDir} 0700 paperless paperless - -"
            "d ${cfg.mediaDir} 0700 paperless paperless - -"
            "d ${cfg.consumptionDir} 0700 paperless paperless - -"
          ];

          environment.systemPackages = [
            postConsumeScript
          ];

          services.paperless = {
            address = lib.mkDefault "0.0.0.0";
            port = lib.mkDefault 8080;

            dataDir = lib.mkDefault "${cfg.dataRoot}/paperless";
            mediaDir = lib.mkDefault "${cfg.dataDir}/media";
            consumptionDir = lib.mkDefault "${cfg.dataDir}/consume";

            paperless-gpt = {
              docling.dataDir = lib.mkDefault "${cfg.dataRoot}/docling";
              secretFiles.host = cfg.secretFiles.host;
              instances = {
                llm = {
                  dataDir = lib.mkDefault "${cfg.dataRoot}/paperless-gpt-llm";
                  port = lib.mkDefault 5051;
                  manualTag = lib.mkDefault "paperless-gpt";
                  autoTag = lib.mkDefault "paperless-gpt-auto";
                  autoOcrTag = lib.mkDefault "ocr-llm";
                  pdfOcrCompleteTag = lib.mkDefault "ocr-llm-complete";
                  environment.OCR_PROVIDER = lib.mkDefault "llm";
                };
                docling = {
                  dataDir = lib.mkDefault "${cfg.dataRoot}/paperless-gpt-docling";
                  port = lib.mkDefault 5052;
                  manualTag = lib.mkDefault "paperless-gpt-docling-manual-unused";
                  autoTag = lib.mkDefault "paperless-gpt-docling-auto-unused";
                  autoOcrTag = lib.mkDefault "ocr-docling";
                  pdfOcrCompleteTag = lib.mkDefault "ocr-docling-complete";
                  environment.OCR_PROVIDER = lib.mkDefault "docling";
                };
              };
            };

            environmentFile = lib.mkDefault config.sops.templates."paperless-environment".path;
            passwordFile = lib.mkDefault config.sops.secrets.paperless_admin_pass.path;

            database.createLocally = lib.mkDefault false;
            # Plain PDFs/images only: no Tika/Gotenberg sidecar for office and
            # email documents.
            configureTika = lib.mkDefault false;
            openMPThreadingWorkaround = lib.mkDefault true;

            settings = {
              PAPERLESS_LOGLEVEL = "debug";
              PAPERLESS_CONSUMER_DELETE_DUPLICATES = true;

              PAPERLESS_DBENGINE = "postgresql";
              PAPERLESS_DBHOST = "/run/postgresql";
              PAPERLESS_DBNAME = "paperless";
              PAPERLESS_DBUSER = "paperless";

              PAPERLESS_OCR_LANGUAGE = "eng";
              PAPERLESS_TIME_ZONE = config.time.timeZone;
              PAPERLESS_URL = "https://paper.${(import ../../policy/globals.nix).domain}";
              PAPERLESS_DATE_ORDER = "DMY";
              PAPERLESS_FILENAME_DATE_ORDER = "YMD";

              PAPERLESS_CONSUMPTION_DIR = cfg.consumptionDir;
              PAPERLESS_DATA_DIR = cfg.dataDir;
              PAPERLESS_MEDIA_ROOT = cfg.mediaDir;

              PAPERLESS_POST_CONSUME_SCRIPT = "${postConsumeScript}/bin/paperless-post-consume";
            }
            // lib.optionalAttrs oidcEnabled {
              PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
              PAPERLESS_REDIRECT_LOGIN_TO_SSO = true;
              PAPERLESS_DISABLE_REGULAR_LOGIN = true;
              PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS = true;
              # allauth's own globals are not mapped by this application's settings loader,
              # so email-based sign-in is declared in the provider block below instead.
              PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS_CLAIM = "groups";
            };
          };

          services.postgres.consumers.paperless = {
            database = "paperless";
          };

          services.state-backups.services.paperless = {
            enable = true;
            mode = "live";
            paths = [
              cfg.dataDir
              cfg.mediaDir
              cfg.consumptionDir
            ];
          };

          systemd.services.paperless-group-seed = lib.mkIf (cfg.socialGroups != [ ]) {
            description = "Seed Paperless Django groups for OIDC sync";
            after = [ "paperless-scheduler.service" ];
            requires = [ "paperless-scheduler.service" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              Type = "oneshot";
              User = "paperless";
              Group = "paperless";
              EnvironmentFile = cfg.environmentFile;
              RemainAfterExit = true;
              Restart = "no";
            };
            script = ''
              exec /run/current-system/sw/bin/paperless-manage shell < ${groupSeedScript}
            '';
          };
        }
      ];
    };
}
