set shell := ["bash", "-euo", "pipefail", "-c"]
set no-cd

all:
  @nix flake check --no-build --no-write-lock-file path:.
  @./tests/check-secret-scope.sh
  @./tests/check-web-services-policy.sh

test-secrets:
  @./tests/check-secret-scope.sh

test-web-policy host="do-admin-1":
  @./tests/check-web-services-policy.sh {{host}}
