#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Canonical catalog contract: cross-host consumers resolve stable service IDs
# for public URL, access, and health metadata, and never see edge-local origin
# transport fields as cross-host addresses.
nix eval --impure --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    policy = import ./policy/web-services.nix;
    policyLib = import ./lib/policy.nix { inherit lib; };
    catalog = policyLib.serviceCatalog policy;
  in
  assert builtins.hasAttr "kanidm-admin" catalog;
  assert catalog."kanidm-admin".publicUrl == "https://id.shrublab.xyz";
  assert catalog.paperless.publicUrl == "https://paper.shrublab.xyz";
  assert catalog.karakeep.publicUrl == "https://keep.shrublab.xyz";
  assert catalog.paperless.access.oidc.enabled;
  assert catalog.karakeep.access.oidc.enabled;
  assert catalog."ntfy-admin".health.path == "/v1/health";
  assert !(builtins.hasAttr "origin" catalog.paperless);
  assert !(builtins.hasAttr "upstream" catalog.paperless);
  assert !(builtins.hasAttr "healthUrl" catalog.paperless);
  true
' > /dev/null
echo "web-service catalog contract: PASS"

# Duplicate service IDs across policy owners fail evaluation before the
# catalog can become ambiguous.
nix eval --impure --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    policyLib = import ./lib/policy.nix { inherit lib; };
    dupPolicy = {
      defaults = { primaryDomain = "example.com"; };
      hosts = {
        a = {
          services.dup = {
            subdomain = "dup";
            origin = { scheme = "http"; host = "127.0.0.1"; port = 1; };
          };
        };
        b = {
          services.dup = {
            subdomain = "dup";
            origin = { scheme = "http"; host = "127.0.0.1"; port = 2; };
          };
        };
      };
    };
    result = builtins.tryEval (builtins.deepSeq (policyLib.serviceCatalog dupPolicy) true);
  in
  assert !result.success;
  true
' > /dev/null
echo "web-service catalog duplicate-key: PASS"

# Minimal physical deployment boundary: edgeHost and deployOrder remain the
# only central physical facts, and the edge host is a real deploy node. The
# serial deploy order is independent of which host is the edge.
nix eval --impure --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    deploy = flake.deployHosts;
  in
  assert deploy.edgeHost == "oci-melb-1";
  assert builtins.elem deploy.edgeHost deploy.deployOrder;
  assert builtins.hasAttr deploy.edgeHost deploy.nodes;
  assert builtins.attrNames deploy == [ "deployOrder" "edgeHost" "nodes" ];
  true
' > /dev/null
echo "deploy default-target boundary: PASS"

# Stage 8 task 3.2 (HIC-3): host-backed web routing references canonical host
# identities. Every `hosts` table key must be a declared canonical host ID, and
# every host-backed origin FQDN must be composed from a canonical host ID plus
# the single tailnet suffix authority (policy/globals.nix).
web_refs="$(nix eval --impure --raw --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    globals = import ./policy/globals.nix;
    policy = import ./policy/web-services.nix;
    hostsTable = policy.hosts or { };
    origins = builtins.concatMap (
      hostName:
      builtins.map (svc: svc.origin.host or null) (builtins.attrValues (hostsTable.${hostName}.services or { }))
    ) (builtins.attrNames hostsTable);
  in
  builtins.toJSON {
    suffix = globals.tailnet.suffix;
    policyHostKeys = builtins.attrNames hostsTable;
    canonicalHostKeys = builtins.attrNames flake.nixosConfigurations;
    hostNames = builtins.mapAttrs (_: c: c.config.networking.hostName or null) flake.nixosConfigurations;
    originHosts = builtins.filter (h: h != null) origins;
  }
')" || { echo "web routing references must evaluate" >&2; exit 1; }
python3 - "$web_refs" <<'PYEOF'
import json
import sys

got = json.loads(sys.argv[1])
suffix = got["suffix"]
canonical = set(got["canonicalHostKeys"])
errors = []

if not canonical:
    errors.append("no canonical host IDs resolved")

unknown_keys = sorted(set(got["policyHostKeys"]) - canonical)
if unknown_keys:
    errors.append(f"policy hosts keys are not canonical host IDs: {unknown_keys!r}")

# Non-vacuity: the policy must actually contain host-backed origins to check.
host_backed = sorted({h for h in got["originHosts"] if h.endswith("." + suffix)})
if not host_backed:
    errors.append("no host-backed origin FQDN found (this check would be vacuous)")

for fqdn in host_backed:
    host_id = fqdn[: -(len(suffix) + 1)]
    if host_id not in canonical:
        errors.append(f"origin FQDN {fqdn!r} does not name a canonical host ID")
        continue
    if got["hostNames"].get(host_id) != host_id:
        errors.append(
            f"origin FQDN {fqdn!r} disagrees with canonical host {host_id!r} "
            f"(networking.hostName {got['hostNames'].get(host_id)!r})"
        )

if errors:
    print("; ".join(errors), file=sys.stderr)
    sys.exit(1)
PYEOF
echo "web routing canonical-host references: PASS"

# The private service policy is the single source for the Niks3 write port:
# the provider listens on it and every publisher dials it. This is the one
# fleet-placement invariant that the retired internal-contracts module used to
# prove generically; it stays as a concrete check rather than an abstraction.
nix eval --impure --no-write-lock-file --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
    provider = flake.nixosConfigurations.oci-melb-1.config;
    catalog = provider.repo.web.catalog."niks3-write";
    lib = flake.inputs.nixpkgs.lib;
  in
  {
    isPrivate = catalog.declarePublic == false && catalog.exposureMode == "tailscale-only";
    noPublicIdentity = catalog.publicUrl == null && catalog.publicHost == null;
    providerListensOnDeclaredPort = provider.services.niks3.httpAddr
      == "0.0.0.0:${toString catalog.endpoint.port}";
    providerHostMatchesOrigin = lib.hasPrefix "oci-melb-1." catalog.endpoint.host;
  }
' | python3 -c '
import json, sys
got = json.load(sys.stdin)
want = {
    "isPrivate": True,
    "noPublicIdentity": True,
    "providerListensOnDeclaredPort": True,
    "providerHostMatchesOrigin": True,
}
if got != want:
    print(f"niks3 write-endpoint invariant: got {got!r} want {want!r}", file=sys.stderr)
    sys.exit(1)
'
echo "private write-endpoint invariant: PASS"

echo "check-web-service-catalog: PASS"
