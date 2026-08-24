#!/usr/bin/env bash
set -euo pipefail

# Derive a known_hosts entry for a deployment target only after verifying the
# discovered ed25519 host key against a source-controlled, console-verified
# fingerprint. SSH host checking is never disabled; emit() writes a verified
# known_hosts file so ssh runs with normal host verification.

usage() {
  cat >&2 <<'EOF'
usage: ssh-known-hosts.sh <command> [args]

discover <host> [port]
    Print the first ed25519 host key line discovered from <host> via ssh-keyscan.

verify <host> <expected-fingerprint> <key-line>
    Verify that the sha256 fingerprint of <key-line> (an ssh-keyscan line)
    exactly matches <expected-fingerprint> and print the canonical
    known_hosts line on success.

emit <host> <expected-fingerprint> <known-hosts-file>
    discover + verify, then write the verified known_hosts file.
EOF
}

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

die() {
  echo "ssh-known-hosts: $*" >&2
  exit 1
}

# sha256 fingerprint of an ed25519 key blob, without contacting a network.
# OpenSSH >= 10 no longer reads a bare key line from stdin, so use a scratch
# public-key file (the canonical known_hosts entry format).
fingerprint_of() {
  # $1 = keytype, $2 = base64 blob
  printf '%s %s\n' "$1" "$2" >"$SCRATCH/key"
  awk '{print $2}' <<<"$(ssh-keygen -l -E sha256 -f "$SCRATCH/key")"
}

discover() {
  local host="$1" port="${2:-22}"
  ssh-keyscan -t ed25519 -p "$port" "$host" 2>/dev/null | awk '/ssh-ed25519/ { print; exit }'
}

verify() {
  local host="$1" expected="$2" key_line="$3"
  local keytype base64 actual

  read -r _ keytype base64 <<<"$key_line"
  [[ "$keytype" == "ssh-ed25519" ]] || die "expected an ssh-ed25519 key, got '${keytype:-<none>}'"
  actual="$(fingerprint_of "$keytype" "$base64")"
  [[ "$actual" == "$expected" ]] || die "host key fingerprint mismatch for $host: expected $expected, got $actual"
  printf '%s %s %s\n' "$host" "$keytype" "$base64"
}

emit() {
  local host="$1" expected="$2" out="$3"
  local line

  line="$(discover "$host")"
  [[ -n "$line" ]] || die "no ed25519 host key discovered for $host"
  verify "$host" "$expected" "$line" >"$out"
}

cmd="${1:-}"
case "$cmd" in
discover)
  [[ $# -ge 2 ]] || die "usage: ssh-known-hosts.sh discover <host> [port]"
  discover "$2" "${3:-22}"
  ;;
verify)
  [[ $# -eq 4 ]] || die "usage: ssh-known-hosts.sh verify <host> <expected-fingerprint> <key-line>"
  verify "$2" "$3" "$4"
  ;;
emit)
  [[ $# -eq 4 ]] || die "usage: ssh-known-hosts.sh emit <host> <expected-fingerprint> <known-hosts-file>"
  emit "$2" "$3" "$4"
  ;;
*)
  usage
  exit 2
  ;;
esac
