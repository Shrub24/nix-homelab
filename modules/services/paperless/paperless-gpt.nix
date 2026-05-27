{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.paperless.paperless-gpt;
  globals = import ../../../policy/globals.nix;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
  bifrostBaseUrl = config.services.bifrost-gateway.endpoint.containerBaseUrl;
  environmentFile = config.sops.templates."paperless-gpt.environment".path;
  envDir = builtins.dirOf environmentFile;

  doclingPort = 8070;
  doclingAddress = "127.0.0.1";
  gptPort = 5050;
in
{
  options.services.paperless.paperless-gpt = {
    enable = lib.mkEnableOption "paperless-gpt AI enhancement stack";

    docling = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable docling-serve OCR alongside paperless-gpt.";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/srv/data/docling";
      };
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/paperless-gpt";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "paperless-gpt-host-secrets";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        inherit (cfg) enable;
        file = cfg.secretFiles.host;
        feature = "services.paperless.paperless-gpt";
        label = "secretFiles.host";
      })
      {
        assertion = config.services.bifrost-gateway.enable;
        message = "services.paperless.paperless-gpt requires services.bifrost-gateway.";
      }
    ];

    sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
      paperless_gpt_api_token = {
        key = "paperless-gpt/api_token";
        path = "/run/secrets/paperless-gpt.api_token";
      };
    };

    sops.templates."paperless-gpt.environment" = {
      owner = "root";
      group = "root";
      mode = "0400";
      content = ''
        PAPERLESS_API_TOKEN=${config.sops.placeholder.paperless_gpt_api_token}
      '';
    };

    systemd.services.docling-serve = lib.mkIf cfg.docling.enable {
      description = "Docling Serve — AI document OCR API";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.docling-serve}/bin/docling-serve";
        Restart = "on-failure";
        RestartSec = "5s";
        Environment = [
          "UVICORN_HOST=${doclingAddress}"
          "UVICORN_PORT=${toString doclingPort}"
          "UVICORN_WORKERS=1"
          "DOCLING_SERVE_ARTIFACTS_PATH=${cfg.docling.dataDir}/models"
          "DOCLING_SERVE_SCRATCH_PATH=${cfg.docling.dataDir}/scratch"
          "DOCLING_SERVE_LOG_LEVEL=WARNING"
          "DOCLING_NUM_THREADS=2"
        ];
        MemoryMax = "1024M";
        MemoryHigh = "768M";
        OOMScoreAdjust = 200;
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        ReadWritePaths = [ cfg.docling.dataDir ];
      };
      unitConfig.RequiresMountsFor = [ cfg.docling.dataDir ];
    };

    systemd.tmpfiles.rules =
      (lib.optionals cfg.docling.enable [
        "d ${cfg.docling.dataDir} 0750 root root - -"
        "d ${cfg.docling.dataDir}/models 0750 root root - -"
        "d ${cfg.docling.dataDir}/scratch 0750 root root - -"
      ])
      ++ [
        "d ${cfg.dataDir} 0750 root root - -"
        "d ${cfg.dataDir}/prompts 0750 root root - -"
        "d ${cfg.dataDir}/db 0750 root root - -"
        "d ${cfg.dataDir}/hocr 0750 root root - -"
        "d ${cfg.dataDir}/pdf 0750 root root - -"
        "d ${envDir} 0750 root root - -"
        "f ${environmentFile} 0640 root root - -"
      ];

    virtualisation.podman.enable = true;
    virtualisation.podman.autoPrune.enable = lib.mkDefault true;

    virtualisation.oci-containers.containers.paperless-gpt = {
      autoStart = true;
      image = "ghcr.io/icereed/paperless-gpt:latest";
      ports = [ "127.0.0.1:${toString gptPort}:8080" ];
      environment = {
        LISTEN_INTERFACE = ":8080";
        PAPERLESS_BASE_URL = "http://host.containers.internal:8080";
        OCR_PROVIDER = "docling";
        DOCLING_URL = "http://host.containers.internal:${toString doclingPort}";
        LLM_PROVIDER = "openai";
        LLM_MODEL = globals.aiGateway.aliases.image;
        OPENAI_BASE_URL = bifrostBaseUrl;
        OPENAI_API_KEY = "bifrost-local";
        LOG_LEVEL = "info";
      };
      environmentFiles = [ environmentFile ];
      volumes = [
        "${cfg.dataDir}/prompts:/app/prompts"
        "${cfg.dataDir}/db:/app/db"
        "${cfg.dataDir}/hocr:/app/hocr"
        "${cfg.dataDir}/pdf:/app/pdf"
      ];
    };

    services.state-backups.services.paperless-gpt = {
      enable = true;
      mode = "live";
      paths = [ cfg.dataDir ] ++ lib.optionals cfg.docling.enable [ cfg.docling.dataDir ];
    };

    systemd.services."podman-paperless-gpt" = {
      description = "paperless-gpt Podman container service wrapper";
      wants = [ "network-online.target" ];
      after =
        [
          "network-online.target"
          "paperless-web.service"
        ]
        ++ lib.optionals cfg.docling.enable [ "docling-serve.service" ];
      requires =
        [ "paperless-web.service" ]
        ++ lib.optionals cfg.docling.enable [ "docling-serve.service" ];
      unitConfig.RequiresMountsFor = [
        cfg.dataDir
        envDir
      ];
      restartTriggers = [ environmentFile ];
    };
  };
}
