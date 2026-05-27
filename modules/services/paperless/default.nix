{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.paperless;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
  fqPackage = self.packages.${pkgs.stdenv.hostPlatform.system};
  oidcEnabled = cfg.oidc.enable;
  socialAccountProvidersJson = builtins.toJSON {
    openid_connect = {
      SCOPE = [
        "openid"
        "profile"
        "email"
        "groups_name"
      ];
      OAUTH_PKCE_ENABLED = true;
      APPS = [
        {
          provider_id = "kanidm";
          name = "Kanidm";
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
    DOCUMENT_TITLE="''${DOCUMENT_TITLE:-Unknown}"
    echo "New document: $DOCUMENT_TITLE" | ${fqPackage.notify}/bin/notify info "Paperless" "info" "services"
  '';

  # Python seed script for OIDC sync groups
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
    ./paperless-gpt.nix
  ];

  options.services.paperless = {
    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data";
      description = "Top-level data root for Paperless dirs (data, media, consumption, paperless-gpt, docling).";
    };

    enableAI = lib.mkEnableOption "paperless-gpt AI enhancement stack (docling-serve + paperless-gpt)";

    secretFiles.host = secretHelpers.mkSecretFileOption "paperless-host-secrets";

    secretFiles.oidc = secretHelpers.mkSecretFileOption "paperless-oidc-secrets";

    oidc = {
      enable = lib.mkEnableOption "Kanidm OIDC login for Paperless";

      wellknownUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC provider .well-known/openid-configuration URL.";
      };

      clientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OIDC client ID registered with the identity provider.";
      };
    };

    socialGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "service-admins"
        "users"
      ];
      description = "Django groups to pre-seed for OIDC sync. Kanidm groups matching these names have membership synced.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        inherit (cfg) enable;
        file = cfg.secretFiles.host;
        feature = "services.paperless";
        label = "secretFiles.host";
      })
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
        enable = cfg.enableAI;
        dataDir = "${cfg.dataRoot}/paperless-gpt";
        docling.dataDir = "${cfg.dataRoot}/docling";
        secretFiles.host = cfg.secretFiles.host;
      };

      environmentFile = lib.mkDefault config.sops.templates."paperless-environment".path;
      passwordFile = lib.mkDefault config.sops.secrets.paperless_admin_pass.path;

      database.createLocally = lib.mkDefault false;
      configureTika = lib.mkDefault true;
      openMPThreadingWorkaround = lib.mkDefault true;

      settings = {
        PAPERLESS_LOGLEVEL = "debug";

        PAPERLESS_DBENGINE = "postgresql";
        PAPERLESS_DBHOST = "/run/postgresql";
        PAPERLESS_DBNAME = "paperless";
        PAPERLESS_DBUSER = "paperless";

        PAPERLESS_OCR_LANGUAGE = "eng";
        PAPERLESS_TIME_ZONE = config.time.timeZone;
        PAPERLESS_URL = "https://paper.shrublab.xyz";
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
        PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS_CLAIM = "groups_name";
      };
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

    systemd.services.paperless-group-seed =
      lib.mkIf (cfg.socialGroups != [ ])
        {
          description = "Seed Paperless Django groups for OIDC sync";
          after = [ "paperless-scheduler.service" ];
          requires = [ "paperless-scheduler.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = "paperless";
            Group = "paperless";
            RemainAfterExit = true;
            Restart = "no";
          };
          script = ''
            exec /run/current-system/sw/bin/paperless-manage shell < ${groupSeedScript}
          '';
        };
  };
}
