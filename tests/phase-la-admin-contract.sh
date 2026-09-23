#!/usr/bin/env bash
set -euo pipefail

# Focused LA host contract test. This deliberately avoids forcing full LA
# config evaluation: secrets/hosts/la-admin-1/{system,oidc}.yaml are
# operator-owned ciphertext created in a later task, so only attributes that
# provably do not read them are evaluated (host declarations, options, and the
# kanidm module wiring). Checks here encode independent expectations (forbidden
# imports, template format, an executed validator, CI host-checking wiring)
# rather than restating config literals.

LA='path:.#nixosConfigurations.la-admin-1.config'

fail() {
  echo "$1" >&2
  exit 1
}

# The host assembly must not import destructive install/provider/static-network
# inputs; the source check is feasible here because these imports would be
# written by hand and never enter LA host declarations.
LA_ASSEMBLY="modules/hosts/la-admin-1/_nixos.nix"
if grep -Eq 'disko|nixos-anywhere|networking\.(interfaces|defaultGateway|useDHCP|nameservers)' "$LA_ASSEMBLY"; then
  echo "la-admin-1: host assembly must not import disko/provider/static-network configuration" >&2
  exit 1
fi

# ntfy publisher authorization is policy owned by the push-server aspect:
# `services.ntfy.auth.publishers` maps each ntfy principal (a fleet host, a
# dotfiles machine, a CLI) to its topic-wide permission, and the module renders
# `auth-access` from that map alone. Credentials are secret owned: every policy
# publisher must appear in the plain-text template's `auth-users` and
# `auth-tokens` sections, while extra users (the administrator) are allowed.
# The template is ciphertext-free source, so this check needs no decryption.
TEMPLATE="secrets/.templates/services/ntfy.yaml"
TEMPLATE_USERS=$(awk -F'"' '/^auth-users:|^auth_users:/{u=1; next} /^auth-tokens:|^auth_tokens:/{u=0} u && /^  - "/{split($2, f, ":"); print f[1]}' "$TEMPLATE")
TEMPLATE_TOKENS=$(awk -F'"' '/^auth-tokens:|^auth_tokens:/{t=1; next} t && /^  - "/{split($2, f, ":"); print f[1]}' "$TEMPLATE")
if grep -qE '^auth-access:|^auth_access:' "$TEMPLATE"; then
  echo "la-admin-1: ntfy auth-access is push-server policy; it must not appear in the auth secret template" >&2
  exit 1
fi
# ntfy accepts either spelling but silently keeps just one when both appear, so
# the template must not declare both forms of a key.
if grep -qE '^auth-users:' "$TEMPLATE" && grep -qE '^auth_users:' "$TEMPLATE"; then
  echo "la-admin-1: ntfy template must not declare both auth-users and auth_users" >&2
  exit 1
fi
if grep -qE '^auth-tokens:' "$TEMPLATE" && grep -qE '^auth_tokens:' "$TEMPLATE"; then
  echo "la-admin-1: ntfy template must not declare both auth-tokens and auth_tokens" >&2
  exit 1
fi

# The publisher policy the push-server aspect declares and the publisher
# credentials the encrypted auth file provisions must agree in the direction
# that matters: a publisher declared without credentials is an authorization
# entry no one can use, and a credential removed from one side only is the
# drift this contract exists to catch. The policy is read from the evaluated
# config and the template from plain-text source, so no decryption is needed.
POLICY_PUBLISHERS=$(nix eval --raw --no-write-lock-file --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c.services.ntfy.auth.publishers)' "$LA")
POLICY_GRANTS=$(nix eval --raw --no-write-lock-file --apply 'c: builtins.concatStringsSep "\n" (map (u: u + ":*:" + c.services.ntfy.auth.publishers.${u}) (builtins.attrNames c.services.ntfy.auth.publishers))' "$LA")
missing=""
while IFS= read -r publisher; do
  [ -n "$publisher" ] || continue
  printf '%s\n' "$TEMPLATE_USERS" | grep -Fqx "$publisher" || missing="$missing $publisher:auth-users"
  printf '%s\n' "$TEMPLATE_TOKENS" | grep -Fqx "$publisher" || missing="$missing $publisher:auth-tokens"
done <<< "$POLICY_PUBLISHERS"
if [ -n "$missing" ]; then
  echo "la-admin-1: ntfy publisher policy has no credential in the auth template:$missing" >&2
  exit 1
fi

# 3.2d: every active template auth-users entry must use ntfy's documented
# `<username>:<bcrypt-hash>:<role>` shape. Reject the legacy empty-hash form
# (`oci-melb-1::user`): ntfy requires a real bcrypt hash even for token-only
# service accounts. The template is plain-text source, so this is
# ciphertext-safe.
if awk -F'"' '
  /^auth-users:|^auth_users:/ { u = 1; next }
  /^auth-tokens:|^auth_tokens:/ { u = 0 }
  u && /^  - "/ {
    n = split($2, f, ":")
    if (n != 3 || length(f[1]) == 0 || length(f[2]) == 0 || length(f[3]) == 0) {
      print "ntfy template auth-users entry '"'"'" $2 "'"'"' must be username:bcrypt-hash:role with a nonempty hash" > "/dev/stderr"
      bad = 1
    }
  }
  END { exit bad }
' "$TEMPLATE"; then
  :
else
  echo "la-admin-1: ntfy template auth-users entries must use username:<bcrypt-hash>:role (see secrets/.templates/services/ntfy.yaml)" >&2
  exit 1
fi

# 3.2d: the publisher contract has a runtime half. The rendered activation
# validator must reject a decrypted auth file that carries auth-access (policy
# owned), that is missing a credential for a declared publisher, or that holds a
# malformed auth-users entry, and must accept a complete file and render
# auth-access from policy. Exercised against synthetic plaintext fixtures, so no
# ciphertext is read.
PRESTART=$(nix eval --raw --no-write-lock-file "$LA.systemd.services.ntfy-sh.preStart")
# The validator resolves its tools from PATH, which systemd supplies from the
# unit's own `path`. Provide that same PATH here, so the suite is independent of
# the caller's environment (CI runs it inside the devShell, a developer may not,
# and the ambient yq is not necessarily mikefarah's).
VALIDATOR_PATH=$(nix eval --raw --no-write-lock-file \
  --apply 'ps: builtins.concatStringsSep ":" (map (p: "${toString p}/bin") ps)' \
  "$LA.systemd.services.ntfy-sh.path")
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT
printf 'base-url: https://ntfy.example.invalid\n' > "$fixture_dir/base.yml"
{
  printf 'auth-access: ['
  first_grant=1
  while IFS= read -r grant; do
    [ -n "$grant" ] || continue
    [ "$first_grant" -eq 1 ] || printf ','
    printf '"%s"' "$grant"
    first_grant=0
  done <<< "$POLICY_GRANTS"
  printf ']\n'
} >> "$fixture_dir/base.yml"
{
  echo 'auth-users:'
  while IFS= read -r publisher; do
    [ -n "$publisher" ] || continue
    printf '  - "%s:$2a$10$fixturehash:user"\n' "$publisher"
  done <<< "$POLICY_PUBLISHERS"
  echo 'auth-tokens:'
  while IFS= read -r publisher; do
    [ -n "$publisher" ] || continue
    printf '  - "%s:tk_fixture"\n' "$publisher"
  done <<< "$POLICY_PUBLISHERS"
} > "$fixture_dir/complete.yml"
cp "$fixture_dir/complete.yml" "$fixture_dir/leaky.yml"
printf 'auth-access:\n  - "rogue:*:read-write"\n' >> "$fixture_dir/leaky.yml"
sed 's|^auth-users:$|auth_users:|; s|^auth-tokens:$|auth_tokens:|' "$fixture_dir/complete.yml" > "$fixture_dir/underscore.yml"
cp "$fixture_dir/complete.yml" "$fixture_dir/mixed.yml"
printf 'auth_users:\n  - "extra:$2a$10$fixturehash:user"\n' >> "$fixture_dir/mixed.yml"
sed 's|^auth-users:$|auth-users:\n  - "broken::user"|' "$fixture_dir/complete.yml" > "$fixture_dir/malformed.yml"
first_publisher=$(printf '%s\n' "$POLICY_PUBLISHERS" | head -n 1)
awk -v p="$first_publisher" '$0 !~ ("^  - \"" p ":")' "$fixture_dir/complete.yml" > "$fixture_dir/missing.yml"
run_validator() {
  sed \
    -e "s|^base_config=.*|base_config=$fixture_dir/base.yml|" \
    -e "s|^auth_config=.*|auth_config=$1|" \
    -e "s|^install -m 0440 \"\$tmp\" /run/ntfy-sh/server.yml|install -m 0444 \"\$tmp\" $fixture_dir/server.yml|" \
    <<< "$PRESTART" > "$fixture_dir/validator.sh"
  PATH="$VALIDATOR_PATH:$PATH" bash "$fixture_dir/validator.sh"
}
run_validator "$fixture_dir/complete.yml" > "$fixture_dir/complete.log" 2>&1 \
  || fail "runtime validator must accept a complete auth file: $(tail -n 2 "$fixture_dir/complete.log")"
# ntfy documents the hyphen spelling and accepts underscores; a file written
# either way must validate, because the operator picks one and ntfy honours it.
run_validator "$fixture_dir/underscore.yml" > "$fixture_dir/underscore.log" 2>&1 \
  || fail "runtime validator must accept the underscore key spelling: $(tail -n 2 "$fixture_dir/underscore.log")"
while IFS= read -r grant; do
  [ -n "$grant" ] || continue
  grep -Fq "\"$grant\"" "$fixture_dir/server.yml" \
    || fail "runtime validator must render policy auth-access entry '$grant'"
done <<< "$POLICY_GRANTS"
for case_name in leaky malformed missing mixed; do
  if run_validator "$fixture_dir/$case_name.yml" > "$fixture_dir/$case_name.log" 2>&1; then
    fail "runtime validator must reject the $case_name auth file"
  fi
  grep -q '^ntfy: ' "$fixture_dir/$case_name.log" \
    || fail "runtime validator must fail '$case_name' with a named ntfy error"
done

# CI must configure strict known_hosts/StrictHostKeyChecking via an ephemeral
# ~/.ssh/config Host entry rather than passing a CLI ssh-opts override; host
# checking is never disabled or auto-accepted.
CI_WF=".github/workflows/deploy-host.yml"
if grep -q -- '--ssh-opts' "$CI_WF" \
  || ! grep -q 'StrictHostKeyChecking yes' "$CI_WF" \
  || ! grep -q '~/.ssh/config' "$CI_WF"; then
  echo "la-admin-1: CI must not pass --ssh-opts and must route known_hosts/strict checking via ~/.ssh/config" >&2
  exit 1
fi

echo "phase-la-admin-contract: PASS"
