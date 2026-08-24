#!/usr/bin/env bash
# Print every SOPS-encryptable file under secrets/ (.yaml/.yml/.json),
# excluding secrets/.templates/. Used by the secrets/justfile updatekeys
# recipes and by tests/check-secret-updatekeys-selection.sh; it only lists
# paths, it never decrypts or edits anything.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

find "$ROOT/secrets" \
  -path "$ROOT/secrets/.templates" -prune -o \
  \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) -type f -print \
  | sed "s#^$ROOT/##" \
  | sort
