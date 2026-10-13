#!/usr/bin/env bash
set -euo pipefail

# Focused shell-account contract test (migrate-admin-host-to-la task 3.2e).
# Every fleet host must keep the operator/recovery shell split:
#   - dev      -> managed Zsh operator shell, startup file provisioned after
#                 the `users` activation step creates /home/dev (no
#                 zsh-newuser-install on first login)
#   - root     -> minimal interactive Bash, shared recovery keys, no operator
#                 Zsh prompt/plugin/alias configuration
#   - rescue   -> explicit minimal Bash recovery shell
#   - operator aliases live under programs.zsh.shellAliases only, so global
#     environment.shellAliases stays empty (nixpkgs even ships a default `l`)
#   - users.defaultUserShell is NOT overridden to zsh: dev/root/rescue shells
#     are explicit per-user declarations, and any other account inherits the
#     nixpkgs bash default rather than the operator shell
# Attribute-selected evaluation keeps this safe before LA ciphertext exists
# (task 3.3): no secret file is ever read here.

HOSTS="la-admin-1 oci-melb-1"

# The rescue password is a `neededForUsers` secret, so it belongs at sops-nix's
# default under /run/secrets-for-users. A path under /run/secrets is discarded:
# the regular installer swaps that directory for its own generation directory,
# and on the systemd activation path that swap runs after the activation step
# which installs this file — leaving the rescue account's password applied only
# because the users step happens to run first.
check_rescue_pair() { # $1 host, $2 JSON pair
  python3 - "$1" "$2" <<'PYEOF'
import json, sys

host, raw = sys.argv[1], sys.argv[2]
try:
    pair = json.loads(raw)
except Exception:
    print(f"{host}: rescue secret probe did not evaluate", file=sys.stderr)
    sys.exit(1)
path = pair.get("path") or ""
hashed = pair.get("hashedPasswordFile") or ""
if not path or not hashed:
    print(f"{host}: rescue secret path/hashedPasswordFile missing: {pair!r}", file=sys.stderr)
    sys.exit(1)
if not path.startswith("/run/secrets-for-users/"):
    print(
        f"{host}: a neededForUsers secret must live under /run/secrets-for-users "
        f"(the /run/secrets directory is swapped for the installer's own generation), got {path}",
        file=sys.stderr,
    )
    sys.exit(1)
if hashed != path:
    print(f"{host}: hashedPasswordFile must read the secret's path, got {hashed!r} != {path!r}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

for host in $HOSTS; do
  cfg="path:.#nixosConfigurations.$host.config"

  dev_shell="$(nix eval --no-write-lock-file --raw "$cfg.users.users.dev.shell.name")"
  case "$dev_shell" in
    zsh-*) ;;
    *) echo "$host: dev shell must resolve to zsh, got $dev_shell" >&2; exit 1 ;;
  esac

  root_shell="$(nix eval --no-write-lock-file --raw "$cfg.users.users.root.shell.name")"
  case "$root_shell" in
    bash-interactive-*) ;;
    *) echo "$host: root shell must resolve to bash, got $root_shell" >&2; exit 1 ;;
  esac

  rescue_shell="$(nix eval --no-write-lock-file --raw "$cfg.users.users.rescue.shell")"
  case "$rescue_shell" in
    */bin/bash) ;;
    *) echo "$host: rescue shell must resolve to bash, got $rescue_shell" >&2; exit 1 ;;
  esac

  default_shell="$(nix eval --no-write-lock-file --raw "$cfg.users.defaultUserShell.name")"
  case "$default_shell" in
    zsh-*) echo "$host: users.defaultUserShell must not be zsh (per-user shells are explicit), got $default_shell" >&2; exit 1 ;;
    *) ;;
  esac

  deps="$(nix eval --no-write-lock-file --json "$cfg.system.activationScripts.dev-zshrc.deps")"
  if ! echo "$deps" | python3 -c 'import json, sys; sys.exit(0 if "users" in json.load(sys.stdin) else 1)'; then
    echo "$host: dev-zshrc must depend on the users activation step, got deps=$deps" >&2
    exit 1
  fi

  dev_keys="$(nix eval --no-write-lock-file --json "$cfg.users.users.dev.openssh.authorizedKeys.keys")"
  root_keys="$(nix eval --no-write-lock-file --json "$cfg.users.users.root.openssh.authorizedKeys.keys")"
  if [ "$dev_keys" != "$root_keys" ]; then
    echo "$host: dev and root must share identical authorized keys" >&2
    exit 1
  fi
  if ! echo "$dev_keys" | python3 -c 'import json, sys; sys.exit(0 if len(json.load(sys.stdin)) > 0 else 1)'; then
    echo "$host: dev/root authorized keys must be nonempty" >&2
    exit 1
  fi

  aliases="$(nix eval --no-write-lock-file --json "$cfg.environment.shellAliases")"
  if [ "$aliases" != "{}" ]; then
    echo "$host: global environment.shellAliases must be empty (operator aliases are Zsh-only), got $aliases" >&2
    exit 1
  fi

  rescue_pair="$(nix eval --no-write-lock-file --json --apply 'c: { path = c.sops.secrets.host_recovery_rescue_password_hash.path or ""; hashedPasswordFile = c.users.users.rescue.hashedPasswordFile or ""; }' "$cfg")"
  check_rescue_pair "$host" "$rescue_pair" || exit 1
  # Control: the checker must reject the path this secret used to carry, or it
  # proves nothing about the invariant.
  if check_rescue_pair "$host" '{"path":"/run/secrets/host-recovery.rescue_password_hash","hashedPasswordFile":"/run/secrets/host-recovery.rescue_password_hash"}' 2>/dev/null; then
    echo "$host: rescue path control did not reject a /run/secrets path" >&2
    exit 1
  fi
done

echo "check-shell-account-contract: PASS"
