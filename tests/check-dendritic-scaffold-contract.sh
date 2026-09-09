#!/usr/bin/env bash
set -euo pipefail

# Dendritic Stage 1 scaffold contract (openspec change
# dendritic-stage-1-scaffold-hosts task 4.1/6.4; design DS-1, DS-2, DS-5, DS-6).
#
# Prefers observable evaluations; exact source invariants are used only where
# import-tree behavior cannot be observed from outside. A plain NixOS leaf
# leaking into flake-parts discovery fails the flake evals below loudly, and
# the Stage 0 path/shape fails check 1 immediately (no boundary list file).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-dendritic-scaffold-contract: $*" >&2
  exit 1
}

ne() { nix eval --no-write-lock-file "$@"; }

# --- 1. Temporary import-tree boundary (DS-1) --------------------------------

LIST_FILE="modules/flake/_unconverted-nixos-dirs.nix"
test -f "$LIST_FILE" || fail "$LIST_FILE missing (Stage 1 boundary)"

# The named list must cover the Stage 1 plain-NixOS roots exactly (order is
# part of the contract so drift shows up as a visible diff).
actual="$(nix-instantiate --eval --strict --json "./$LIST_FILE")"
if [ "$actual" != '["applications","core","hosts","profiles","providers","services","shared","storage"]' ]; then
  fail "unconverted-dir list drifted from Stage 1 roots: $actual"
fi
# (Exact equality also proves no underscore path is enumerated here: import-tree
# underscore semantics, not this list, owns host-private files.)
for dir in applications core hosts profiles providers services shared storage; do
  test -d "modules/$dir" || fail "excluded root modules/$dir must exist"
done

# Discovery wiring is not observable beyond "the flake evaluates" (check 3),
# so pin the two source invariants that make the boundary a filterNot over the
# named list.
grep -q 'inputs.import-tree.filterNot' flake.nix || fail "flake.nix must filter discovery via import-tree filterNot"
grep -q '_unconverted-nixos-dirs.nix' flake.nix || fail "flake.nix must build the filterNot predicate from $LIST_FILE"

# --- 2. Atomic host move; underscore-private bootstrap (DS-5) ----------------

test ! -e hosts || fail "old top-level hosts/ assembly must be gone"
test ! -e modules/storage/disko-single-disk-split.nix || fail "OCI disko layout must live beside its host"
test ! -e modules/storage/disko-two-disk.nix || fail "home-forge disko layout must live beside its host"
test ! -e modules/hosts/oci-melb-1/bootstrap-config.nix || fail "OCI bootstrap metadata must be underscore-private"
# DS-5/DS-6: the transitional _bootstrap-config.nix is deleted; metadata is
# inlined into the typed host record and projected from the registry.
test ! -e modules/hosts/oci-melb-1/_bootstrap-config.nix || fail "modules/hosts/oci-melb-1/_bootstrap-config.nix must be deleted (DS-5/DS-6)"
test -f modules/hosts/oci-melb-1/disko-single-disk-split.nix || fail "modules/hosts/oci-melb-1/disko-single-disk-split.nix missing"
test -f modules/hosts/home-forge/disko-two-disk.nix || fail "modules/hosts/home-forge/disko-two-disk.nix missing"
# The successful flake evals below, with _bootstrap-config.nix absent and no
# underscore entry in the boundary list, are the proof that import-tree skipped
# the file by underscore semantics.

# --- 3. Typed registry materialized into nixosConfigurations (DS-2) ----------

registry_keys="$(ne --raw --apply 'c: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames c))' 'path:.#nixosConfigurations')"
if [ "$registry_keys" != '["home-forge","la-admin-1","oci-melb-1"]' ]; then
  fail "nixosConfigurations keys drifted: $registry_keys"
fi
declare -A want_system=([home-forge]=x86_64-linux [la-admin-1]=x86_64-linux [oci-melb-1]=aarch64-linux)
for host in home-forge la-admin-1 oci-melb-1; do
  system="$(ne --raw "path:.#nixosConfigurations.${host}.config.nixpkgs.system")" ||
    fail "${host}: target system does not evaluate"
  [ "$system" = "${want_system[$host]}" ] ||
    fail "${host}: target system ${system} != ${want_system[$host]}"
done

# --- 3b. Standard materializer, not a direct eval-config shim (DS-2) ---------

# The registry must materialize through inputs.nixpkgs.lib.nixosSystem (the
# public flake integration wrapper), never a direct eval-config.nix import or
# a hand-rolled source shim.
grep -q 'inputs.nixpkgs.lib.nixosSystem' modules/flake/registry.nix ||
  fail "registry must materialize via inputs.nixpkgs.lib.nixosSystem (DS-2)"
if grep -RnE --include='*.nix' 'eval-config\.nix' modules/flake lib; then
  fail "registry must not import nixpkgs eval-config.nix directly (DS-2)"
fi

# --- 4. Preserved flake output contracts (DS-6) ------------------------------

for out in bootstrap checks deploy deployHosts devShells formatter nixosConfigurations packages; do
  ne --apply '_: true' "path:.#${out}" >/dev/null || fail "flake output .${out} missing"
done

# Package keys stay exact per system, including the absent host-home-forge.
for system in x86_64-linux aarch64-linux; do
  pkgs="$(ne --raw --apply 'p: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames p))' "path:.#packages.${system}")" ||
    fail "packages.${system} does not evaluate"
  if [ "$pkgs" != '["deploy-rs","host-la-admin-1","host-oci-melb-1","niks3","nix-path-filter","notification-daemon","notify","windows-dj-setup"]' ]; then
    fail "packages.${system} keys drifted (host-home-forge must stay absent): $pkgs"
  fi
done

# Deploy node keys match the registry; physical edge/order metadata unchanged.
deploy_keys="$(ne --raw --apply 'n: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames n))' 'path:.#deploy.nodes')"
[ "$deploy_keys" = "$registry_keys" ] || fail "deploy node keys $deploy_keys != registry keys $registry_keys"
[ "$(ne --raw 'path:.#deployHosts.edgeHost')" = "la-admin-1" ] || fail "edgeHost must remain la-admin-1"
[ "$(ne --raw --apply 'l: builtins.toJSON l' 'path:.#deployHosts.deployOrder')" = '["la-admin-1","oci-melb-1"]' ] ||
  fail "deployOrder must remain [la-admin-1 oci-melb-1]"

# --- 5. Bootstrap projection and resolver agreement (DS-6) -------------------

[ "$(ne --raw --apply 'n: builtins.toJSON (builtins.attrNames n)' 'path:.#bootstrap.nodes')" = '["oci-melb-1"]' ] ||
  fail "flake.bootstrap.nodes must expose exactly oci-melb-1"
BN='path:.#bootstrap.nodes.oci-melb-1'
# Exactly the seven projected values: five stored in the typed record plus
# hostName and flake derived from the registry key (DS-5/DS-6).
oci_keys="$(ne --raw --apply 'v: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames v))' "$BN")"
if [ "$oci_keys" != '["bootstrapDisk","bootstrapUser","dataRoot","flake","hostName","mediaDisk","rootPartitionSize"]' ]; then
  fail "OCI bootstrap projection must keep exactly the seven expected values: $oci_keys"
fi
# Every field scripts/resolve-host-config.sh consumes must be present
# (hardwareConfig* are resolver-optional and legitimately absent here).
ne --apply 'v: if (v ? hostName) && (v ? bootstrapUser) && (v ? flake) then true else throw "missing resolver fields"' "$BN" >/dev/null ||
  fail "OCI bootstrap projection must contain hostName, bootstrapUser, and flake"
p_hostName="$(ne --raw "$BN.hostName")"
p_bootstrapUser="$(ne --raw "$BN.bootstrapUser")"
p_flake="$(ne --raw "$BN.flake")"
p_hwGen="$(ne --raw --apply 'v: v.hardwareConfigGenerator or ""' "$BN")"
p_hwPath="$(ne --raw --apply 'v: v.hardwareConfigPath or ""' "$BN")"

# Source the resolver directly (not through a printf/read round-trip, which
# would strip the empty trailing values) and compare against the projection.
unset HOST_CONFIG 2>/dev/null || true
source scripts/resolve-host-config.sh oci-melb-1 >/dev/null
[ "$TARGET_HOST" = "$p_hostName" ] || fail "resolver TARGET_HOST '$TARGET_HOST' != projection '$p_hostName'"
[ "$BOOTSTRAP_USER" = "$p_bootstrapUser" ] || fail "resolver BOOTSTRAP_USER '$BOOTSTRAP_USER' != projection '$p_bootstrapUser'"
[ "$FLAKE" = "$p_flake" ] || fail "resolver FLAKE '$FLAKE' != projection '$p_flake'"
[ "$HARDWARE_CONFIG_GENERATOR" = "$p_hwGen" ] || fail "resolver HARDWARE_CONFIG_GENERATOR '$HARDWARE_CONFIG_GENERATOR' != projection '$p_hwGen'"
[ "$HARDWARE_CONFIG_PATH" = "$p_hwPath" ] || fail "resolver HARDWARE_CONFIG_PATH '$HARDWARE_CONFIG_PATH' != projection '$p_hwPath'"
# DS-6: the resolver no longer exports a source-file path; HOST_CONFIG must be
# unset after sourcing.
if [[ -n "${HOST_CONFIG:-}" ]]; then
  fail "resolver must no longer export HOST_CONFIG (got '$HOST_CONFIG')"
fi

# --- 6. No broad argument bus below the flake-parts layer (DS-4) -------------

if grep -RnE --include='*.nix' 'specialArgs[[:space:]]*=' flake.nix modules lib policy; then
  fail "specialArgs must be fully removed at cutover (DS-4)"
fi
# No lower-level NixOS function may take self/inputs/ociImages parameters
# (multi-line and single-line destructuring heads).
if grep -RnE --include='*.nix' '^[[:space:]]*(inputs|self|ociImages),[[:space:]]*$' modules lib policy |
  grep -v '^modules/flake/'; then
  fail "lower-level module takes a prohibited self/inputs/ociImages argument"
fi
if grep -RnE --include='*.nix' '\{[^}]*\b(inputs|self|ociImages)\b[^}]*\}' modules lib policy |
  grep -v '^modules/flake/'; then
  fail "lower-level module destructures a prohibited self/inputs/ociImages argument"
fi
# Image references must flow through the typed policy option only.
if grep -RnE --include='*.nix' 'ociImages' modules lib | grep -v '^modules/flake/' | grep -vE 'repo\.ociImages'; then
  fail "ociImages may only be read as config.repo.ociImages"
fi

echo "check-dendritic-scaffold-contract: PASS"
