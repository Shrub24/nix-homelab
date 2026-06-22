{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.niks3-cache;
  globals = import ../../policy/globals.nix;
  s3 = globals.s3 or { };
  # Strip https:// from endpoint for niks3 (controls SSL via useSSL).
  s3Host = builtins.replaceStrings [ "https://" "http://" ] [ "" "" ] (s3.endpoint or "");
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };
in
{
  options.services.niks3-cache = {
    enable = lib.mkEnableOption "niks3 sovereign Nix binary cache";

    hostSecretFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Host-scoped SOPS file for niks3 API push token.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "niks3-service-secrets";

    s3Endpoint = lib.mkOption {
      type = lib.types.str;
      default = s3Host;
      description = "S3-compatible endpoint host (no protocol).";
    };

    s3Bucket = lib.mkOption {
      type = lib.types.str;
      default = "nix-cache";
      description = "S3 bucket name.";
    };

    s3Region = lib.mkOption {
      type = lib.types.str;
      default = s3.region or "auto";
      description = "S3 region.";
    };

    cacheUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://cache.shrublab.xyz";
      description = "Public cache URL for consumer reads.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.niks3 = {
      enable = true;
      httpAddr = "0.0.0.0:5751";
      database.createLocally = true;

      gc = {
        enable = true; # Default: true
        olderThan = "720h"; # 30 days (default)
        failedUploadsOlderThan = "6h"; # 6 hours (default)
        schedule = "daily"; # Run at midnight daily (default)
        randomizedDelaySec = 1800; # Add 0-30 min random delay (default)
      };

      s3 = {
        endpoint = cfg.s3Endpoint;
        bucket = cfg.s3Bucket;
        region = cfg.s3Region;
        useSSL = true;
        accessKeyFile = "/run/secrets/niks3.s3_access_key_id";
        secretKeyFile = "/run/secrets/niks3.s3_secret_access_key";
      };

      cacheUrl = cfg.cacheUrl;
      signKeyFiles = [ "/run/secrets/niks3.signing_key" ];
      apiTokenFile = lib.mkIf (cfg.hostSecretFile != null) "/run/secrets/niks3.api_token";
    };

    sops.secrets = {
      niks3_signing_key = {
        sopsFile = cfg.secretFiles.host;
        key = "signing_key";
        path = "/run/secrets/niks3.signing_key";
        owner = "niks3";
        group = "niks3";
        mode = "0400";
      };
      niks3_s3_access_key_id = {
        sopsFile = cfg.secretFiles.host;
        key = "s3_access_key_id";
        path = "/run/secrets/niks3.s3_access_key_id";
        owner = "niks3";
        group = "niks3";
        mode = "0400";
      };
      niks3_s3_secret_access_key = {
        sopsFile = cfg.secretFiles.host;
        key = "s3_secret_access_key";
        path = "/run/secrets/niks3.s3_secret_access_key";
        owner = "niks3";
        group = "niks3";
        mode = "0400";
      };
    }
    // lib.optionalAttrs (cfg.hostSecretFile != null) {
      niks3_api_token = {
        sopsFile = cfg.hostSecretFile;
        key = "niks3/api_token";
        path = "/run/secrets/niks3.api_token";
        owner = "niks3";
        group = "niks3";
        mode = "0400";
      };
    };

    systemd.services.niks3 = {
      after = lib.mkAfter [ "sops-nix.service" ];
      wants = lib.mkAfter [ "sops-nix.service" ];
    };
  };
}
