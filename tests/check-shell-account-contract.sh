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
done

echo "check-shell-account-contract: PASS"
