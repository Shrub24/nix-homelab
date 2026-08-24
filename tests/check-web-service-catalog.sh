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
# only central physical facts, and the default target is a real deploy node.
nix eval --impure --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    deploy = flake.deployHosts;
  in
  assert deploy.edgeHost == "la-admin-1";
  assert builtins.head deploy.deployOrder == deploy.edgeHost;
  assert builtins.hasAttr deploy.edgeHost deploy.nodes;
  assert builtins.attrNames deploy == [ "deployOrder" "edgeHost" "nodes" ];
  true
' > /dev/null
echo "deploy default-target boundary: PASS"

echo "check-web-service-catalog: PASS"
