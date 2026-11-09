set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

# The same shell contracts run locally and inside checks.repository-contracts.
all:
  @nix build --no-link ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).check-flake-file"
  @./tests/check-ssh-host-fingerprint.sh
  @./tests/check-host-age-anchor.sh
  @./tests/check-deploy-bootstrap-gate.sh
  @python3 tests/test-just-command-surface.py
  @./tests/check-flake-source-tracking.sh
  @nix build --no-link ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).assets-publisher"
  @./tests/check-postgres-hba-safety.sh
  @./tests/check-web-services-policy.sh
  @python3 tests/check-ingress-public-pages.py
  @./tests/check-web-service-catalog.sh
  @./tests/phase-la-admin-contract.sh
  @./tests/check-identity-contract-directionality.sh
  @./tests/check-shell-account-contract.sh
  @./tests/check-backup-surface-contract.sh
  @./tests/check-container-service-address.sh
  @./tests/check-bifrost-gateway-contract.sh oci-melb-1
  @./tests/check-bifrost-gateway-contract.sh home-forge
  @./tests/check-build-account-contract.sh
  @./tests/check-notify-recovery-contract.sh
  @./tests/check-telemetry-view-composition.sh
  @./tests/check-user-app-placements.sh
  @./tests/check-geopulse-contract.sh
  @./tests/check-homarr-contract.sh
  @./tests/check-home-assistant-contract.sh
  @bash ./scripts/run-repository-contracts.sh
  @nix build --no-link .#checks.x86_64-linux.nixbot-contract .#checks.x86_64-linux.cache-retain .#checks.x86_64-linux.package-updates
test-ssh-fingerprint:
  @./tests/check-ssh-host-fingerprint.sh

test-host-age-anchor:
  @./tests/check-host-age-anchor.sh

test-deploy-bootstrap-gate:
  @./tests/check-deploy-bootstrap-gate.sh

test-command-surface:
  @python3 tests/test-just-command-surface.py

test-postgres-hba-safety:
  @./tests/check-postgres-hba-safety.sh

test-web-policy:
  @./tests/check-web-services-policy.sh

test-web-catalog:
  @./tests/check-web-service-catalog.sh

test-shell-account-contract:
  @./tests/check-shell-account-contract.sh

test-backup-surface:
  @./tests/check-backup-surface-contract.sh

test-container-service-address:
  @./tests/check-container-service-address.sh

test-bifrost-gateway:
  @./tests/check-bifrost-gateway-contract.sh oci-melb-1
  @./tests/check-bifrost-gateway-contract.sh home-forge

test-build-account:
  @./tests/check-build-account-contract.sh

test-notify-recovery:
  @./tests/check-notify-recovery-contract.sh

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
