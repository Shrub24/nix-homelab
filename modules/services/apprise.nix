{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.apprise;
  globals = import ../../policy/globals.nix;
  secretHelpers = import ../../lib/secrets.nix { inherit lib; };

  # Declarative runtime config, read by the daemon at request time.
  notifyConfig = {
    token_file = "/run/secrets/apprise/telegram_bot_token";
    chat_id = cfg.telegram.chatId;
    topics = cfg.telegram.topics;
  };

  # Build a shell snippet that notifies on service failure with journald context.
  # Used both in the OnFailure template unit and in ExecStopPost hooks.
  mkFailureNotify = name: ''
    journal_errors="$(journalctl -u "${name}" -n 15 --no-pager -p err 2>/dev/null || true)"
    if [ -n "$journal_errors" ]; then
      printf "Last errors:\n%s\n" "$journal_errors" | apprise-notify warning "FAILED: ${name}" warning
    else
      apprise-notify warning "FAILED: ${name}" warning <<<""
    fi
  '';

in
{
  options.services.apprise = {
    enable = lib.mkEnableOption "apprise notification infrastructure";

    secretFiles.host = secretHelpers.mkSecretFileOption "apprise-notifications";

    telegram = {
      chatId = lib.mkOption {
        type = lib.types.str;
        default = globals.notifications.telegram.chatId;
        description = "Telegram supergroup chat ID for notifications.";
      };

      topics = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = globals.notifications.telegram.topics;
        description = "Mapping of notification tiers to Telegram topic IDs within the supergroup.";
      };
    };

    daemon = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run the apprise-webhook FastAPI daemon. When enabled, the daemon
          serves `POST /notify` and `GET /health` on 127.0.0.1:5555.
          The apprise-notify CLI wrapper POSTs to this daemon.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5555;
        description = "Port for the apprise webhook daemon.";
      };
    };

    monitor = {
      enable = lib.mkEnableOption "systemd service lifecycle monitoring via apprise";

      services = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              onStart = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Notify when the service starts.";
              };
              onSuccess = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Notify when the service completes successfully.";
              };
              onFailure = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Notify when the service fails (includes journald context).";
              };
            };
          }
        );
        default = { };
        example = {
          "beets-import" = {
            onStart = true;
            onFailure = true;
            onSuccess = true;
          };
          "nix-gc" = {
            onFailure = true;
          };
          "podman-cleanup" = {
            onFailure = true;
          };
        };
        description = "Systemd services to monitor. Each key is a systemd unit name.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        inherit (cfg)
          enable
          ;
        file = cfg.secretFiles.host;
        feature = "services.apprise";
        label = "secretFiles.host";
      })
      {
        assertion = cfg.telegram.chatId != "REPLACE_GROUP_CHAT_ID" && cfg.telegram.chatId != "";
        message = "services.apprise.telegram.chatId must be set to a real Telegram supergroup chat ID.";
      }
      {
        assertion = cfg.telegram.topics != { };
        message = "services.apprise.telegram.topics must be configured with at least one tier.";
      }
    ];

    # JSON config consumed by the daemon at request time.
    environment.etc."apprise/notify.json" = {
      mode = "0444";
      text = builtins.toJSON notifyConfig;
    };

    environment.systemPackages = [
      pkgs.apprise
      # Thin CLI wrapper: POSTs JSON to the daemon.
      (pkgs.writeScriptBin "apprise-notify" ''
        #!${pkgs.python3.interpreter}
        import json
        import sys
        import urllib.request
        import urllib.error

        tier = sys.argv[1] if len(sys.argv) > 1 else "info"
        title = sys.argv[2] if len(sys.argv) > 2 else "Notification"
        ntype = sys.argv[3] if len(sys.argv) > 3 else "info"
        message = sys.argv[4] if len(sys.argv) > 4 else sys.stdin.read().strip()

        payload = json.dumps({
            "tier": tier,
            "title": title,
            "type": ntype,
            "message": message,
        }).encode()

        req = urllib.request.Request(
            "http://127.0.0.1:5555/notify",
            data=payload,
            headers={"Content-Type": "application/json"},
        )
        try:
            resp = urllib.request.urlopen(req)
            sys.exit(0 if resp.status == 200 else 1)
        except urllib.error.HTTPError as e:
            body = e.read().decode()
            print(f"apprise-notify: HTTP {e.code} — {body}", file=sys.stderr)
            sys.exit(1)
        except urllib.error.URLError as e:
            print(f"apprise-notify: connection failed — is the daemon running? ({e.reason})", file=sys.stderr)
            sys.exit(1)
      '')
    ];

    sops.secrets."apprise/telegram_bot_token" = {
      sopsFile = cfg.secretFiles.host;
      key = "telegram_bot_token";
      path = "/run/secrets/apprise/telegram_bot_token";
      owner = "root";
      mode = "0440";
    };

    # ---------------------------------------------------------------------------
    # Monitoring helper: inject lifecycle hooks into systemd services
    # ---------------------------------------------------------------------------
    systemd.services = lib.mkMerge [

      # Apprise webhook daemon (FastAPI)
      (lib.mkIf cfg.daemon.enable {
        apprise-webhook = {
          description = "Apprise notification webhook daemon";
          after = [
            "sops-nix.service"
            "network.target"
          ];
          wants = [ "sops-nix.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${
              self.packages.${pkgs.stdenv.hostPlatform.system}.apprise-webhook
            }/bin/apprise-webhook";
            Restart = "on-failure";
            RestartSec = "5s";
            User = "root";
          };
        };
      })

      # Template unit for OnFailure — triggered when a monitored service crashes.
      # The failing unit name is passed as %i.
      (lib.mkIf cfg.monitor.enable {
        "apprise-monitor@" = {
          description = "Apprise notification on service failure (%i)";
          serviceConfig = {
            Type = "oneshot";
            ExecStart =
              let
                script = pkgs.writeShellScript "apprise-monitor" ''
                  set -euo pipefail
                  unit="$1"
                  ${mkFailureNotify "$unit"}
                '';
              in
              "${script} %i";
          };
        };
      })

      # Inject hooks into each declared service.
      (lib.mkIf cfg.monitor.enable (
        let
          monitored = lib.filterAttrs (_: o: o.onStart || o.onFailure || o.onSuccess) cfg.monitor.services;
        in
        lib.mapAttrs (name: opts: {
          serviceConfig = lib.mkMerge [

            # OnFailure: triggers the template unit with journald context.
            (lib.mkIf opts.onFailure {
              OnFailure = [ "apprise-monitor@${name}.service" ];
            })

            # onStart: notify when the service starts.
            (lib.mkIf opts.onStart {
              ExecStartPost = lib.mkAfter [
                (
                  let
                    script = pkgs.writeShellScript "notify-start-${name}" ''
                      apprise-notify info "${name} started" info <<<""
                    '';
                  in
                  "${script}"
                )
              ];
            })

            # ExecStopPost: handles both onSuccess and onFailure (runs on every stop).
            # Check $SERVICE_RESULT to determine outcome.
            (lib.mkIf (opts.onSuccess || opts.onFailure) (
              let
                script = pkgs.writeShellScript "notify-stop-${name}" ''
                  set -euo pipefail
                  result="''${SERVICE_RESULT:-}"
                  [ -z "$result" ] && exit 0
                  if [ "$result" = "success" ]; then
                    ${lib.optionalString opts.onSuccess ''
                      apprise-notify info "${name} completed" info <<<""
                    ''}
                  else
                    ${lib.optionalString opts.onFailure ''
                      ${mkFailureNotify name}
                    ''}
                  fi
                '';
              in
              {
                ExecStopPost = lib.mkAfter [ "${script}" ];
              }
            ))

          ];
        }) monitored
      ))
    ];
  };
}
