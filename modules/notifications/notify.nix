# Notifications foundation aspect: selecting it is its enablement. nix-fleet owns
# the mechanism — the daemon, the `notify` CLI, the `unit-notify` systemd event
# handler, the `services.notify` option surface and the
# `services.notify.events.<unit>` registration contract that the capability
# owning a unit writes directly. This contributor imports that shared aspect and
# binds the fleet's conventions: the Telegram and ntfy policy from
# policy/globals.nix, the ntfy server URL derived from the web catalog, the ntfy
# topic map, and the fail-closed secret bootstrap.
#
# Secret readership is unchanged in shape and re-pointed in path: the shared
# aspect renders sops.secrets."notify/telegram_bot_token" and
# sops.secrets."notify/ntfy_token" from cfg.secretFiles.host and
# cfg.secretFiles.hostSystem with the conventional keys and ownership, at
# /run/secrets/notify/{telegram_bot_token,ntfy_token}.
#
# The daemon dispatches over /run/notify/notify.sock (mode 0660, group `notify`),
# so non-root callers join that group from the module that owns them
# (`users.users.<caller>.extraGroups`), and `services.notify.cliGroup` stays
# null: root-only socket dispatch plus explicit per-caller grants.
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
            chatId = lib.mkDefault globals.notifications.telegram.chatId;
            topics = lib.mkDefault globals.notifications.telegram.topics;
          };

          ntfy = {
            serverUrl = lib.mkDefault (
              lib.attrByPath [ "repo" "web" "catalog" "ntfy-admin" "publicUrl" ] "" config
            );
            topics = lib.mkDefault {
              system = "system";
              services = "services";
              web = "web";
              music = "music";
            };
          };
        };

        assertions = [
          {
            assertion = cfg.telegram.chatId != "REPLACE_GROUP_CHAT_ID" && cfg.telegram.chatId != "";
            message = "services.notify.telegram.chatId must be set to a real Telegram supergroup chat ID.";
          }
          {
            assertion = cfg.telegram.topics != { };
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
