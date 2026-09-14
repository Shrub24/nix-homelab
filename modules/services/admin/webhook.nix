# Webhook composition (decoupled from the `applications.admin` namespace in
# decouple-identity-admin-capabilities 3.2): the leaf owns only its own enable
# and mirrors the upstream `services.webhook` service unchanged. It consumes
# no web policy, secret source, or runtime path; the retained `webhook-admin`
# policy route serves external/manual callers only and has no in-repo poster.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.admin.webhook;
in
{
  options.services.admin.webhook.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable admin-owned Webhook service wiring.";
  };

  config = lib.mkIf cfg.enable {
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
