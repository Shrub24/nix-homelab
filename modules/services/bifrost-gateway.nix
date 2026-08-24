{
  config,
  lib,
  pkgs,
  ociImages,
  ...
}:
let
  cfg = config.services.bifrost-gateway;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };

  hostBase = "http://127.0.0.1:${toString cfg.port}";
  containerBase = "http://host.containers.internal:${toString cfg.port}";
  appDir = "${cfg.dataDir}/app";
  configPath = "${appDir}/config.json";
  configDbPath = "${appDir}/config.db";
  parsedConfig = builtins.fromJSON (builtins.readFile cfg.configFile);

  runtimeUid = 1000;
  runtimeGid = 1000;
  logsDir = "${appDir}/logs";
  logsDbPath = "${appDir}/logs.db";
  cacheDir = "${appDir}/cache";
  vectorDir = "${appDir}/vector";
  environmentFile = config.sops.templates."bifrost.environment".path;
in
{
  options.services.bifrost-gateway = {
    enable = lib.mkEnableOption "Bifrost AI gateway";

    image = lib.mkOption {
      type = lib.types.str;
      default = ociImages.bifrost;
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/bifrost";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 7411;
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      description = "Repo-owned Bifrost config.json source for file-driven mode.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "bifrost-host-secrets";

    endpoint.hostBaseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${hostBase}/v1";
    };

    endpoint.containerBaseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${containerBase}/v1";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.attrByPath [ "config_store" "enabled" ] false parsedConfig);
        message = "services.bifrost-gateway.configFile must keep config_store.enabled=false for file-driven mode.";
      }
      (secretHelpers.mkRequiredSecretAssertion {
        inherit (cfg) enable;
        file = cfg.secretFiles.host;
        feature = "services.bifrost-gateway";
        label = "secretFiles.host";
      })
    ];

    sops.templates."bifrost.environment" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        BIFROST_ENCRYPTION_KEY=${config.sops.placeholder.bifrost_encryption_key}
        GEMINI_API_KEY=${config.sops.placeholder.bifrost_gemini_api_key}
        DEEPSEEK_API_KEY=${config.sops.placeholder.bifrost_deepseek_api_key}
        OPENCODE_API_KEY=${config.sops.placeholder.bifrost_opencode_api_key}
        OPENROUTER_API_KEY=${config.sops.placeholder.bifrost_openrouter_api_key}
      '';
    };

    sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
      bifrost_encryption_key = {
        key = "bifrost/encryption_key";
        path = "/run/secrets/bifrost.encryption_key";
      };
      bifrost_gemini_api_key = {
        key = "bifrost/gemini_api_key";
        path = "/run/secrets/bifrost.gemini_api_key";
      };
      bifrost_deepseek_api_key = {
        key = "bifrost/deepseek_api_key";
        path = "/run/secrets/bifrost.deepseek_api_key";
      };
      bifrost_opencode_api_key = {
        key = "bifrost/opencode_api_key";
        path = "/run/secrets/bifrost.opencode_api_key";
      };
      bifrost_openrouter_api_key = {
        key = "bifrost/openrouter_api_key";
        path = "/run/secrets/bifrost.openrouter_api_key";
      };
    };

    virtualisation.podman.enable = true;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root - -"
      "z ${cfg.dataDir} 0755 root root - -"
      "d ${appDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "z ${appDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "d ${logsDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "z ${logsDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "d ${cacheDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "z ${cacheDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "d ${vectorDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
      "z ${vectorDir} 0775 ${toString runtimeUid} ${toString runtimeGid} - -"
    ];

    systemd.services.bifrost-config = {
      description = "Render Bifrost config from repo-owned settings";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-bifrost.service" ];
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "bifrost-config-render" ''
          set -euo pipefail
          install -d -m 0775 -o ${toString runtimeUid} -g ${toString runtimeGid} "${appDir}"
          install -d -m 0775 -o ${toString runtimeUid} -g ${toString runtimeGid} "${logsDir}"
          install -d -m 0775 -o ${toString runtimeUid} -g ${toString runtimeGid} "${cacheDir}"
          install -d -m 0775 -o ${toString runtimeUid} -g ${toString runtimeGid} "${vectorDir}"
          # Bifrost prefers the imperative SQLite config store over config.json when present.
          rm -f "${configDbPath}"
          install -m 0644 -o ${toString runtimeUid} -g ${toString runtimeGid} "${cfg.configFile}" "${configPath}"
        '';
      };
    };

    virtualisation.oci-containers.containers.bifrost = {
      autoStart = true;
      image = cfg.image;
      ports = [ "0.0.0.0:${toString cfg.port}:${toString cfg.port}" ];
      environment = {
        APP_DIR = "/app/data";
        APP_HOST = "0.0.0.0";
        APP_PORT = toString cfg.port;
      };
      environmentFiles = [ environmentFile ];
      volumes = [
        "${appDir}:/app/data"
      ];
    };

    services.state-backups.services.bifrost-gateway = {
      enable = true;
      mode = "live";
      paths = [ appDir ];
      exclude = [
        logsDir
        logsDbPath
        "${logsDbPath}-shm"
        "${logsDbPath}-wal"
        cacheDir
        vectorDir
      ];
    };

    systemd.services."podman-bifrost" = {
      wants = [
        "network-online.target"
        "bifrost-config.service"
      ];
      after = [
        "network-online.target"
        "bifrost-config.service"
      ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        appDir
      ];
      restartTriggers = [
        cfg.configFile
      ]
      ++ [ environmentFile ];
    };
  };
}
