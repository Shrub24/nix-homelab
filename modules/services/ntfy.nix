{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.services.ntfy;
  ntfyRoute = config.repo.web.currentHost.services."ntfy-admin" or { };
  listenAddress = "${ntfyRoute.origin.host}:${toString ntfyRoute.origin.port}";
  publicBaseUrl = ntfyRoute.publicUrl;

  dataDir = cfg.dataDir;

  validRoles = [
    "admin"
    "user"
    "none"
  ];

  # ntfy auth-users entries are `<username>:<bcrypt-hash>:<role>`; even
  # token-only accounts need a real `ntfy user hash` (username::role is
  # invalid). A documented non-secret `<...>` placeholder is accepted so hosts
  # can declare user/role in plaintext while the hash stays in the encrypted
  # auth file.
  isValidAuthUserHash =
    hash: lib.hasPrefix "$2" hash || (lib.hasPrefix "<" hash && lib.hasSuffix ">" hash);

  isValidAuthUser =
    entry:
    let
      parts = lib.splitString ":" entry;
    in
    lib.length parts == 3
    && lib.elemAt parts 0 != ""
    && isValidAuthUserHash (lib.elemAt parts 1)
    && lib.elem (lib.elemAt parts 2) validRoles;
in
{
  options.services.ntfy = {
    enable = lib.mkEnableOption "ntfy push notification server" // {
      default = false;
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/data/ntfy";
      description = "Base data directory for ntfy state (cache, attachments, auth DB).";
    };

    secretFiles = {
      firebase = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = ../../secrets/services/firebase-key.json;
        description = ''
          Path to SOPS-encrypted Firebase Admin SDK key JSON file.
        '';
      };
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "INFO"
        "DEBUG"
        "TRACE"
        "WARN"
        "ERROR"
      ];
      default = "INFO";
      description = "ntfy log level. Set to DEBUG or TRACE for verbose request logging.";
    };

    auth = {
      enable = lib.mkEnableOption "ntfy authentication and access control" // {
        default = true;
      };

      file = lib.mkOption {
        type = lib.types.path;
        default = "${dataDir}/auth.db";
        description = "Path to the ntfy auth database (SQLite). Created automatically if absent.";
      };

      defaultAccess = lib.mkOption {
        type = lib.types.enum [
          "read-write"
          "read-only"
          "write-only"
          "deny-all"
        ];
        default = "deny-all";
        description = "Default access policy when no ACL entry matches.";
      };

      access = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "service:*:write-only" ];
        description = ''
          Declarative ACL entries in <user>:<topic>:<permission> format.
        '';
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "oci-melb-1:<disposable bcrypt hash from ntfy user hash>:user"
        ];
        description = ''
          Non-secret declaration of the ntfy auth-users entries the encrypted
          auth secret file must provision, in ntfy's documented
          `<username>:<bcrypt-hash>:<role>` shape. The bcrypt hashes and access
          tokens themselves stay in `auth.secretFiles.auth`; hashes declared
          here must be a real bcrypt hash from `ntfy user hash` or a documented
          `<...>` placeholder. Every entry is validated at evaluation time when
          auth is enabled.
        '';
      };

      validateAuthUser = lib.mkOption {
        type = lib.types.functionTo lib.types.bool;
        default = isValidAuthUser;
        readOnly = true;
        description = ''
          Pure validation function for a single ntfy `auth-users` entry.
          Exposed as an option so contract tests can exercise the same shape
          checks that guard `auth.users` without reading any encrypted secret.
          Accepts only `<username>:<bcrypt-hash|<...>>:<role>` entries.
        '';
      };

      secretFiles.auth = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = ../../secrets/services/ntfy.yaml;
        description = ''
          SOPS-encrypted YAML file containing auth-users and auth-tokens
          as top-level keys. Decrypted as a single blob and merged into
          the ntfy config via yq at service start.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Shared across both paths: tmpfiles, mount dependency
      {
        users.users.ntfy-sh = {
          isSystemUser = true;
          group = "ntfy-sh";
          description = "ntfy push notification server";
        };
        users.groups.ntfy-sh = { };

        systemd.tmpfiles.rules = [
          "d ${dataDir} 0750 ntfy-sh ntfy-sh - -"
          "d ${dataDir}/attachments 0750 ntfy-sh ntfy-sh - -"
        ];

        systemd.services.ntfy-sh = {
          unitConfig.RequiresMountsFor = [ dataDir ];
          serviceConfig = {
            DynamicUser = lib.mkForce false;
            User = "ntfy-sh";
            Group = "ntfy-sh";
            StateDirectory = lib.mkForce "";
            RuntimeDirectory = "ntfy-sh";
            RuntimeDirectoryMode = "0755";
            ReadWritePaths = [ dataDir ];
          };
        };
      }

      # Path B: Auth enabled — module settings for upstream deps, template for full config
      (lib.mkIf cfg.auth.enable {
        assertions =
          lib.optional (cfg.auth.file == null) {
            assertion = false;
            message = "services.ntfy.auth.file must be set when auth is enabled.";
          }
          ++ lib.optional (cfg.auth.secretFiles.auth == null) {
            assertion = false;
            message = "services.ntfy.auth.secretFiles.auth must be set when auth is enabled.";
          }
          ++ lib.optionals (cfg.auth.users != [ ]) (
            map (entry: {
              assertion = isValidAuthUser entry;
              message = "services.ntfy.auth.users entry '${entry}' must be '<username>:<bcrypt-hash|<...>>:<role>' with a nonempty username, a bcrypt hash from `ntfy user hash` (or <...> placeholder), and a role in ${builtins.toString validRoles}.";
            }) cfg.auth.users
          );

        services.ntfy-sh = {
          enable = true;
          settings = {
            base-url = publicBaseUrl;
          };
        };

        sops.secrets."ntfy/auth" = {
          sopsFile = cfg.auth.secretFiles.auth;
          key = "";
          path = "/run/secrets/ntfy/auth.yml";
          owner = "ntfy-sh";
          group = "ntfy-sh";
          mode = "0400";
        };

        sops.templates."ntfy-base-config" = {
          content = ''
            base-url: ${publicBaseUrl}
            behind-proxy: true
            proxy-forwarded-header: X-Forwarded-For
            listen-http: ${listenAddress}
            cache-file: ${dataDir}/cache.db
            attachment-cache-dir: ${dataDir}/attachments
            enable-login: true
            enable-signup: false
            auth-file: ${toString cfg.auth.file}
            auth-default-access: ${cfg.auth.defaultAccess}
            auth-access: ${builtins.toJSON cfg.auth.access}
          ''
          + lib.optionalString (cfg.secretFiles.firebase != null) ''
            firebase-key-file: /run/secrets/ntfy/firebase-key.json
          '';
          owner = "ntfy-sh";
          group = "ntfy-sh";
          mode = "0440";
        };

        systemd.services.ntfy-sh = {
          restartTriggers = [
            config.sops.templates."ntfy-base-config".path
          ]
          ++ lib.optionals (cfg.auth.secretFiles.auth != null) [
            cfg.auth.secretFiles.auth
          ]
          ++ lib.optionals (cfg.secretFiles.firebase != null) [
            cfg.secretFiles.firebase
          ];
          preStart = ''
            tmp=$(mktemp) && trap 'rm -f "$tmp"' EXIT
            ${pkgs.yq-go}/bin/yq eval-all '. as $item ireduce ({}; . * $item)' \
              ${config.sops.templates."ntfy-base-config".path} \
              /run/secrets/ntfy/auth.yml \
              > "$tmp"
            install -m 0440 "$tmp" /run/ntfy-sh/server.yml
          '';
          serviceConfig.ExecStart = lib.mkForce [
            ""
            "${pkgs.ntfy-sh}/bin/ntfy serve -c /run/ntfy-sh/server.yml --log-level ${cfg.logLevel}"
          ];
        };
      })

      # Firebase FCM key (shared across both paths)
      (lib.mkIf (cfg.secretFiles.firebase != null) {
        sops.secrets."ntfy-firebase-key" = {
          sopsFile = cfg.secretFiles.firebase;
          format = "json";
          key = "";
          path = "/run/secrets/ntfy/firebase-key.json";
          owner = "ntfy-sh";
          group = "ntfy-sh";
          mode = "0400";
        };
      })
    ]
  );
}
