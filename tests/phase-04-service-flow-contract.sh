#!/usr/bin/env bash
set -euo pipefail

# D-045 moved the whole music service flow (applications.music → Navidrome,
# slskd) to home-forge. oci-melb-1 no longer imports the composition at all.
HF='path:.#nixosConfigurations.home-forge.config'
OCI='path:.#nixosConfigurations.oci-melb-1.config'
nix eval --no-write-lock-file --apply 'v: v == true' "$HF.applications.music.enable" >/dev/null
nix eval --no-write-lock-file --raw "$HF.services.navidrome.settings.MusicFolder" >/dev/null
nix eval --no-write-lock-file --raw "$HF.services.slskd.settings.directories.downloads" >/dev/null
nix eval --no-write-lock-file --apply 'cfg: if cfg ? applications.music then throw "oci-melb-1 must not compose applications.music" else true' "$OCI" >/dev/null
echo "phase-04-service-flow-contract: PASS"
