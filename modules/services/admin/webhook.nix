{
  lib,
  config,
  pkgs,
  ...
}:
let
  appCfg = config.applications.admin;
  cfg = config.services.admin.webhook;
in
{
  options.services.admin.webhook.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable admin-owned Webhook service wiring.";
  };

  config = lib.mkIf (appCfg.enable && cfg.enable) {
    services.webhook = {
      enable = true;
      ip = "127.0.0.1";
      openFirewall = false;
      hooks = {
        health = {
          execute-command = "${pkgs.coreutils}/bin/true";
          response-message = "ok";
        };
      };
    };
  };
}
