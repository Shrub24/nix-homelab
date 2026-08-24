{
  lib,
  config,
  pkgs,
  ...
}:
let
  appCfg = config.applications.admin;
  cfg = config.services.admin.vaultwarden;
  vaultRoute = appCfg.policyServices."vaultwarden-admin";
  vaultHost = vaultRoute.origin.host;
  vaultPort = vaultRoute.origin.port;
  secretHelpers = import ../../../lib/secrets.nix { inherit lib; };
in
{
  options.services.admin.vaultwarden = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable admin-owned Vaultwarden service wiring.";
    };

    smtpFrom = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "From address for Vaultwarden emails. Set per-host (e.g. you@gmail.com).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/srv/data/vaultwarden";
      description = "Persistent data directory for Vaultwarden state.";
    };

    backup.exportFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.services.state-backups.stagingRoot}/vaultwarden/db.sqlite3";
      description = "SQLite backup artifact path captured alongside Vaultwarden raw state. Parent directory is created declaratively by services.state-backups under its staging root.";
    };

    secretFiles.host = secretHelpers.mkSecretFileOption "vaultwarden-host-secrets";
  };

  config = lib.mkIf (appCfg.enable && cfg.enable) {
    assertions = [
      (secretHelpers.mkRequiredSecretAssertion {
        enable = cfg.enable;
        file = cfg.secretFiles.host;
        feature = "services.admin.vaultwarden";
        label = "secretFiles.host";
      })
      {
        assertion = cfg.smtpFrom != null;
        message = "services.admin.vaultwarden.smtpFrom must be set (the email Vaultwarden sends from).";
      }
    ];

    sops.templates."vaultwarden.env" = {
      owner = "vaultwarden";
      group = "vaultwarden";
      mode = "0400";
      content = ''
        ADMIN_TOKEN='${config.sops.placeholder.vaultwarden_admin_token}'
        SMTP_USERNAME=${config.sops.placeholder.vaultwarden_smtp_username}
        SMTP_PASSWORD=${config.sops.placeholder.vaultwarden_smtp_password}
        PUSH_INSTALLATION_ID=${config.sops.placeholder.vaultwarden_push_installation_id}
        PUSH_INSTALLATION_KEY=${config.sops.placeholder.vaultwarden_push_installation_key}
      '';
    };

    sops.secrets = secretHelpers.mkSecretsFromMap cfg.secretFiles.host {
      vaultwarden_admin_token = {
        key = "vaultwarden/admin_token";
        path = "/run/secrets/vaultwarden.admin_token";
        owner = "vaultwarden";
        group = "vaultwarden";
      };
      vaultwarden_smtp_username = {
        key = "vaultwarden/smtp_username";
        path = "/run/secrets/vaultwarden.smtp_username";
        owner = "vaultwarden";
        group = "vaultwarden";
      };
      vaultwarden_smtp_password = {
        key = "vaultwarden/smtp_password";
        path = "/run/secrets/vaultwarden.smtp_password";
        owner = "vaultwarden";
        group = "vaultwarden";
      };
      vaultwarden_push_installation_id = {
        key = "vaultwarden/push_installation_id";
        path = "/run/secrets/vaultwarden.push_installation_id";
        owner = "vaultwarden";
        group = "vaultwarden";
      };
      vaultwarden_push_installation_key = {
        key = "vaultwarden/push_installation_key";
        path = "/run/secrets/vaultwarden.push_installation_key";
        owner = "vaultwarden";
        group = "vaultwarden";
      };
    };

    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite";

      config = {
        DATA_FOLDER = cfg.dataDir;
        # ── Domain & reverse proxy ──
        DOMAIN = vaultRoute.publicUrl;
        ROCKET_ADDRESS = vaultHost;
        ROCKET_PORT = vaultPort;
        IP_HEADER = "X-Forwarded-For";

        # ── Access control ──
        SIGNUPS_ALLOWED = false;
        SIGNUPS_VERIFY = true;
        INVITATIONS_ALLOWED = true;
        ORG_CREATION_USERS = "none";

        # ── Features ──
        SENDS_ALLOWED = true;
        WEB_VAULT_ENABLED = true;
        ENABLE_WEBSOCKET = true;
        EXPERIMENTAL_CLIENT_FEATURE_FLAGS = "ssh-key-vault-item,ssh-agent";
        EMERGENCY_ACCESS_ALLOWED = true;

        # ── Push notifications ──
        PUSH_ENABLED = true;

        # ── Security hardening ──
        PASSWORD_ITERATIONS = 600000;
        PASSWORD_HINTS_ALLOWED = true;
        LOGIN_RATELIMIT_SECONDS = 60;
        LOGIN_RATELIMIT_MAX_BURST = 10;
        ADMIN_RATELIMIT_SECONDS = 300;
        ADMIN_RATELIMIT_MAX_BURST = 3;
        ADMIN_SESSION_LIFETIME = 20;

        # ── SMTP (non-secret settings) ──
        SMTP_HOST = "smtp.resend.com";
        SMTP_FROM = cfg.smtpFrom;
        SMTP_FROM_NAME = "Vaultwarden";
        SMTP_PORT = 587;
        SMTP_SECURITY = "starttls";

        # ── Housekeeping ──
        EVENTS_DAYS_RETAIN = 30;
        LOG_LEVEL = "info";
        EXTENDED_LOGGING = true;
        LOG_TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S.%3f";
      };

      environmentFile = config.sops.templates."vaultwarden.env".path;
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 vaultwarden vaultwarden - -"
      "z ${cfg.dataDir} 0750 vaultwarden vaultwarden - -"
      # SQLite export parent: the export prepare command runs in the restic
      # backup unit as root, so the staging dir is root-owned 0700.
      "d ${builtins.dirOf cfg.backup.exportFile} 0700 root root - -"
    ];

    systemd.services.vaultwarden = {
      unitConfig.RequiresMountsFor = [ cfg.dataDir ];
      serviceConfig.ReadWritePaths = [ cfg.dataDir ];
    };

    services.state-backups.services.vaultwarden = {
      enable = true;
      mode = "export";
      paths = [ cfg.dataDir ];
      exportPaths = [ cfg.backup.exportFile ];
      prepareCommands = [
        ''
          tmp_export="${cfg.backup.exportFile}.tmp"
          rm -f "$tmp_export"
          ${pkgs.sqlite}/bin/sqlite3 ${cfg.dataDir}/db.sqlite3 ".backup $tmp_export"
          mv "$tmp_export" ${cfg.backup.exportFile}
        ''
      ];
    };
  };
}
