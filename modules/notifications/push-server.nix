# ntfy server. Publisher authorization is fleet policy: `auth-access` is derived here while
# the credentials stay in the encrypted auth file, which must not carry `auth-access` itself.

# Flake-level because the policy is shared; the aspect passes the map in by value.
{ ... }:
let
  publishers = {
    "oci-melb-1" = "write-only";
    "la-admin-1" = "write-only";
    "home-forge" = "write-only";
    "legion" = "read-write";
    "spectre" = "read-write";
  };

in
{
  flake.modules.nixos.push-server =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.services.ntfy;
      ntfyRoute = config.repo.web.catalog."ntfy-admin" or { };
      listenAddress = "0.0.0.0:${toString ntfyRoute.upstreamPort}";
      publicBaseUrl = ntfyRoute.publicUrl;

      inherit (cfg) dataDir;

      validRoles = [
        "admin"
        "user"
        "none"
      ];

      # Even token-only accounts need a real hash (`user::role` is invalid); this is the role half of the check.
      rolePattern = "^(${lib.concatStringsSep "|" validRoles})$";

      publisherNames = builtins.attrNames cfg.auth.publishers;
      invalidPublisherNames = lib.filter (
        name: builtins.match "^[A-Za-z0-9][A-Za-z0-9_.-]*$" name == null
      ) publisherNames;
      publisherAccessEntries = lib.mapAttrsToList (
        user: permission: "${user}:*:${permission}"
      ) cfg.auth.publishers;
    in
    {

      options.services.ntfy = {
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

          publishers = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.enum [
                "write-only"
                "read-only"
                "read-write"
              ]
            );
            default = { };
            example = {
              "service" = "write-only";
            };
            description = ''
              Publish-enabled ntfy principals, keyed by username and mapped to
              their topic-wide ACL permission. A principal may be a managed host,
              a host from another fleet repository, a CLI, or a script. The module
              renders these into `auth-access` as `<user>:*:<permission>` entries;
              the matching `auth-users`/`auth-tokens` credentials stay in
              `auth.secretFiles.auth`. Activation fails if a declared publisher
              has no corresponding user and token credential.
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
      config = lib.mkMerge [
        (lib.mkMerge [
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
              ++ lib.optional (invalidPublisherNames != [ ]) {
                assertion = false;
                message =
                  "services.ntfy.auth.publishers contains invalid ntfy usernames: "
                  + builtins.concatStringsSep ", " invalidPublisherNames;
              };

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
                auth-access: ${builtins.toJSON publisherAccessEntries}
              ''
              + lib.optionalString (cfg.secretFiles.firebase != null) ''
                firebase-key-file: /run/secrets/ntfy/firebase-key.json
              '';
              owner = "ntfy-sh";
              group = "ntfy-sh";
              mode = "0440";
            };

            systemd.services.ntfy-sh = {
              # PATH, not baked store paths, so the contract suite can run this against fixtures.
              # yq here is mikefarah's yq-go, not the jq-syntax wrapper.
              path = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.yq-go
              ];
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
                base_config=${config.sops.templates."ntfy-base-config".path}
                auth_config=/run/secrets/ntfy/auth.yml

                # Either spelling is valid; declaring both would let ntfy's loader pick one silently.
                if [ "$(yq -r 'has("auth-users") and has("auth_users")' "$auth_config")" = true ] \
                  || [ "$(yq -r 'has("auth-tokens") and has("auth_tokens")' "$auth_config")" = true ]; then
                  echo "ntfy: the auth secret file must use one spelling per key (auth-users or auth_users, auth-tokens or auth_tokens), not both" >&2
                  exit 1
                fi

                # auth-access is policy-owned; the encrypted file carries only
                # credentials. Reject the ownership error instead of masking it.
                if [ "$(yq -r 'has("auth-access") or has("auth_access")' "$auth_config")" = true ]; then
                  echo "ntfy: auth-access must be owned by push-server policy, not the auth secret file" >&2
                  exit 1
                fi

                # auth-users entries must be `<username>:<bcrypt-hash>:<role>`;
                # ntfy rejects empty-hash entries even for token-only accounts.
                bad_users="$(yq -r '(.["auth-users"] // .auth_users // [])[] | select((split(":") | length) != 3 or (split(":")[1] | length) == 0 or (split(":")[2] | test("${rolePattern}") | not))' "$auth_config")"
                if [ -n "$bad_users" ]; then
                  echo "ntfy: auth-users entries must be <username>:<bcrypt-hash>:<role>; offending: $bad_users" >&2
                  exit 1
                fi

                # Missing publishers are fatal; extra users are allowed.
                users="$(yq -r '(.["auth-users"] // .auth_users // [])[] | split(":")[0]' "$auth_config")"
                tokens="$(yq -r '(.["auth-tokens"] // .auth_tokens // [])[] | split(":")[0]' "$auth_config")"
                for publisher in ${lib.concatStringsSep " " publisherNames}; do
                  if ! printf '%s\n' "$users" | grep -Fqx "$publisher"; then
                    echo "ntfy: publisher '$publisher' has no auth-users credential" >&2
                    exit 1
                  fi
                  if ! printf '%s\n' "$tokens" | grep -Fqx "$publisher"; then
                    echo "ntfy: publisher '$publisher' has no auth-tokens credential" >&2
                    exit 1
                  fi
                done

                # Merge the credentials, then the policy again: the rendered
                # auth-access is this module's map regardless of the secret file.
                yq eval-all '. as $item ireduce ({}; . * $item)' \
                  "$base_config" "$auth_config" "$base_config" > "$tmp"
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
        ])
        {

          services.ntfy.auth.publishers = publishers;
        }
      ];
    };
}
