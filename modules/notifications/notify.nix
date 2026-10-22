# Notifications. nix-fleet owns the mechanism; this binds the fleet's ntfy policy and the
# fail-closed secret bootstrap. Non-root callers join group `notify` from their own module.
{ inputs, ... }:
{
  flake.modules.nixos.notify =
    { config, lib, ... }:
    let
      globals = import ../../policy/globals.nix;
      cfg = config.services.notify;
    in
    {
      imports = [ inputs.nix-fleet.modules.nixos.notify ];

      config = {
        services.notify = {
          telegram = {
            # Bound but off; re-enabling is one line.
            enable = lib.mkDefault false;
            chatId = lib.mkDefault globals.notifications.telegram.chatId;
            topics = lib.mkDefault globals.notifications.telegram.topics;
          };

          ntfy = {
            # The catalog endpoint, not the public hostname: the edge's browser-signature
            # rule rejects the daemon's urllib client.
            serverUrl = lib.mkDefault (
              lib.attrByPath [ "repo" "web" "catalog" "ntfy-admin" "endpoint" "url" ] "" config
            );
            defaultTopic = lib.mkDefault "general";
            topics = lib.mkDefault {
              # The daemon rejects an undeclared topic before it reaches ntfy, and `general`
              # is the fallback for callers that name none.
              general = "general";
              system = "system";
              services = "services";
              web = "web";
              music = "music";
            };
          };
        };

        assertions = [
          {
            assertion =
              !cfg.telegram.enable
              || (cfg.telegram.chatId != "REPLACE_GROUP_CHAT_ID" && cfg.telegram.chatId != "");
            message = "services.notify.telegram.chatId must be set to a real Telegram supergroup chat ID.";
          }
          {
            assertion = !cfg.telegram.enable || cfg.telegram.topics != { };
            message = "services.notify.telegram.topics must be configured with at least one tier.";
          }
          {
            assertion = cfg.secretFiles.host != null;
            message = "services.notify.secretFiles.host must be set to the conventional host-scoped secret file (secrets/services/notification-daemon.yaml).";
          }
        ]
        ++ lib.optional (cfg.ntfy.enable && cfg.ntfy.serverUrl == "") {
          assertion = false;
          message = "services.notify.ntfy.serverUrl must be set when ntfy is enabled.";
        }
        ++ lib.optional (cfg.ntfy.enable && cfg.secretFiles.hostSystem == null) {
          assertion = false;
          message = "services.notify.ntfy.enable is true but services.notify.secretFiles.hostSystem is not set.";
        };
      };
    };
}
