{
  lib,
  config,
  pkgs,
  ociImages,
  ...
}:
let
  cfg = config.services.paperless.paperless-gpt;
  bifrostBaseUrl = config.services.bifrost-gateway.endpoint.containerBaseUrl;

  enabledInstances = lib.filterAttrs (n: v: v.enable) cfg.instances;
  hasDocling = cfg.docling.enable;
in
{
  options.services.paperless.paperless-gpt = {
    docling = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable docling-serve OCR service shared across paperless-gpt instances.";
      };
      dataDir = lib.mkOption {
        type = lib.types.str;
        default = "/srv/data/docling";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8070;
      };
      address = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };
    };

    secretFiles.host =
      (import ../../../lib/secrets.nix { inherit lib; }).mkSecretFileOption
        "paperless-gpt-host-secrets";

    instances = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkEnableOption "this paperless-gpt instance";

            port = lib.mkOption {
              type = lib.types.port;
              default = 5050;
            };

            dataDir = lib.mkOption {
              type = lib.types.str;
              default = "/srv/data/paperless-gpt";
            };

            manualTag = lib.mkOption {
              type = lib.types.str;
              default = "paperless-gpt";
            };

            autoTag = lib.mkOption {
              type = lib.types.str;
              default = "paperless-gpt-auto";
            };

            autoOcrTag = lib.mkOption {
              type = lib.types.str;
              default = "paperless-gpt-ocr-auto";
            };

            pdfOcrCompleteTag = lib.mkOption {
              type = lib.types.str;
              default = "paperless-gpt-ocr-complete";
            };

            environment = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional environment variables merged into the container. Use for OCR_PROVIDER, LLM_MODEL, etc.";
            };
          };
        }
      );
      default = { };
      description = "Named paperless-gpt instances. Each is an independent container with its own port, state dir, and tag routing.";
    };
  };

  config = lib.mkIf (hasDocling || enabledInstances != { }) {
    sops.secrets =
      (import ../../../lib/secrets.nix { inherit lib; }).mkSecretsFromMap cfg.secretFiles.host
        {
          paperless_gpt_api_token = {
            key = "paperless-gpt/api_token";
            path = "/run/secrets/paperless-gpt.api_token";
          };
        };

    sops.templates = lib.mapAttrs' (
      name: inst:
      lib.nameValuePair "paperless-gpt-${name}.environment" {
        owner = "root";
        group = "root";
        mode = "0400";
        content = ''
          PAPERLESS_API_TOKEN=${config.sops.placeholder.paperless_gpt_api_token}
        '';
      }
    ) enabledInstances;

    systemd.tmpfiles.rules =
      lib.flatten (
        lib.mapAttrsToList (name: inst: [
          "d ${inst.dataDir} 0750 root root - -"
          "d ${inst.dataDir}/prompts 0750 root root - -"
          "d ${inst.dataDir}/db 0750 root root - -"
          "d ${inst.dataDir}/hocr 0750 root root - -"
          "d ${inst.dataDir}/pdf 0750 root root - -"
        ]) enabledInstances
      )
      ++ lib.optionals hasDocling [
        "d ${cfg.docling.dataDir} 0750 root root - -"
        "d ${cfg.docling.dataDir}/models 0750 root root - -"
        "d ${cfg.docling.dataDir}/scratch 0750 root root - -"
      ];

    virtualisation.podman.enable = true;
    virtualisation.podman.autoPrune.enable = lib.mkDefault true;

    virtualisation.oci-containers.containers = lib.mkMerge [
      (lib.optionalAttrs hasDocling {
        docling-serve = {
          autoStart = true;
          image = ociImages.doclingServe;
          ports = [ "${cfg.docling.address}:${toString cfg.docling.port}:5001" ];
          environment = {
            DOCLING_SERVE_LOG_LEVEL = "WARNING";
            DOCLING_SERVE_ARTIFACTS_PATH = "/models";
            DOCLING_SERVE_SCRATCH_PATH = "/scratch";
            DOCLING_SERVE_ENABLE_UI = "0";
          };
          volumes = [
            "${cfg.docling.dataDir}/models:/models:Z"
            "${cfg.docling.dataDir}/scratch:/scratch:Z"
          ];
          extraOptions = [
            "--memory=1024M"
            "--health-cmd=curl -sf http://127.0.0.1:5001/health || exit 1"
            "--health-interval=30s"
            "--health-retries=3"
          ];
        };
      })
      (lib.mapAttrs' (
        name: inst:
        lib.nameValuePair "paperless-gpt-${name}" {
          autoStart = true;
          image = ociImages.paperlessGpt;
          ports = [ "127.0.0.1:${toString inst.port}:8080" ];
          environment = {
            LISTEN_INTERFACE = ":8080";
            PAPERLESS_BASE_URL = "http://host.containers.internal:8080";
            MANUAL_TAG = inst.manualTag;
            AUTO_TAG = inst.autoTag;
            AUTO_OCR_TAG = inst.autoOcrTag;
            PDF_OCR_COMPLETE_TAG = inst.pdfOcrCompleteTag;
            LLM_PROVIDER = "openai";
            OPENAI_BASE_URL = bifrostBaseUrl;
            OPENAI_API_KEY = "bifrost-local";
            LOG_LEVEL = "info";
          }
          // lib.optionalAttrs (hasDocling) {
            DOCLING_URL = "http://host.containers.internal:${toString cfg.docling.port}";
          }
          // inst.environment;
          environmentFiles = [ config.sops.templates."paperless-gpt-${name}.environment".path ];
          volumes = [
            "${inst.dataDir}/prompts:/app/prompts"
            "${inst.dataDir}/db:/app/db"
            "${inst.dataDir}/hocr:/app/hocr"
            "${inst.dataDir}/pdf:/app/pdf"
          ];
        }
      ) enabledInstances)
    ];

    services.state-backups.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: inst:
        lib.nameValuePair "paperless-gpt-${name}" {
          enable = true;
          mode = "live";
          paths = [ inst.dataDir ];
        }
      ) enabledInstances)
      (lib.optionalAttrs hasDocling {
        paperless-gpt-docling = {
          enable = true;
          mode = "live";
          paths = [ cfg.docling.dataDir ];
        };
      })
    ];

    systemd.services = lib.mkMerge [
      (lib.mapAttrs' (
        name: inst:
        lib.nameValuePair "podman-paperless-gpt-${name}" {
          description = "paperless-gpt (${name}) Podman container service wrapper";
          wants = [ "network-online.target" ];
          after = [
            "network-online.target"
            "paperless-web.service"
          ]
          ++ lib.optionals (hasDocling) [
            "podman-docling-serve.service"
          ];
          requires = [
            "paperless-web.service"
          ]
          ++ lib.optionals (hasDocling) [
            "podman-docling-serve.service"
          ];
          unitConfig.RequiresMountsFor = [
            inst.dataDir
            (builtins.dirOf config.sops.templates."paperless-gpt-${name}.environment".path)
          ];
          restartTriggers = [ config.sops.templates."paperless-gpt-${name}.environment".path ];
        }
      ) enabledInstances)
    ];
  };
}
