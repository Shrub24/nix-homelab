#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${1:-la-admin-1}"
OUT="${REPO_ROOT}/generated/policy/web-services.json"
TMP="$(mktemp)"

cleanup() {
  rm -f "$TMP"
}
trap cleanup EXIT

nix eval --impure --json --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    policy = import ./policy/web-services.nix;
    policyLib = import ./lib/policy.nix { inherit lib; };
  in
  policyLib.exportHostPolicy policy "'"${HOST}"'"
' > "$TMP"

if [[ ! -f "$OUT" ]]; then
  echo "$OUT is missing (run: ./scripts/export-web-services-policy.sh ${HOST})"
  exit 1
fi

if ! cmp -s "$TMP" "$OUT"; then
  echo "$OUT is out of date (run: ./scripts/export-web-services-policy.sh ${HOST})"
  exit 1
fi

echo "web-services policy export is up to date for ${HOST}"
