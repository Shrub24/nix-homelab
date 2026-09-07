#!/usr/bin/env bash
set -euo pipefail

BASE='path:.#nixosConfigurations.home-forge.config'
nix eval --no-write-lock-file --raw "$BASE.services.beets.dataDir" >/dev/null
echo "phase-04.1-beets-contract: PASS"
