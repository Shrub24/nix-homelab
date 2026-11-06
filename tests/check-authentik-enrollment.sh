#!/usr/bin/env bash
# Real flow acceptance; requires rootless Podman and access to the official images.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
WORK="$(mktemp -d)"
NAME="authentik-enrollment-$$"
export ENROLLMENT_TEST_ROOT="$ROOT"

cleanup() {
  local status=$?
  if podman container exists "$NAME-runtime"; then
    podman rm -f -v "$NAME-runtime" || status=1
  fi
  if podman container exists "$NAME-db"; then
    podman rm -f -v "$NAME-db" || status=1
  fi
  if podman network exists "$NAME"; then
    podman network rm "$NAME" || status=1
  fi
  rm -rf "$WORK"
  exit "$status"
}
trap cleanup EXIT

version="$(nix eval --raw .#nixosConfigurations.oci-melb-1.config.services.authentik.authentikComponents.gopkgs.version)"
image="ghcr.io/goauthentik/server:$version"
tools="$(nix build --no-link --print-out-paths --impure --expr '
  let
    root = builtins.toPath (builtins.getEnv "ENROLLMENT_TEST_ROOT");
    flake = builtins.getFlake ("git+file://" + toString root);
    pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  in (import (root + "/modules/identity/authentik/_blueprint/tools.nix") { inherit pkgs; }).tool
')"
nix eval --impure --json --expr '
  let
    root = builtins.toPath (builtins.getEnv "ENROLLMENT_TEST_ROOT");
    flake = builtins.getFlake ("git+file://" + toString root);
  in import (root + "/tests/authentik-enrollment.nix") { inherit (flake.inputs.nixpkgs) lib; }
' > "$WORK/blueprint.json"
"$tools/bin/authentik-blueprint-tools" --output "$WORK/blueprint.yaml" "$WORK/blueprint.json"

podman network create "$NAME"
podman run -d --name "$NAME-db" --network "$NAME" \
  -e POSTGRES_DB=authentik -e POSTGRES_USER=authentik \
  -e POSTGRES_PASSWORD=disposable-enrollment-test \
  --health-cmd='pg_isready -U authentik -d authentik' --health-interval=1s \
  --health-retries=60 docker.io/library/postgres:16-alpine
timeout 120s podman wait --condition=healthy "$NAME-db"

# These credentials are local to the disposable network; no host ports are published.
printf '%s\n' \
  'AUTHENTIK_SECRET_KEY=disposable-enrollment-acceptance-key-never-used-outside-this-test-network' \
  "AUTHENTIK_POSTGRESQL__HOST=$NAME-db" \
  'AUTHENTIK_POSTGRESQL__NAME=authentik' \
  'AUTHENTIK_POSTGRESQL__USER=authentik' \
  'AUTHENTIK_POSTGRESQL__PASSWORD=disposable-enrollment-test' \
  'AUTHENTIK_LOG_LEVEL=warning' \
  'AUTHENTIK_ERROR_REPORTING__ENABLED=false' \
  'AUTHENTIK_DISABLE_UPDATE_CHECK=true' \
  'AUTHENTIK_ENROLLMENT_TEST=1' > "$WORK/runtime.env"

runtime() {
  podman run --rm --name "$NAME-runtime" --network "$NAME" \
    --env-file "$WORK/runtime.env" \
    -v "$WORK/blueprint.yaml:/blueprints/custom/enrollment.yaml:ro" \
    -v "$ROOT/tests/authentik-enrollment.py:/tmp/acceptance.py:ro" "$@"
}
runtime --entrypoint /ak-root/.venv/bin/python "$image" -m lifecycle.migrate
runtime "$image" apply_blueprint \
  default/flow-default-authentication-flow.yaml \
  default/flow-default-authenticator-totp-setup.yaml \
  default/flow-default-authenticator-webauthn-setup.yaml \
  custom/enrollment.yaml
runtime "$image" shell --no-imports -c 'exec(open("/tmp/acceptance.py").read())'
podman image inspect "$image" --format '{{json .RepoDigests}}'
printf 'check-authentik-enrollment: PASS (Authentik %s; isolated official image)\n' "$version"
