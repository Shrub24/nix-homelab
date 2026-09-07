{
  lib,
  config,
  ...
}:
let
  cfg = config.applications."edge-ingress";
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };
in
{
  imports = [ ../../modules/services/edge-proxy-ingress.nix ];

  options.applications."edge-ingress" = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable host-level edge ingress composition.";
    };

    role = lib.mkOption {
      type = lib.types.enum [
        "none"
        "edge"
        "origin"
      ];
      default = "none";
      description = "Ingress role for this host.";
    };

    primaryDomain = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Primary ingress domain.";
    };

    acmeEmail = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ACME email for ingress certificates.";
    };

    cloudflareCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Credentials env-file for Cloudflare DNS-01 token.";
    };

    trustedProxyCidrs = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      description = "Override trusted proxy CIDR ranges. Uses Cloudflare defaults (from services.edge-proxy-ingress) when null.";
    };

    authenticatedOriginPulls = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Cloudflare Authenticated Origin Pulls (mTLS).";
      };

      caCertFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "CA certificate path used for mTLS origin pull verification.";
      };
    };

    routes = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Ingress routes declared at host/application layer.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "edge-ingress-host-secrets";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.role == "edge";
        file = cfg.secretFiles.host;
        feature = "applications.edge-ingress";
        label = "secretFiles.host";
      })
    ];

    services."edge-proxy-ingress" = lib.mkMerge [
      {
        inherit (cfg)
          role
          primaryDomain
          acmeEmail
          routes
          ;

        # Use the template file as the cloudflare credentials file when role=edge
        cloudflareCredentialsFile = lib.mkIf (
          cfg.role == "edge"
        ) config.sops.templates."caddy-cloudflare.env".path;

        inherit (cfg) authenticatedOriginPulls;
      }
      (lib.mkIf (cfg.trustedProxyCidrs != null) {
        inherit (cfg) trustedProxyCidrs;
      })
    ];

    # Cloudflare/Caddy template - owned by edge-ingress when role=edge
    sops.templates."caddy-cloudflare.env" = lib.mkIf (cfg.role == "edge") {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_dns_api_token}
      '';
    };

    sops.secrets = lib.mkIf (cfg.role == "edge") (
      secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
        cloudflare_dns_api_token = {
          key = "cloudflare/dns_api_token";
          path = "/run/secrets/cloudflare.dns_api_token";
          owner = "root";
          group = "root";
        };
      }
    );
  };
}
