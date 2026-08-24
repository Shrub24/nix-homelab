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

# The host assembly must not import destructive install/provider/static-network
# inputs; the source check is feasible here because these imports would be
# written by hand and never enter LA host declarations.
LA_ASSEMBLY="hosts/la-admin-1/default.nix"
if grep -Eq 'disko|nixos-anywhere|modules/providers/digitalocean|networking\.(interfaces|defaultGateway|useDHCP|nameservers)' "$LA_ASSEMBLY"; then
  echo "la-admin-1: host assembly must not import disko/provider/static-network configuration" >&2
  exit 1
fi

# Transition: all publisher hosts (oci-melb-1, la-admin-1, home-forge) plus
# admin may publish to LA ntfy. ACL subjects are the bare-hostname publisher
# users declared in the plain-text template (secrets/.templates/services/ntfy.yaml
# is ciphertext-free source); ntfy ACLs match user names, and publish auth
# resolves to the user that owns the token. The transition contract pins
# exactly three write-only publishers.
TEMPLATE="secrets/.templates/services/ntfy.yaml"
TEMPLATE_USERS=$(awk -F'"' '/^auth-users:/{u=1; next} /^auth-tokens:/{u=0} u && /^  - "(oci-melb-1|la-admin-1|home-forge):/{split($2, f, ":"); print f[1]}' "$TEMPLATE")
if [ "$(printf '%s\n' "$TEMPLATE_USERS" | wc -l)" -ne 3 ]; then
  echo "la-admin-1: ntfy template must declare exactly three bare-hostname token users" >&2
  exit 1
fi

# 3.2d: every active template auth-users entry must use ntfy's documented
# `<username>:<bcrypt-hash>:<role>` shape. Reject the legacy empty-hash form
# (`oci-melb-1::user`): ntfy requires a real bcrypt hash even for token-only
# service accounts. The template is plain-text source, so this is
# ciphertext-safe.
if awk -F'"' '
  /^auth-users:/ { u = 1; next }
  /^auth-tokens:/ { u = 0 }
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

# 3.2d: the ntfy module exposes its auth-users entry validator as an option
# attribute (services.ntfy.auth.validateAuthUser). Prove it rejects empty-hash
# (legacy `oci-melb-1::user`), role-less, and short entries while accepting
# valid <...> placeholders and bcrypt hashes — the same checks that guard a
# declarative auth.users option — without reading any encrypted secret.
nix eval --no-write-lock-file --apply '
  v:
    if   (v "oci-melb-1::user") then throw "ntfy validator must reject empty-hash auth-user entries"
    else if (v "saurabhj:<value>") then throw "ntfy validator must reject role-less auth-user entries"
    else if (v "oci-melb-1:user") then throw "ntfy validator must reject short auth-user entries"
    else if !(v "la-admin-1:<disposable bcrypt hash from ntfy user hash>:user") then throw "ntfy validator must accept <...> placeholder auth-user entries"
    else if !(v "saurabhj:$2a$10$abcdefghijklmnopqrstuvwx:admin") then throw "ntfy validator must accept bcrypt auth-user entries"
    else true
' "$LA.services.ntfy.auth.validateAuthUser" >/dev/null

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
