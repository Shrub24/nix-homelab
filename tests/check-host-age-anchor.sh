#!/usr/bin/env bash
set -euo pipefail
# Regression: `just host-age from-key ... update=true` must fail closed. The
# anchor replacement (scripts/update-age-anchor.py) requires exactly one
# matching &<alias> age anchor and a well-formed recipient; anything else
# exits nonzero and never writes the file. All fixtures are temporary; nothing
# is decrypted and no real SOPS file is touched.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/update-age-anchor.py"

fail() {
  echo "check-host-age-anchor: $*" >&2
  exit 1
}

NEW_RECIPIENT="age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
OLD_RECIPIENT="age1w5asfm5rfncy4yvslj3az78kvn7hkrzq4vy0mzexf36w64a7e3nqamw3fp"
OTHER_RECIPIENT="age1a2masnj7tmwjl9azt75kh387lvwwz9vqfhqr0emghdcvu7x9jd9q4wv4aq"

fixture() {
  cat <<EOF
creation_rules:
  - path_regex: secrets/common/.*
    key_groups:
      - age:
          - &owner_age $OLD_RECIPIENT
          - &oci_melb_1_age $OTHER_RECIPIENT
  - path_regex: secrets/hosts/la-admin-1/.*
    key_groups:
      - age:
          - &la_admin_1_age $OLD_RECIPIENT
EOF
}

# Expect success: exactly one anchor replaced, neighbours untouched.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fixture >"$TMP/sops.yaml"
python3 "$SCRIPT" "$TMP/sops.yaml" la_admin_1_age "$NEW_RECIPIENT" >/dev/null
grep -q -- "&la_admin_1_age $NEW_RECIPIENT" "$TMP/sops.yaml" ||
  fail "success case did not update the target anchor"
grep -q -- "&owner_age $OLD_RECIPIENT" "$TMP/sops.yaml" ||
  fail "success case mutated an unrelated anchor"
grep -q -- "&oci_melb_1_age $OTHER_RECIPIENT" "$TMP/sops.yaml" ||
  fail "success case mutated an unrelated anchor"

# Expect failure: missing alias leaves the file untouched.
fixture >"$TMP/sops.yaml"
if python3 "$SCRIPT" "$TMP/sops.yaml" missing_alias "$NEW_RECIPIENT" >/dev/null 2>&1; then
  fail "missing alias unexpectedly succeeded"
fi
grep -q -- "&la_admin_1_age $OLD_RECIPIENT" "$TMP/sops.yaml" ||
  fail "missing alias modified the fixture"

# Expect failure: duplicate anchors (zero-length recipient pool) leave file untouched.
fixture >"$TMP/sops.yaml"
printf '  - &dup_age %s\n  - &dup_age %s\n' "$OLD_RECIPIENT" "$OTHER_RECIPIENT" >>"$TMP/sops.yaml"
if python3 "$SCRIPT" "$TMP/sops.yaml" dup_age "$NEW_RECIPIENT" >/dev/null 2>&1; then
  fail "duplicate anchors unexpectedly succeeded"
fi
grep -q -- "&dup_age $OLD_RECIPIENT" "$TMP/sops.yaml" ||
  fail "duplicate anchors modified the fixture"

# Expect failure: malformed/non-age recipient leaves file untouched.
fixture >"$TMP/sops.yaml"
if python3 "$SCRIPT" "$TMP/sops.yaml" la_admin_1_age "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA" >/dev/null 2>&1; then
  fail "non-age recipient unexpectedly succeeded"
fi
if python3 "$SCRIPT" "$TMP/sops.yaml" la_admin_1_age "age1SHOUTINGINVALID" >/dev/null 2>&1; then
  fail "uppercase recipient unexpectedly succeeded"
fi
grep -q -- "&la_admin_1_age $OLD_RECIPIENT" "$TMP/sops.yaml" ||
  fail "invalid recipient modified the fixture"

# Expect failure: no-op rewrite (same recipient) is rejected, file untouched.
fixture >"$TMP/sops.yaml"
if python3 "$SCRIPT" "$TMP/sops.yaml" la_admin_1_age "$OLD_RECIPIENT" >/dev/null 2>&1; then
  fail "unchanged recipient unexpectedly succeeded"
fi
grep -q -- "&la_admin_1_age $OLD_RECIPIENT" "$TMP/sops.yaml" ||
  fail "unchanged recipient modified the fixture"

echo "check-host-age-anchor: PASS"
