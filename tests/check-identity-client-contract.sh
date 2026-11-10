#!/usr/bin/env bash
set -euo pipefail

# The OIDC client contract is intrinsic and provider-neutral: it resolves on a
# host that selects no provider, and every consumer of it — including Cloudflare
# Access — reads the same projection. Targeted evaluations only: never reads or
# decrypts secret ciphertext, never touches .sops.yaml, never builds.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-identity-client-contract: $*" >&2
  exit 1
}

report() { # $1 flake ref, $2 apply expression
  nix eval --no-write-lock-file --raw --apply "$2" "$1"
}

WORK="$(mktemp -d /tmp/identity-contract.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# 1. The client contract alone resolves endpoints and starts nothing. Explicit
# override of the provider URL keeps this probe independent of policy.
probe_dir="$WORK/fragment"
mkdir -p "$probe_dir"
cat >"$probe_dir/flake.nix" <<EOF2
{
  inputs.repo.url = "path:$ROOT";
  outputs = { self, repo }: {
    report = let
      sys = repo.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import "$ROOT/modules/identity/_oidc.nix")
          {
            services.identity.oidc.providerUrl = "https://probe-id.example";
            networking.hostName = "probe-host";
            system.stateVersion = "25.11";
          }
        ];
      };
      c = sys.config;
    in {
      clients = c.services.identity.oidc.clients;
    };
  };
}
EOF2
fragment="$(nix eval --raw --impure --no-write-lock-file --expr \
  "builtins.toJSON ((builtins.getFlake (toString $probe_dir)).report)")" ||
  fail "the intrinsic client contract alone does not evaluate"

python3 - "$fragment" <<'PYEOF' || fail "intrinsic client contract observables violated"
import json, sys

got = json.loads(sys.argv[1])
errors = []
if not got.get("clients"):
    errors.append("no clients resolved from policy")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF

# 2. A remote client host resolves the same contract with no provider selected:
# the contract is intrinsic, not a side effect of the provider's aspect.
report ".#nixosConfigurations.oci-melb-1.config" \
  'c: c.services.identity.oidc.clients.paperless.issuerUrl' > /dev/null ||
  fail "a remote client host resolves no client contract"

# 4. Cloudflare Access federates with the same client contract. A cutover that moved the
# provider without moving the Access IdP would leave every Access-gated route unreachable,
# so the infrastructure input is checked against the contract rather than trusted.
# Read from a host that composes the contract: the provider host runs no OIDC client of
# its own, so the namespace is absent there by design.
idp_json="$(report ".#nixosConfigurations.oci-melb-1.config" 'c: let k = c.services.identity.oidc.clients."cloudflare-access"; in builtins.toJSON {
  name = k.providerName;
  authUrl = k.authorizationUrl;
  tokenUrl = k.tokenUrl;
  certsUrl = k.jwksUrl;
}')" || fail "the Cloudflare Access client does not resolve"
python3 - "$idp_json" "$ROOT/opentofu/cloudflare/foundation/config.auto.tfvars" <<'PYEOF' || fail "Cloudflare Access must federate with the client contract"
import json, re, sys

contract = json.loads(sys.argv[1])
tfvars = open(sys.argv[2]).read()

def value(key):
    match = re.search(rf'^{key}\s*=\s*"([^"]*)"', tfvars, re.MULTILINE)
    return match.group(1) if match else None

errors = []
for key, want in (
    ("idp_name", contract["name"]),
    ("idp_auth_url", contract["authUrl"]),
    ("idp_token_url", contract["tokenUrl"]),
    ("idp_certs_url", contract["certsUrl"]),
):
    got = value(key)
    if got != want:
        errors.append(f"{key}: opentofu declares {got!r}, the client contract resolves {want!r}")
if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF


echo "check-identity-client-contract: PASS"
