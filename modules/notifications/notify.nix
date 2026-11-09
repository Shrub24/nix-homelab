# Notifications. nix-fleet owns the mechanism; this binds the fleet's ntfy policy and the
# fail-closed secret bootstrap. Non-root callers join group `notify` from their own module.
{ inputs, ... }:
{
  flake.modules.nixos.notify =
    { config, lib, ... }:
    let
      globals = import ../../policy/globals.nix;
      cfg = config.services.notify;

      # A failure notification means automatic recovery ended, not that one attempt
      # failed. In its default mode systemd exposes a failed state — and so fires
      # OnFailure= — for every restart attempt, which pages once per retry and lets a
      # crash loop outrun the handler's own start limit. Direct mode keeps the
      # transition internal, still fires the hook when the start limit gives out, and
      # leaves the per-attempt record to the journal and telemetry.
      monitored = lib.attrNames (
        lib.filterAttrs (_: ev: ev.failure != null || ev.success != null) cfg.events
      );

      restarts = unit: (config.systemd.services.${unit}.serviceConfig.Restart or "no") != "no";

      # Five starts an hour, matching the container invariant: systemd's default
      # window is 5 starts per 10 s, which only catches a loop that dies fast — a
      # service failing after 20 s of startup retries for ever, and direct mode would
      # then silence it with no failure to report at all.
      recoveryBudget = {
        interval = "3600";
        burst = "5";
      };

      startLimitDisabled =
        unit:
        let
          value = config.systemd.services.${unit}.unitConfig.StartLimitIntervalSec or null;
        in
        value != null
        && lib.elem (toString value) [
          "0"
          "infinity"
        ];
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

          # The conventional host-scoped file; a host may still override it.
          secretFiles.host = lib.mkDefault ../../secrets/services/notification-daemon.yaml;

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

        systemd.services = lib.genAttrs monitored (unit: {
          serviceConfig.RestartMode = lib.mkDefault "direct";
          # A unit that never restarts has no recovery to bound; bounding it would
          # only refuse a sixth deploy of the same generation.
          unitConfig = lib.mkIf (config.systemd.services ? ${unit} && restarts unit) {
            StartLimitIntervalSec = lib.mkDefault recoveryBudget.interval;
            StartLimitBurst = lib.mkDefault recoveryBudget.burst;
          };
        });

        assertions = [
          {
            # Direct mode reports only the failure that ends the retries. An
            # unlimited window has no such failure, so the unit would restart
            # silently for ever with no notification ever sent.
            assertion = !(lib.any startLimitDisabled monitored);
            message = "notify: ${lib.concatStringsSep ", " (lib.filter startLimitDisabled monitored)} disables its start limit while registered for notification, so automatic recovery never fails and the failure event would never fire. Leave the limit finite (it bounds the retries a notification reports) or unregister the unit.";
          }
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
