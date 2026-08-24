#!/usr/bin/env bash
set -euo pipefail
# Regression (migrate-admin-host-to-la task 3.2e): deploy.sh must not fall back
# to any default host config. A direct invocation without --host-config must
# fail on the required-config gate before any nix evaluation or network work,
# and an explicit --host-config path (or its prefixed host_config=<path> value
# form) must pass argument validation and reach the config-file check. A poisoned
# `nix` on PATH proves no evaluation runs before the gate; nothing here touches
# a real host and no fake config file is created.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/deploy.sh"

fail() {
  echo "check-deploy-bootstrap-gate: $*" >&2
  exit 1
}

# Poison PATH: any nix evaluation/run attempted before the gate fails loudly.
FAKE="$(mktemp -d)"
trap 'rm -rf "$FAKE"' EXIT
cat >"$FAKE/nix" <<'EOF'
#!/usr/bin/env bash
echo "check-deploy-bootstrap-gate: deploy.sh invoked nix before the --host-config gate" >&2
exit 90
EOF
chmod +x "$FAKE/nix"
PATH="$FAKE:$PATH"
export PATH

# Direct no-config invocation must fail with the gate error before any work.
set +e
OUT="$("$DEPLOY" 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  fail "no-config invocation unexpectedly succeeded"
fi
if ! echo "$OUT" | grep -Fq -- "--host-config is required"; then
  fail "no-config invocation did not fail on the --host-config gate; got: $OUT"
fi

# An explicit --host-config path passes argument validation and reaches the
# config-file check (the next error is "not found", never the gate, and no nix
# evaluation or network work runs).
set +e
OUT="$("$DEPLOY" --host-config "$FAKE/no-such-config.nix" 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  fail "explicit --host-config invocation unexpectedly succeeded"
fi
if ! echo "$OUT" | grep -Fq -- "bootstrap config not found: $FAKE/no-such-config.nix"; then
  fail "explicit --host-config did not pass argument validation; got: $OUT"
fi

# The prefixed host_config=<path> value form (passed through --host-config)
# normalizes the same way.
set +e
OUT="$("$DEPLOY" --host-config "host_config=$FAKE/no-such-config.nix" 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  fail "prefixed host_config invocation unexpectedly succeeded"
fi
if ! echo "$OUT" | grep -Fq -- "bootstrap config not found: $FAKE/no-such-config.nix"; then
  fail "prefixed host_config did not pass argument validation; got: $OUT"
fi

echo "check-deploy-bootstrap-gate: PASS"
