set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

# No `nix flake check` here: CI owns that wiring gate, and the LA toplevel
# needs operator ciphertext that does not exist before task 3.3.
all:
  @./tests/check-secret-scope.sh
  @./tests/check-secret-scope-extra-reader.sh
  @./tests/check-secret-updatekeys-selection.sh
  @./tests/check-ssh-host-fingerprint.sh
  @./tests/check-host-age-anchor.sh
  @./tests/check-deploy-bootstrap-gate.sh
  @./tests/check-web-services-policy.sh
  @./tests/check-web-service-catalog.sh
  @./tests/phase-la-admin-contract.sh
  @./tests/kanidm-restore-contract.sh
  @./tests/check-shell-account-contract.sh
  @./tests/check-backup-surface-contract.sh

test-secrets:
  @./tests/check-secret-scope.sh

test-secret-scope-extra-reader:
  @./tests/check-secret-scope-extra-reader.sh

test-secret-updatekeys:
  @./tests/check-secret-updatekeys-selection.sh

test-ssh-fingerprint:
  @./tests/check-ssh-host-fingerprint.sh

test-host-age-anchor:
  @./tests/check-host-age-anchor.sh

test-deploy-bootstrap-gate:
  @./tests/check-deploy-bootstrap-gate.sh

test-web-policy host="la-admin-1":
  @./tests/check-web-services-policy.sh {{host}}

test-web-catalog:
  @./tests/check-web-service-catalog.sh

test-shell-account-contract:
  @./tests/check-shell-account-contract.sh

test-backup-surface:
  @./tests/check-backup-surface-contract.sh
