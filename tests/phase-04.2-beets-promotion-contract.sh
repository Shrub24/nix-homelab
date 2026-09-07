#!/usr/bin/env bash
set -euo pipefail

BASE='path:.#nixosConfigurations.home-forge.config'
nix eval --no-write-lock-file --raw "$BASE.services.beets.libraryDir" >/dev/null
nix eval --no-write-lock-file --raw "$BASE.services.beets.quarantineDir" >/dev/null
echo "phase-04.2-beets-promotion-contract: PASS"
