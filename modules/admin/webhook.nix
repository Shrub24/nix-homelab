# Webhook deployment aspect: the leaf consumes no web policy, secret source, or
# runtime path; the `webhook-admin` policy route serves external callers only.
_: {
  flake.modules.nixos.webhook =
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
      options.services.admin.webhook.enable = lib.mkEnableOption "the Webhook service wiring";
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
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
        })
        { services.admin.webhook.enable = true; }
      ];
    };
}
