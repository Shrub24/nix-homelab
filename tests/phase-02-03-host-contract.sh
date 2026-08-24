#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE='path:.#nixosConfigurations.oci-melb-1.config'
nix eval --no-write-lock-file --raw "$BASE.networking.hostName" >/dev/null
nix eval --no-write-lock-file --raw "$BASE.system.stateVersion" >/dev/null
nix eval --no-write-lock-file --apply 'v: v == true' "$BASE.applications.music.enable" >/dev/null

# OCI consumes canonical policy service metadata (catalog), never admin-host
# names, for every cross-host identity/OIDC consumer: Kanidm, Paperless,
# Karakeep. OCI host ciphertext exists, so whole-config comparisons are safe.
nix eval --no-write-lock-file --apply 'cfg: if cfg.services.identity.oidc.providerUrl == cfg.repo.web.catalog."kanidm-admin".publicUrl then true else throw "oci-melb-1: OIDC providerUrl must resolve from the policy catalog"' "$BASE" >/dev/null
nix eval --no-write-lock-file --apply 'cfg: if cfg.services.paperless.oidc.enable == cfg.repo.web.catalog.paperless.access.oidc.enabled then true else throw "oci-melb-1: paperless OIDC enable must resolve from the policy catalog"' "$BASE" >/dev/null
nix eval --no-write-lock-file --apply 'cfg: if cfg.services.karakeep-pod.oidc.enable == cfg.repo.web.catalog.karakeep.access.oidc.enabled then true else throw "oci-melb-1: karakeep OIDC enable must resolve from the policy catalog"' "$BASE" >/dev/null

# Source-level regression: no host-keyed service reads may be reintroduced, and
# each cross-host consumer must keep its canonical catalog read.
if grep -R -n 'repo\.web\.hosts\.' modules/ hosts/oci-melb-1/; then
  echo "oci-melb-1: host-keyed repo.web.hosts.* reads must not be reintroduced" >&2
  exit 1
fi
for service in 'repo.web.catalog."kanidm-admin"' 'repo.web.catalog.paperless' 'repo.web.catalog.karakeep'; do
  if ! grep -q "$service" hosts/oci-melb-1/default.nix; then
    echo "oci-melb-1: expected catalog read ${service} missing from host wiring" >&2
    exit 1
  fi
done

echo "phase-02-03-host-contract: PASS"
