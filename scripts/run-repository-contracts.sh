#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

./tests/check-ssh-host-fingerprint.sh
./tests/check-host-age-anchor.sh
./tests/check-deploy-bootstrap-gate.sh
./tests/check-flake-source-tracking.sh
./tests/check-web-services-policy.sh
./tests/check-web-service-catalog.sh
./tests/phase-la-admin-contract.sh
./tests/check-identity-contract-directionality.sh
./tests/check-postgres-hba-safety.sh
./tests/check-container-service-address.sh
./tests/check-shell-account-contract.sh
./tests/check-backup-surface-contract.sh
./tests/check-bifrost-gateway-contract.sh oci-melb-1
./tests/check-bifrost-gateway-contract.sh home-forge
./tests/check-build-account-contract.sh
./tests/check-notify-recovery-contract.sh
./tests/check-telemetry-view-composition.sh
./tests/check-user-app-placements.sh
./tests/check-geopulse-contract.sh
./tests/check-homarr-contract.sh
./tests/check-home-assistant-contract.sh
