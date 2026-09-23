#!/usr/bin/env bash
set -euo pipefail
# Regression (migrate-admin-host-to-la task 3.2e; refined by
# dendritic-stage-1-scaffold-hosts task 6.3/6.4): deploy.sh must not fall back
# to any default host config. A bare invocation without required registry
# values must fail on the required-config gate before any nix evaluation or
# network work, and the --host-config machinery must be fully removed. A
# poisoned `nix` on PATH proves no evaluation runs before the gate; nothing
# here touches a real host.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY="$ROOT/deploy.sh"

fail() {
  echo "check-deploy-bootstrap-gate: $*" >&2
  exit 1
}

# The --host-config machinery is fully removed (task 6.3): no flag, no
# host_config= value form, no source-file gate.
if grep -n -- '--host-config' "$DEPLOY"; then
  fail "deploy.sh must no longer accept --host-config"
fi
if grep -n -- 'host_config=' "$DEPLOY"; then
  fail "deploy.sh must no longer accept the host_config= value form"
fi

# Poison PATH: any nix evaluation/run attempted before the gate fails loudly.
FAKE="$(mktemp -d)"
trap 'rm -rf "$FAKE"' EXIT
cat >"$FAKE/nix" <<'EOF'
#!/usr/bin/env bash
echo "check-deploy-bootstrap-gate: deploy.sh invoked nix before the required-config gate" >&2
exit 90
EOF
chmod +x "$FAKE/nix"
PATH="$FAKE:$PATH"
export PATH

# Bare no-config invocation must fail with the gate error before any work.
set +e
OUT="$("$DEPLOY" 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  fail "bare invocation unexpectedly succeeded"
fi
if ! echo "$OUT" | grep -Fq -- "target host unresolved"; then
  fail "bare invocation did not fail on the target-host gate; got: $OUT"
fi

# Supplying only some required values still fails closed on the rest.
set +e
OUT="$("$DEPLOY" --target 1.2.3.4 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  fail "partial invocation unexpectedly succeeded"
fi
if ! echo "$OUT" | grep -Fq -- "bootstrap user unresolved"; then
  fail "partial invocation did not fail on the bootstrap-user gate; got: $OUT"
fi

echo "check-deploy-bootstrap-gate: PASS"