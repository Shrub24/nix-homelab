# ntfy push-server deployment aspect: the ntfy server leaf is the intrinsic
# implementation and selection supplies the top-level enablement. Host-scoped
# variants (Firebase key, auth secret file, and the loopback server URL consumed
# by the notification daemon) stay host-set.
#
# Publisher authorization is fleet policy, not an LA machine fact, so it lives
# here. Publishers are explicit ntfy principals: fleet host daemons, dotfiles
# machines, CLIs, or scripts. The canonical host registry is not the authority.
# The module derives ntfy `auth-access` from this map; the matching
# `auth-users`/`auth-tokens` credentials stay in the encrypted
# `auth.secretFiles.auth`, which must not carry an `auth-access` key of its own.
# The activation preStart validates the decrypted file against this policy: it
# rejects a secret-owned `auth-access` or a malformed `auth-users` entry, and it
# fails by name when a declared publisher has no credential. ntfy's underscore
# key spelling is accepted, but a file declaring both forms of one key is
# rejected because ntfy's loader would silently keep just one of them. Other
# auth users (for example an administrator or a read-only client) may exist
# without being publishers.

# The file-level policy stays at flake-parts level because it is shared
# notification policy, independent of any host's NixOS evaluation. The aspect
# passes the map into the NixOS module by value.
{ ... }:
let
  publishers = {
    "oci-melb-1" = "write-only";
    "la-admin-1" = "write-only";
    "home-forge" = "write-only";
    # Principals outside this repo's host registry (dotfiles machines, CLIs).
    # Not validated against nixos.hosts: a ntfy publisher is a credential
    # holder, not a deployed NixOS configuration.
    "shrub" = "read-write";
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

      # ntfy auth-users entries are `<username>:<bcrypt-hash>:<role>`; even
      # token-only accounts need a real `ntfy user hash` (username::role is
      # invalid). The allowed hashes and roles are enforced against the decrypted
      # file at activation; this list is the role half of that check.
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
        (lib.mkIf cfg.enable (
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
                # The activation validator shells out to yq (mikefarah's yq-go, not
                # the jq-syntax wrapper) and grep. Give the unit a PATH instead of
                # baking store paths into the script, so the same script is
                # runnable out of context (the contract suite executes it against
                # synthetic fixtures).
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

                  # ntfy documents `auth-users`/`auth-tokens` and accepts the
                  # underscore spelling as an alias, so either form is valid here;
                  # declaring both would let ntfy's loader pick one silently.
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

                  # Every declared publisher needs both credential forms in the
                  # encrypted file. Extra users (an administrator, a read-only
                  # client) are allowed; missing publishers are not.
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
          ]
        ))
        {
          services.ntfy.enable = true;

          # Publisher authorization is fleet policy validated against the canonical
          # host records at flake level (the aspect's own let); the map is passed into
          # the module by value.
          services.ntfy.auth.publishers = publishers;
        }
      ];
    };
}
