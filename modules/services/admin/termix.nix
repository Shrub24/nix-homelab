{
  lib,
  config,
  ociImages,
  ...
}:
let
  appCfg = config.applications.admin;
  cfg = config.services.admin.termix;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
in
{
  options.services.admin.termix = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable admin-owned Termix composition wiring.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/termix";
      description = "Data directory for Termix";
    };

    oidc = {
      enabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether Termix should enable native OIDC auth wiring.";
      };

      clientId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Canonical OIDC client ID for Termix.";
      };

      issuerUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OIDC issuer URL for Termix auth posture documentation/runtime metadata.";
      };

      authorizationUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OIDC authorization URL for Termix runtime wiring.";
      };

      tokenUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OIDC token URL for Termix runtime wiring.";
      };

      userinfoUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "OIDC userinfo URL for Termix runtime wiring.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional env-file containing Termix OIDC variables (OIDC_CLIENT_ID, OIDC_CLIENT_SECRET, OIDC_AUTHORIZATION_URL, OIDC_TOKEN_URL, etc.).";
      };
    };

    secretFiles.oidc = secretHelpers.mkSecretFileOption "termix-oidc-secrets";
  };

  config = lib.mkIf (appCfg.enable && cfg.enable) {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.oidc.enabled;
        file = cfg.secretFiles.oidc;
        feature = "services.admin.termix";
        label = "secretFiles.oidc";
      })
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.clientId != null;
        message = "services.admin.termix.oidc.clientId must be set when services.admin.termix.oidc.enabled=true.";
      }
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.issuerUrl != null;
        message = "services.admin.termix.oidc.issuerUrl must be set when services.admin.termix.oidc.enabled=true.";
      }
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.environmentFile != null;
        message = "services.admin.termix.oidc.environmentFile must be set when services.admin.termix.oidc.enabled=true.";
      }
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.authorizationUrl != null;
        message = "services.admin.termix.oidc.authorizationUrl must be set when services.admin.termix.oidc.enabled=true.";
      }
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.tokenUrl != null;
        message = "services.admin.termix.oidc.tokenUrl must be set when services.admin.termix.oidc.enabled=true.";
      }
      {
        assertion = !cfg.oidc.enabled || cfg.oidc.userinfoUrl != null;
        message = "services.admin.termix.oidc.userinfoUrl must be set when services.admin.termix.oidc.enabled=true.";
      }
    ];

    # Termix OIDC template - owned by termix module when OIDC is enabled
    sops.templates."termix-oidc.env" = lib.mkIf cfg.oidc.enabled {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        OIDC_CLIENT_ID=${cfg.oidc.clientId}
        OIDC_CLIENT_SECRET=${config.sops.placeholder.termix_oidc_client_secret}
        OIDC_ISSUER_URL=${cfg.oidc.issuerUrl}
        OIDC_AUTHORIZATION_URL=${cfg.oidc.authorizationUrl}
        OIDC_TOKEN_URL=${cfg.oidc.tokenUrl}
        OIDC_USERINFO_URL=${cfg.oidc.userinfoUrl}
        OIDC_SCOPES=openid email profile
      '';
    };

    sops.secrets = lib.mkIf cfg.oidc.enabled (
      secretHelpers.mkSecretsFromMap cfg.secretFiles.oidc {
        termix_oidc_client_secret = {
          key = "termix/client_secret";
          path = "/run/secrets/termix.oidc_client_secret";
          owner = "root";
          group = "root";
        };
      }
    );

    virtualisation.podman.enable = true;

    virtualisation.oci-containers.containers = {
      guacd = {
        autoStart = true;
        image = ociImages.guacd;
        volumes = [
          "${cfg.dataDir}/guacd:/var/lib/guacd"
        ];
      };

      termix = {
        autoStart = true;
        image = ociImages.termix;
        dependsOn = [ "guacd" ];
        environment = {
          GUACD_HOST = "127.0.0.1";
          GUACD_PORT = "4822";
        }
        // lib.optionalAttrs cfg.oidc.enabled {
          OIDC_ISSUER_URL = toString cfg.oidc.issuerUrl;
        };
        environmentFiles = lib.optionals (cfg.oidc.environmentFile != null) [
          cfg.oidc.environmentFile
        ];
        labels = lib.optionalAttrs cfg.oidc.enabled {
          "io.shrublab.auth.oidc" = "kanidm";
          "io.shrublab.auth.oidc.issuer" = toString cfg.oidc.issuerUrl;
        };
        ports = [
          "0.0.0.0:8083:8080"
        ];
        extraOptions = [
          "--dns-search=tail0fe19b.ts.net"
          "--dns=100.100.100.100"
        ];
        volumes = [
          "${cfg.dataDir}/data:/app/data"
        ];
      };
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root - -"
      "d ${cfg.dataDir}/data 0750 root root - -"
      "d ${cfg.dataDir}/guacd 0750 root root - -"
    ];

    systemd.services."podman-guacd" = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };

    systemd.services."podman-termix" = {
      wants = [
        "network-online.target"
        "podman-guacd.service"
      ];
      after = [
        "network-online.target"
        "podman-guacd.service"
      ];
    };
  };
}
