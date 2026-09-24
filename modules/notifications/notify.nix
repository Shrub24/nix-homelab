# Notifications foundation aspect: selecting it is its enablement. nix-fleet owns
# the mechanism — the daemon, the `notify` CLI, the `unit-notify` systemd event
# handler, the `services.notify` option surface and the
# `services.notify.events.<unit>` registration contract that the capability
# owning a unit writes directly. This contributor imports that shared aspect and
# binds the fleet's conventions: the ntfy policy (server URL derived from the web
# catalog, topic map) and the fail-closed secret bootstrap. Telegram is off; ntfy
# is the push path.
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
            # Bound but off; re-enabling is one line.
            enable = lib.mkDefault false;
            chatId = lib.mkDefault globals.notifications.telegram.chatId;
            topics = lib.mkDefault globals.notifications.telegram.topics;
          };

          ntfy = {
            # The machine dial, not the public hostname: the catalog endpoint is
            # loopback on the host that serves ntfy and the provider's tailnet name
            # everywhere else, so a publish never crosses the public edge (whose
            # browser-signature rule rejects the daemon's urllib client).
            serverUrl = lib.mkDefault (
              lib.attrByPath [ "repo" "web" "catalog" "ntfy-admin" "endpoint" "url" ] "" config
            );
            defaultTopic = lib.mkDefault "general";
            topics = lib.mkDefault {
              # `general` is the daemon's fallback for a caller that names no
              # topic — the deploy hook and ad-hoc operator messages — so it has
              # to be declared here: the daemon rejects an undeclared topic
              # before it ever reaches ntfy (observed as a 500 "unknown topic
              # 'general'" while the same publish through the tailnet endpoint
              # returned 200).
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
