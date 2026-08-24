#!/usr/bin/env bash
set -euo pipefail
# Regression: the updatekeys recipes must include encrypted JSON files
# (secrets/identity/provisioning.json, secrets/services/ntfy-firebase-key.json)
# while excluding secrets/.templates/. Selection runs through the shared
# scripts/list-sops-files.sh used by both secrets/justfile recipes; nothing is
# decrypted or edited here.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$("$ROOT/scripts/list-sops-files.sh")"

fail() {
  echo "check-secret-updatekeys-selection: $*" >&2
  exit 1
}

# Both known encrypted JSON payloads must be re-encryption targets.
grep -qx 'secrets/identity/provisioning.json' <<<"$out" ||
  fail "secrets/identity/provisioning.json must be selected for updatekeys"
grep -qx 'secrets/services/ntfy-firebase-key.json' <<<"$out" ||
  fail "secrets/services/ntfy-firebase-key.json must be selected for updatekeys"

# Templates are never re-encryption targets.
grep -q '^secrets/.templates/' <<<"$out" &&
  fail "templates must be excluded from updatekeys selection"

# Only SOPS-managed extensions are selected.
bad="$(grep -vE '\.(ya?ml|json)$' <<<"$out" || true)"
[[ -z "$bad" ]] || fail "selection contains non-sops files: $bad"

echo "check-secret-updatekeys-selection: PASS"
