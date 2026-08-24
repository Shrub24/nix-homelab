#!/usr/bin/env bash
set -euo pipefail
# Regression: an unexpected mapped host recipient in .sops.yaml must FAIL the
# scope check (not warn). Uses a fixture .sops.yaml with one extra reader; no
# encrypted payloads and no network involved.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/secret-scope.nix" <<'EOF'
{
  "apps/example" = [
    "la-admin-1"
  ];
}
EOF

cat > "$WORK/.sops.yaml" <<'EOF'
keys:
  - &owner_age age1w5asfm5rfncy4yvslj3az78kvn7hkrzq4vy0mzexf36w64a7e3nqamw3fp
  - &oci_melb_1_age age1lg45rhdn6mp856f97sdwxu7rpzyyz7edqwnldnpj67r6curnkqws7nn42a
  - &la_admin_1_age age1placeholderlaadmin00000000000000
creation_rules:
  - path_regex: ^secrets/apps/example\.ya?ml$
    key_groups:
      - age:
          - *owner_age
          - *la_admin_1_age
          - *oci_melb_1_age
EOF

set +e
SOPS_FILE="$WORK/.sops.yaml" SCOPE_FIXTURE="$WORK/secret-scope.nix" \
  "$ROOT/tests/check-secret-scope.sh" >"$WORK/out.log" 2>&1
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  echo "check-secret-scope-extra-reader: check must fail when an unexpected host reader is mapped" >&2
  cat "$WORK/out.log" >&2
  exit 1
fi
grep -q 'oci-melb-1' "$WORK/out.log" ||
  { echo "check-secret-scope-extra-reader: failure output must name the unexpected reader oci-melb-1" >&2; cat "$WORK/out.log" >&2; exit 1; }

echo "check-secret-scope-extra-reader: PASS"
