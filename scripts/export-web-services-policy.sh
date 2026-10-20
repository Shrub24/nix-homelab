#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-$(nix eval --impure --raw --no-write-lock-file --expr '(import ./lib/deploy/hosts.nix).edgeHost')}"

mkdir -p generated/policy
nix eval --impure --json --no-write-lock-file --expr '
  let
    flake = builtins.getFlake "path:${toString ./.}";
    lib = flake.inputs.nixpkgs.lib;
    policy = import ./policy/web-services.nix {
      canonicalServices = flake.inputs.nix-fleet.lib.serviceEndpoints.canonicalServices;
    };
    policyLib = import ./lib/policy.nix { inherit lib; };
  in
  policyLib.exportHostPolicy policy "'"${HOST}"'"
' > generated/policy/web-services.json
echo "Exported generated/policy/web-services.json for ${HOST}"
