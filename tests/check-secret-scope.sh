#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Overridable for fixture-based regression tests (tests/check-secret-scope-extra-reader.sh).
SOPS_FILE="${SOPS_FILE:-$REPO_ROOT/.sops.yaml}"
SCOPE_FIXTURE="${SCOPE_FIXTURE:-$REPO_ROOT/tests/fixtures/secret-scope.nix}"
TMP=$(mktemp -d)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

SED_ANCHORS="${TMP}/anchors.txt"
grep -oP '&\w+\s+\S+' "$SOPS_FILE" | while read -r line; do
  anchor=$(echo "$line" | awk '{print $1}' | sed 's/^&//')
  age_key=$(echo "$line" | awk '{print $2}')
  echo "$anchor $age_key"
done > "$SED_ANCHORS"

declare -A ANCHOR_TO_HOST
while read -r anchor age_key; do
  case "$anchor" in
    oci_melb_1_age) ANCHOR_TO_HOST[$anchor]="oci-melb-1" ;;
    la_admin_1_age) ANCHOR_TO_HOST[$anchor]="la-admin-1" ;;
    home_forge_age) ANCHOR_TO_HOST[$anchor]="home-forge" ;;
  esac
done < "$SED_ANCHORS"

echo "=== Secret scope validation ==="
echo ""

PASS=0
FAIL=0

# Print the key_groups of the creation rule whose path_regex matches the given
# scope pattern, stopping at the next rule so adjacent rules never bleed in.
# RULE_PAT goes through ENVIRON: awk's -v assignment would process backslashes
# and eat the \\. that mirrors .sops.yaml's escaped path_regex dots.
rule_block_for() {
  RULE_PAT="$1" awk '
    $0 ~ ENVIRON["RULE_PAT"] { in_rule = 1; next }
    in_rule && /^[[:space:]]*- path_regex:/ { in_rule = 0 }
    in_rule { print }
  ' "$SOPS_FILE"
}

while IFS=$'\t' read -r scope expected; do
  echo "[scope] secrets/$scope"
  echo "  expected readers: $expected"

  # .sops.yaml path_regex values escape literal dots (e.g. provisioning\.json),
  # so turn each dot in the scope into \\. (match backslash + dot) when grepping.
  scope_pat=$(printf '%s' "secrets/$scope" | sed 's/\./\\\\./g')

  rule_block="$(rule_block_for "$scope_pat")"
  if [ -z "$rule_block" ]; then
    echo "  ❌  MISSING: no rule found for secrets/$scope"
    FAIL=$((FAIL+1))
    echo ""
    continue
  fi

  IFS=',' read -ra HOSTS <<< "$expected"
  for host in "${HOSTS[@]}"; do
    anchor=""
    case "$host" in
      "oci-melb-1") anchor="oci_melb_1_age" ;;
      "la-admin-1") anchor="la_admin_1_age" ;;
      "home-forge") anchor="home_forge_age" ;;
    esac
    if echo "$rule_block" | grep -q "\*${anchor}"; then
      echo "  ✅ $host"
    else
      echo "  ❌  $host: anchor *${anchor} not found in rule for secrets/$scope"
      FAIL=$((FAIL+1))
    fi
  done

  # Unexpected mapped host recipients are failures, not warnings: adding a host
  # recipient to a scope implicitly widens its blast radius.
  found_anchors="$(echo "$rule_block" | grep -oP '\*\w+_age' | sort -u || true)"
  if [ -n "$found_anchors" ]; then
    while read -r found_anchor; do
      # grep -oP retains the leading '*'; strip it before the map lookup.
      found_host="${ANCHOR_TO_HOST[${found_anchor:1}]:-}"
      if [ -n "$found_host" ] && ! echo "$expected" | grep -q "$found_host"; then
        echo "  ❌  $found_host ($found_anchor) can decrypt secrets/$scope but is not an expected reader"
        FAIL=$((FAIL+1))
      fi
    done <<< "$found_anchors"
  fi

  PASS=$((PASS+1))
  echo ""
done < <(
  nix eval --json --file "$SCOPE_FIXTURE" \
    | python3 -c 'import json, sys; data = json.load(sys.stdin); [print(f"{scope}\t{",".join(readers)}") for scope, readers in data.items()]'
)

echo "=== Result: $PASS scopes checked ==="
if [ "$FAIL" -gt 0 ]; then
  echo "❌  $FAIL FAILURES — update .sops.yaml to match topology"
  exit 1
else
  echo "✅ All checks passed"
fi
