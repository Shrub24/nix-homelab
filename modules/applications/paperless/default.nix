{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.applications.paperless;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

  paperlessEnabled = cfg.enable && builtins.pathExists cfg.secretFiles.host;

  oidcEnabled =
    paperlessEnabled && cfg.secretFiles.oidc != null && builtins.pathExists cfg.secretFiles.oidc;

  paperlessGptEnabled = paperlessEnabled && cfg.enableAI;

in
{
  imports = [
    ../../services/paperless
  ];

  options.applications.paperless = {
    enable = lib.mkEnableOption "paperless document management application composition";

    dataRoot = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data";
      description = "Top-level data root for Paperless services.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "paperless-host-secrets";

    enableAI = lib.mkEnableOption "paperless-gpt AI enhancement stack (docling-serve + paperless-gpt)";

    secretFiles.oidc = secretHelpers.mkSecretFileOption "paperless-oidc-secrets";

    taxonomy = {
      tags = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "Paperless tags to seed. Passthrough to services.paperless.taxonomy.tags.";
      };

      correspondents = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "Paperless correspondents to seed. Passthrough to services.paperless.taxonomy.correspondents.";
      };

      documentTypes = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        description = "Paperless document types to seed. Passthrough to services.paperless.taxonomy.documentTypes.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.paperless = {
      enable = paperlessEnabled;
      dataDir = "${cfg.dataRoot}/paperless";
      secretFiles.host = cfg.secretFiles.host;
      secretFiles.oidc = cfg.secretFiles.oidc;

      oidc = {
        enable = oidcEnabled;
        clientId = lib.mkDefault config.services.identity.oidc.clients.paperless.clientId;
        wellknownUrl = lib.mkDefault config.services.identity.oidc.clients.paperless.wellknownUrl;
      };

      taxonomy = {
        inherit (cfg.taxonomy) tags correspondents documentTypes;
      };
    };

    services.paperless.paperless-gpt = {
      enable = paperlessGptEnabled;
      dataDir = "${cfg.dataRoot}/paperless-gpt";
      docling.dataDir = "${cfg.dataRoot}/docling";
      secretFiles.host = cfg.secretFiles.host;
    };
  };
}
