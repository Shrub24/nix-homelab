#!/usr/bin/env bash
set -euo pipefail
# Fixture-based tests for scripts/ssh-known-hosts.sh verify logic.
# Keys and fingerprints are generated locally with ssh-keygen; no network.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/ssh-known-hosts.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ssh-keygen -q -t ed25519 -N "" -f "$WORK/key_ed25519"
ssh-keygen -q -t rsa -b 2048 -N "" -f "$WORK/key_rsa"

ED_KEYTYPE="ssh-ed25519"
ED_BLOB="$(awk '{print $2}' "$WORK/key_ed25519.pub")"
ED_FP="$(ssh-keygen -l -E sha256 -f "$WORK/key_ed25519.pub" | awk '{print $2}')"

RSA_KEYTYPE="$(awk '{print $1}' "$WORK/key_rsa.pub")"
RSA_BLOB="$(awk '{print $2}' "$WORK/key_rsa.pub")"
RSA_FP="$(ssh-keygen -l -E sha256 -f "$WORK/key_rsa.pub" | awk '{print $2}')"

fail() {
  echo "check-ssh-host-fingerprint: $*" >&2
  exit 1
}

# Positive: matching fingerprint emits the canonical known_hosts line.
out="$("$SCRIPT" verify la-admin-1 "$ED_FP" "la-admin-1 $ED_KEYTYPE $ED_BLOB")"
[[ "$out" == "la-admin-1 $ED_KEYTYPE $ED_BLOB" ]] ||
  fail "verify must emit the canonical known_hosts line"

# Negative: mismatched fingerprint must fail and name the mismatch.
set +e
out="$("$SCRIPT" verify la-admin-1 "$RSA_FP" "la-admin-1 $ED_KEYTYPE $ED_BLOB" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "verify must reject a mismatched fingerprint"
grep -q "mismatch" <<<"$out" || fail "mismatch failure must name the mismatch"

# Negative: non-ed25519 keys are rejected even when the fingerprint matches.
set +e
out="$("$SCRIPT" verify la-admin-1 "$RSA_FP" "la-admin-1 $RSA_KEYTYPE $RSA_BLOB" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "verify must reject a non-ed25519 key"
grep -q "ssh-ed25519" <<<"$out" || fail "non-ed25519 failure must mention ssh-ed25519"

echo "check-ssh-host-fingerprint: PASS"
