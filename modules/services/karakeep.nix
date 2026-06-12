{
  lib,
  config,
  pkgs,
  ociImages,
  ...
}:
let
  cfg = config.services.karakeep-pod;
  envDir = builtins.dirOf cfg.environmentFile;
  globals = import ../../policy/globals.nix;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };
in
{
  options.services.karakeep-pod = {
    enable = lib.mkEnableOption "Karakeep bookmark and read-later service";

    webImage = lib.mkOption {
      type = lib.types.str;
      default = ociImages.karakeepWeb;
      description = "Karakeep web container image.";
    };

    chromeImage = lib.mkOption {
      type = lib.types.str;
      default = ociImages.karakeepChrome;
      description = "Headless Chrome container image for link preview rendering.";
    };

    meilisearchImage = lib.mkOption {
      type = lib.types.str;
      default = ociImages.karakeepMeilisearch;
      description = "Meilisearch container image for full-text search.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = globals.services.karakeep-pod.dataDir;
      description = "Persistent data directory for Karakeep app and search state.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address for host port mapping.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 3010;
      description = "Karakeep web UI port on the host.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = config.sops.templates."karakeep.environment".path;
      description = "Required environment file containing Karakeep auth and search secrets.";
    };

    publicUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://keep.shrublab.xyz";
      description = "Public-facing base URL for Karakeep (NEXTAUTH_URL).";
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "karakeep-net";
      description = "Dedicated Podman network shared by Karakeep containers for stable DNS/service discovery.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "karakeep-host-secrets";
    secretFiles.oidc = secretHelpers.mkSecretFileOption "karakeep-oidc-secrets";

    oidc = {
      enable = lib.mkEnableOption "OIDC login for Karakeep";

      clientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Canonical OIDC client ID for Karakeep.";
      };

      wellknownUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "OIDC .well-known configuration URL (OAUTH_WELLKNOWN_URL).";
      };

      providerName = lib.mkOption {
        type = lib.types.str;
        default = "Kanidm";
        description = "Display name for OIDC provider (OAUTH_PROVIDER_NAME).";
      };

      scope = lib.mkOption {
        type = lib.types.str;
        default = "openid email profile";
        description = "OIDC scope string (OAUTH_SCOPE).";
      };

      autoRedirect = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Auto-redirect login flow to OIDC provider (OAUTH_AUTO_REDIRECT).";
      };

      allowDangerousEmailAccountLinking = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow dangerous email account linking (OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING).";
      };

      disablePasswordAuth = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Disable Karakeep password auth (DISABLE_PASSWORD_AUTH).";
      };
    };

    storage = {
      s3 = {
        enable = lib.mkEnableOption "S3-compatible object storage backend for Karakeep assets";

        bucket = lib.mkOption {
          type = lib.types.str;
          default = globals.services.karakeep-pod.s3.bucket;
          description = "Bucket name for Karakeep asset storage.";
        };

        forcePathStyle = lib.mkOption {
          type = lib.types.bool;
          default = globals.s3.forcePathStyle;
          description = "Force path-style S3 requests (ASSET_STORE_S3_FORCE_PATH_STYLE, default from policy/globals.nix).";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.oidc.enable || cfg.oidc.clientId != null;
        message = "services.karakeep-pod.oidc.clientId must be set when OIDC is enabled.";
      }
      {
        assertion = !cfg.oidc.enable || cfg.oidc.wellknownUrl != "";
        message = "services.karakeep-pod.oidc.wellknownUrl must be set when OIDC is enabled.";
      }
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFiles.host;
        feature = "services.karakeep-pod";
        label = "secretFiles.host";
      })
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.oidc.enable;
        file = cfg.secretFiles.oidc;
        feature = "services.karakeep-pod.oidc";
        label = "secretFiles.oidc";
      })
    ];

    sops.templates."karakeep.environment" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        NEXTAUTH_SECRET=${config.sops.placeholder.karakeep_nextauth_secret}
        MEILI_MASTER_KEY=${config.sops.placeholder.karakeep_meilisearch_master_key}
        OAUTH_CLIENT_ID=${cfg.oidc.clientId}
        OAUTH_CLIENT_SECRET=${config.sops.placeholder.karakeep_oidc_client_secret}
        OPENAI_BASE_URL=${config.services.bifrost-gateway.endpoint.containerBaseUrl}
        OPENAI_API_KEY=bifrost-local
        INFERENCE_TEXT_MODEL=${globals.aiGateway.aliases.text}
        INFERENCE_IMAGE_MODEL=${globals.aiGateway.aliases.image}
        EMBEDDING_TEXT_MODEL=${globals.aiGateway.aliases.embedding}
        ASSET_STORE_S3_ENDPOINT=${globals.s3.endpoint}
        ASSET_STORE_S3_REGION=${globals.s3.region}
        ASSET_STORE_S3_BUCKET=${cfg.storage.s3.bucket}
        ASSET_STORE_S3_ACCESS_KEY_ID=${config.sops.placeholder.karakeep_asset_store_s3_access_key_id}
        ASSET_STORE_S3_SECRET_ACCESS_KEY=${config.sops.placeholder.karakeep_asset_store_s3_secret_access_key}
      '';
    };

    sops.secrets =
      secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
        karakeep_nextauth_secret = {
          key = "karakeep/nextauth_secret";
          path = "/run/secrets/karakeep.nextauth_secret";
        };
        karakeep_meilisearch_master_key = {
          key = "karakeep/meilisearch_master_key";
          path = "/run/secrets/karakeep.meilisearch_master_key";
        };
        karakeep_asset_store_s3_access_key_id = {
          key = "karakeep/asset_store_s3_access_key_id";
          path = "/run/secrets/karakeep.asset_store_s3_access_key_id";
        };
        karakeep_asset_store_s3_secret_access_key = {
          key = "karakeep/asset_store_s3_secret_access_key";
          path = "/run/secrets/karakeep.asset_store_s3_secret_access_key";
        };
      }
      // (lib.optionalAttrs cfg.oidc.enable (
        secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
          karakeep_oidc_client_secret = {
            key = "karakeep/client_secret";
            path = "/run/secrets/karakeep.oidc_client_secret";
          };
        }
      ));

    virtualisation.podman.enable = true;
    virtualisation.podman.autoPrune.enable = lib.mkDefault true;

    systemd.services."podman-network-${cfg.networkName}" = {
      description = "Create Podman network ${cfg.networkName}";
      wantedBy = [ "multi-user.target" ];
      before = [
        "podman-karakeep-meilisearch.service"
        "podman-karakeep-chrome.service"
        "podman-karakeep-web.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network exists ${cfg.networkName} || ${pkgs.podman}/bin/podman network create ${cfg.networkName}'";
        ExecStop = "${pkgs.runtimeShell} -c '${pkgs.podman}/bin/podman network rm -f ${cfg.networkName} || true'";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
      "d ${cfg.dataDir}/app 0750 root root - -"
      "d ${cfg.dataDir}/meilisearch 0750 root root - -"
      "d ${envDir} 0750 root root - -"
      "f ${cfg.environmentFile} 0640 root root - -"
    ];

    virtualisation.oci-containers.containers.karakeep-meilisearch = {
      autoStart = true;
      image = cfg.meilisearchImage;
      extraOptions = [
        "--network=${cfg.networkName}"
      ];
      environment = {
        MEILI_NO_ANALYTICS = "true";
      };
      environmentFiles = [
        cfg.environmentFile
      ];
      volumes = [
        "${cfg.dataDir}/meilisearch:/meili_data"
      ];
    };

    virtualisation.oci-containers.containers.karakeep-chrome = {
      autoStart = true;
      image = cfg.chromeImage;
      extraOptions = [
        "--network=${cfg.networkName}"
      ];
      cmd = [
        "--no-sandbox"
        "--remote-debugging-address=0.0.0.0"
        "--remote-debugging-port=9222"
      ];
    };

    virtualisation.oci-containers.containers.karakeep-web = {
      autoStart = true;
      image = cfg.webImage;
      extraOptions = [
        "--network=${cfg.networkName}"
      ];
      ports = [
        "${cfg.listenAddress}:${toString cfg.port}:3000"
      ];
      environment = {
        MEILI_ADDR = "http://karakeep-meilisearch:7700";
        BROWSER_WEB_URL = "http://karakeep-chrome:9222";
        DATA_DIR = "/data";
        MEILI_NO_ANALYTICS = "true";
        NEXTAUTH_URL = cfg.publicUrl;
      }
      // {
        DISABLE_PASSWORD_AUTH = if cfg.oidc.disablePasswordAuth then "true" else "false";
      }
      // lib.optionalAttrs cfg.oidc.enable {
        OAUTH_WELLKNOWN_URL = cfg.oidc.wellknownUrl;
        OAUTH_SCOPE = cfg.oidc.scope;
        OAUTH_PROVIDER_NAME = cfg.oidc.providerName;
        OAUTH_AUTO_REDIRECT = if cfg.oidc.autoRedirect then "true" else "false";
        OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING =
          if cfg.oidc.allowDangerousEmailAccountLinking then "true" else "false";
      }
      // lib.optionalAttrs cfg.storage.s3.enable {
        ASSET_STORE_S3_FORCE_PATH_STYLE = if cfg.storage.s3.forcePathStyle then "true" else "false";
      };
      environmentFiles = [
        cfg.environmentFile
      ];
      volumes = [
        "${cfg.dataDir}/app:/data"
      ];
    };

    services.state-backups.services.karakeep = {
      enable = true;
      mode = "live";
      paths = [ cfg.dataDir ];
    };

    systemd.services."podman-karakeep-web" = {
      wants = [
        "network-online.target"
        "podman-network-${cfg.networkName}.service"
      ];
      after = [
        "network-online.target"
        "podman-network-${cfg.networkName}.service"
        "podman-karakeep-meilisearch.service"
        "podman-karakeep-chrome.service"
      ];
      requires = [
        "podman-network-${cfg.networkName}.service"
        "podman-karakeep-meilisearch.service"
        "podman-karakeep-chrome.service"
      ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        envDir
      ];
    };

    systemd.services."podman-karakeep-meilisearch" = {
      wants = [
        "network-online.target"
        "podman-network-${cfg.networkName}.service"
      ];
      after = [
        "network-online.target"
        "podman-network-${cfg.networkName}.service"
      ];
      requires = [ "podman-network-${cfg.networkName}.service" ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
      ];
    };

    systemd.services."podman-karakeep-chrome" = {
      wants = [
        "network-online.target"
        "podman-network-${cfg.networkName}.service"
      ];
      after = [
        "network-online.target"
        "podman-network-${cfg.networkName}.service"
      ];
      requires = [ "podman-network-${cfg.networkName}.service" ];
    };
  };
}
