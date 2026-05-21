{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.notification-daemon;
  globals = import ../../../policy/globals.nix;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };

  # Config JSON written to /etc/notification-daemon/config.json for the daemon to read.
  notifyConfig = {
    token_file = "/run/secrets/notification-daemon/telegram_bot_token";
    chat_id = cfg.telegram.chatId;
    topics = cfg.telegram.topics;
    ntfy = lib.optionalAttrs (cfg.ntfy.enable && cfg.ntfy.serverUrl != "") {
      server_url = cfg.ntfy.serverUrl;
      topics = cfg.ntfy.topics;
      token_file = "/run/secrets/notification-daemon/ntfy_token";
    };
  };

  notifyPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.notify;

  # Python script invoked by systemd OnFailure/ExecStopPost for monitored services.
  monitorScript = pkgs.writeScriptBin "svc-monitor" ''
    #!${pkgs.python3}/bin/python3
    import json, subprocess, sys, urllib.request

    unit = sys.argv[1] if len(sys.argv) > 1 else sys.exit("Usage: svc-monitor <unit>")
    event = sys.argv[2] if len(sys.argv) > 2 else "onFailure"

    journal = subprocess.run(
        ["journalctl", "-u", unit, "--since", "5 minutes ago", "--no-pager", "-n", "50"],
        capture_output=True, text=True, timeout=15,
    ).stdout or ""

    title = "[%s] monitor: %s" % (event, unit)
    body = journal
    tier = "warning" if event == "onFailure" else "info"
    ntype = event

    payload = json.dumps({"tier": tier, "title": title, "type": ntype, "message": body}).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:5555/notify",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except urllib.error.HTTPError as e:
        sys.exit("daemon error: %d %s" % (e.code, e.read().decode()))
    except (urllib.error.URLError, OSError) as e:
        sys.exit("daemon connection failed: %s" % e)
  '';
in
{
  options.services.notification-daemon = {
    enable = lib.mkEnableOption "notification dispatch daemon (Telegram + ntfy)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 5555;
      description = "Port on which the notification daemon listens (127.0.0.1 only).";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.notification-daemon;
      defaultText = lib.literalExpression "self.packages.\${pkgs.stdenv.hostPlatform.system}.notification-daemon";
      description = "The notification-daemon package to use.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "notification-daemon-secrets";

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

    ntfy = {
      enable = lib.mkEnableOption "ntfy dispatch alongside apprise";

      serverUrl = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "ntfy server URL (e.g. https://ntfy.shrublab.xyz).";
      };

      topics = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          system = "system";
          services = "services";
          web = "web";
          music = "music";
        };
        description = "Semantic ntfy topic names (e.g. system, services, web, music).";
      };
    };

    monitor = {
      enable = lib.mkEnableOption "systemd service notification monitors";

      services = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Systemd units to inject notification hooks into.";
      };

      tiers = {
        onStart = lib.mkOption {
          type = lib.types.str;
          default = "info";
        };
        onFailure = lib.mkOption {
          type = lib.types.str;
          default = "warning";
        };
        onSuccess = lib.mkOption {
          type = lib.types.str;
          default = "info";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        inherit (cfg) enable;
        file = cfg.secretFiles.host;
        feature = "services.notification-daemon";
        label = "secretFiles.host";
      })
      {
        assertion = cfg.telegram.chatId != "REPLACE_GROUP_CHAT_ID" && cfg.telegram.chatId != "";
        message = "services.notification-daemon.telegram.chatId must be set to a real Telegram supergroup chat ID.";
      }
      {
        assertion = cfg.telegram.topics != { };
        message = "services.notification-daemon.telegram.topics must be configured with at least one tier.";
      }
    ] ++ lib.optional (cfg.ntfy.enable && cfg.ntfy.serverUrl == "") {
      assertion = false;
      message = "services.notification-daemon.ntfy.serverUrl must be set when ntfy is enabled.";
    };

    environment.etc."notification-daemon/config.json" = {
      mode = "0444";
      text = builtins.toJSON notifyConfig;
    };

    environment.systemPackages = [
      cfg.package
      pkgs.apprise
      notifyPackage
    ] ++ lib.optionals cfg.monitor.enable [ monitorScript ];

    systemd.services = {
      notification-daemon = {
        description = "HTTP notification dispatch daemon";
        after = [ "sops-nix.service" ];
        wants = [ "sops-nix.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/notification-daemon";
          Restart = "on-failure";
          RestartSec = "5s";
          User = "root";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ "/run" ];
          ReadOnlyPaths = [
            "/etc/notification-daemon"
            "/run/secrets"
          ];
        };
      };
    } // lib.optionalAttrs cfg.monitor.enable (
      let
        mon = "svc-monitor@";
        injectOnFailure = name: {
          "${name}".onFailure = lib.mkBefore [ "${mon}${name}.service" ];
        };
        injectExecHooks = name: {
          "${name}" = {
            serviceConfig = {
              ExecStartPost = lib.mkBefore [
                "${monitorScript}/bin/svc-monitor ${name} onStart"
              ];
              ExecStopPost = lib.mkAfter [
                "${monitorScript}/bin/svc-monitor ${name} onSuccess"
              ];
            };
          };
        };
      in
      {
        "${mon}" = {
          description = "Notification monitor for %I";
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${monitorScript}/bin/svc-monitor %I onFailure";
            User = "root";
            Group = "root";
          };
        };
      }
      // builtins.foldl' (acc: name: acc // injectOnFailure name // injectExecHooks name) { } cfg.monitor.services
    );

    sops.secrets."notification-daemon/telegram_bot_token" = {
      sopsFile = cfg.secretFiles.host;
      key = "telegram_bot_token";
      path = "/run/secrets/notification-daemon/telegram_bot_token";
      owner = "root";
      group = "root";
      mode = "0440";
    };

    sops.secrets."notification-daemon/ntfy_token" = lib.mkIf cfg.ntfy.enable {
      sopsFile = cfg.secretFiles.host;
      key = "ntfy_token";
      path = "/run/secrets/notification-daemon/ntfy_token";
      owner = "root";
      group = "root";
      mode = "0440";
    };
  };
}
