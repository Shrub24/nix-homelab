set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

# The local battery: the repository's own contract tests plus the generated
# flake.nix freshness check. The full wiring gate is CI's build job, which builds
# `.#checks` with the fleet's builders available — an evaluation-only
# `nix flake check --no-build` cannot pass on a cold store, because evaluating the
# flake realises degoog's unsubstitutable bun2nix import-from-derivation (D-082).
all:
  @nix build --no-link ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).check-flake-file"
  @./tests/check-ssh-host-fingerprint.sh
  @./tests/check-host-age-anchor.sh
  @./tests/check-deploy-bootstrap-gate.sh
  @./tests/check-flake-source-tracking.sh
  @./tests/check-dendritic-scaffold-contract.sh
  @./tests/check-web-services-policy.sh
  @./tests/check-web-service-catalog.sh
  @./tests/phase-la-admin-contract.sh
  @./tests/check-identity-contract-directionality.sh
  @./tests/kanidm-restore-contract.sh
  @./tests/check-shell-account-contract.sh
  @./tests/check-backup-surface-contract.sh
  @./tests/check-bifrost-gateway-contract.sh oci-melb-1
  @./tests/check-bifrost-gateway-contract.sh home-forge
  @./tests/check-build-account-contract.sh
  @./tests/check-telemetry-view-composition.sh
  @./tests/check-user-app-placements.sh
  @./tests/check-geopulse-contract.sh
  @./tests/check-homarr-contract.sh
  @./tests/check-home-assistant-contract.sh

test-ssh-fingerprint:
  @./tests/check-ssh-host-fingerprint.sh

test-host-age-anchor:
  @./tests/check-host-age-anchor.sh

test-deploy-bootstrap-gate:
  @./tests/check-deploy-bootstrap-gate.sh

test-dendritic-scaffold-contract:
  @./tests/check-dendritic-scaffold-contract.sh

test-web-policy:
  @./tests/check-web-services-policy.sh

test-web-catalog:
  @./tests/check-web-service-catalog.sh

test-shell-account-contract:
  @./tests/check-shell-account-contract.sh

test-backup-surface:
  @./tests/check-backup-surface-contract.sh

test-bifrost-gateway:
  @./tests/check-bifrost-gateway-contract.sh oci-melb-1
  @./tests/check-bifrost-gateway-contract.sh home-forge

test-build-account:
  @./tests/check-build-account-contract.sh

test-telemetry-views:
  @./tests/check-telemetry-view-composition.sh

test-user-app-placements:
  @./tests/check-user-app-placements.sh

test-homarr-contract:
  @./tests/check-homarr-contract.sh

test-geopulse-contract:
  @./tests/check-geopulse-contract.sh

test-home-assistant-contract:
  @./tests/check-home-assistant-contract.sh
