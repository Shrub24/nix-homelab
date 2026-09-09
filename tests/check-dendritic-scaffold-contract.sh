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

# The named list must cover the plain-NixOS roots exactly (order is part of
# the contract so drift shows up as a visible diff). Stage 2 (foundation
# aspects) removed `core` and `profiles` after their contents became aspect
# contributors or were deleted.
actual="$(nix-instantiate --eval --strict --json "./$LIST_FILE")"
if [ "$actual" != '["applications","hosts","providers","services","shared","storage"]' ]; then
  fail "unconverted-dir list drifted from Stage 2 roots: $actual"
fi
# (Exact equality also proves no underscore path is enumerated here: import-tree
# underscore semantics, not this list, owns host-private files.)
for dir in applications hosts providers services shared storage; do
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

# --- 7. Stage 2 foundation aspects (FND-1..FND-6) ---------------------------
# (openspec change dendritic-stage-2-foundation-aspects task 6.1)
#
# flake.modules.nixos is an internal flake-parts option, so publication
# exactness is pinned at its source (modules/flake/aspects.nix) and at the
# registry selection; the selection-is-enablement contract is then proven
# observationally per host below. FND-2 typed facts and the boot/`/build`
# render are exact evaluated values, not restatements of module source.

# 7a. Exactly the infra trio plus the five foundation aspects are published;
# the deleted `cli` aspect must not be resurrected, and the private aspect
# leaves are exactly base/shell/networking plus the p10k data file.
pub_names="$(grep -oE '^[[:space:]]*flake\.modules\.nixos\.[a-z-]+' modules/flake/aspects.nix | tr -d ' ' | sort)"
if [ "$pub_names" != "$(printf '%s\n' \
flake.modules.nixos.base \
flake.modules.nixos.fleet-packages \
flake.modules.nixos.networking \
flake.modules.nixos.notify \
flake.modules.nixos.oci-images \
flake.modules.nixos.provenance \
flake.modules.nixos.shell \
flake.modules.nixos.tailscale)" ]; then
fail "flake.modules.nixos publication drifted from infra trio + five foundation aspects: $pub_names"
fi
if grep -RnE --include='*.nix' 'flake\.modules\.nixos\.cli|_aspects/cli|aspects\.cli' modules; then
fail "the deleted cli aspect must not be resurrected"
fi
if [ "$(find modules/flake/_aspects -maxdepth 1 -type f -printf '%f\n' | sort | tr '\n' ' ')" != "base.nix networking.nix p10k.zsh shell.nix " ]; then
fail "modules/flake/_aspects must contain exactly base.nix networking.nix p10k.zsh shell.nix"
fi

# 7b. Every registry host selects exactly the five foundation aspects, in
# canonical order (selection is enablement). Host assemblies receive them
# only via the registry and never import the deleted compatibility roots.
foundation_block="$(awk '/# Foundation aspects \(FND-1\)/ { grab = 1; next } grab && /\.\.\/hosts\// { grab = 0 } grab { gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print }' modules/flake/registry.nix)"
canonical="$(printf 'aspects.base\naspects.shell\naspects.networking\naspects.tailscale\naspects.notify\n%.0s' {1..3})"
if [ "$foundation_block" != "$canonical" ]; then
fail "registry foundation selection must be exactly base,shell,networking,tailscale,notify per host: $foundation_block"
fi
if grep -RnE 'aspects\.|_aspects' modules/hosts; then
fail "host assemblies must receive foundation aspects only via the registry"
fi
test ! -e modules/core || fail "modules/core must be deleted (FND-6)"
test ! -e modules/profiles || fail "modules/profiles must be deleted (FND-6)"
if grep -RnE --include='*.nix' 'import.*modules/(core|profiles)/' modules; then
fail "no module may import a deleted core/profiles path"
fi

# 7c. Typed base facts: enum bootLoader ("grub" | "systemd-boot") and a
# required string buildTmpfsSize, rendered by the base aspect without a
# per-host mkForce override anywhere in the tree.
grep -q 'type = lib.types.enum' modules/flake/_aspects/base.nix || fail "bootLoader fact must be a typed enum"
grep -q '"grub"' modules/flake/_aspects/base.nix || fail "bootLoader enum must accept grub"
grep -q '"systemd-boot"' modules/flake/_aspects/base.nix || fail "bootLoader enum must accept systemd-boot"
grep -q 'buildTmpfsSize = lib.mkOption' modules/flake/_aspects/base.nix || fail "buildTmpfsSize fact option missing"
grep -q 'type = lib.types.str;' modules/flake/_aspects/base.nix || fail "buildTmpfsSize fact must be a typed string"
if grep -RnE --include='*.nix' 'mkForce' modules | grep -E 'boot\.loader|fileSystems|"/build"|fleet\.foundation|services\.tailscale|notification-daemon|tailscale_auth|debugMtu|authKeyFile'; then
fail "foundation-owned options must not be overridden with mkForce"
fi

# 7d. Per-host observable contract: typed facts, boot/`/build` rendering,
# the five aspect markers (selection is enablement), Tailscale MTU/auth-key
# ownership, and notify composition with the repo packages.
probe() { # $1 host, $2 expected JSON (python dict literal)
host="$1"
json="$(ne --json --apply 'c: {
bootLoader = c.fleet.foundation.bootLoader;
buildTmpfsSize = c.fleet.foundation.buildTmpfsSize;
systemdBoot = c.boot.loader.systemd-boot.enable;
grub = c.boot.loader.grub.enable;
efiRemovable = c.boot.loader.grub.efiInstallAsRemovable or false;
buildFs = c.fileSystems."/build".fsType or "";
buildOpts = c.fileSystems."/build".options or [];
dev = (c.users.users.dev or {}).isNormalUser or false;
zsh = c.programs.zsh.enable or false;
networkd = c.systemd.network.enable or false;
ts = c.services.tailscale.enable or false;
tsMtu = ((c.systemd.services.tailscaled or {}).environment or {}).TS_DEBUG_MTU or null;
tsAuthKeyFile = c.services.tailscale.authKeyFile or null;
daemon = c.services.notification-daemon.enable or false;
daemonPkg = (c.services.notification-daemon.package or {}).name or "";
notifyPkg = (c.services.notification-daemon.notifyPackage or {}).name or "";
}' "path:.#nixosConfigurations.${host}.config")" ||
fail "${host}: foundation probe does not evaluate"
python3 - "$host" "$2" "$json" <<'PYEOF' || fail "${host}: observable foundation contract violated"
import json, sys
host, exp_raw, got_raw = sys.argv[1], sys.argv[2], sys.argv[3]
exp = json.loads(exp_raw)
got = json.loads(got_raw)
errs = []
for k, v in exp.items():
    if got.get(k) != v:
        errs.append(f"{k}: got {got.get(k)!r} want {v!r}")
if got["buildFs"] != "tmpfs":
    errs.append(f"buildFs: got {got['buildFs']!r} want tmpfs")
if not any(o == "size=" + got["buildTmpfsSize"] for o in got["buildOpts"]):
    errs.append(f"buildOpts: no size={got['buildTmpfsSize']} in {got['buildOpts']!r}")
if not any(o == "mode=0755" for o in got["buildOpts"]):
    errs.append(f"buildOpts: missing mode=0755 in {got['buildOpts']!r}")
if not got["daemonPkg"].startswith("notification-daemon-"):
    errs.append(f"daemonPkg: {got['daemonPkg']!r} not the repo notification-daemon package")
if got["notifyPkg"] != "notify":
    errs.append(f"notifyPkg: {got['notifyPkg']!r} not the repo notify package")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

probe oci-melb-1 '{"bootLoader":"grub","buildTmpfsSize":"8G","systemdBoot":false,"grub":true,"efiRemovable":true,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":"1200","tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemon":true}'
probe la-admin-1 '{"bootLoader":"systemd-boot","buildTmpfsSize":"50%","systemdBoot":true,"grub":false,"efiRemovable":false,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":"1200","tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemon":true}'
probe home-forge '{"bootLoader":"systemd-boot","buildTmpfsSize":"50%","systemdBoot":true,"grub":false,"efiRemovable":false,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":null,"tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemon":true}'

# 7e. Tailscale ownership (FND-4, secrets-management spec): the module leaf
# owns auth-key registration and MTU rendering; hosts never repeat them.
grep -q 'key = "tailscale/auth_key"' modules/services/tailscale.nix || fail "tailscale leaf must register key tailscale/auth_key"
grep -q 'path = "/run/secrets/tailscale.auth_key"' modules/services/tailscale.nix || fail "tailscale leaf must render /run/secrets/tailscale.auth_key"
grep -q 'mode = "0400"' modules/services/tailscale.nix || fail "tailscale auth-key secret must be mode 0400"
grep -q 'authKeyFile = lib.mkIf hasHostSecrets "/run/secrets/tailscale.auth_key"' modules/services/tailscale.nix || fail "tailscale leaf must own authKeyFile"
grep -q 'TS_DEBUG_MTU = toString cfg.debugMtu' modules/services/tailscale.nix || fail "tailscale leaf must render TS_DEBUG_MTU from debugMtu"
if grep -RnE 'tailscale_auth_key|authKeyFile|TS_DEBUG_MTU|tailscale\.auth_key' modules/hosts; then
fail "hosts must not repeat tailscale secret/MTU registration"
fi

# 7f. Notify composition (FND-5, apprise-notification-module spec): the notify
# aspect composes the notification-daemon leaf, enables it, and resolves the
# repo packages via withSystem; hosts keep only host-specific inputs.
grep -q 'imports = \[ ../services/notification-daemon \]' modules/flake/aspects.nix || fail "notify aspect must compose the notification-daemon leaf"
grep -q 'enable = true;' modules/flake/aspects.nix || fail "notify aspect must enable the daemon"
grep -q 'package = packages.notification-daemon;' modules/flake/aspects.nix || fail "notify aspect must pass the repo notification-daemon package"
grep -q 'notifyPackage = packages.notify;' modules/flake/aspects.nix || fail "notify aspect must pass the repo notify package"
if grep -RnE 'notification-daemon\.enable|notification-daemon\]' modules/hosts; then
fail "hosts must not re-enable or import the notification-daemon leaf"
fi

# 7g. Explicit retained leaf imports (FND-6): deferred leaves stay explicit
# host imports, present on every host, and are not drawn into aspects. Shell
# owns the nix-index input directly (the deleted cli aspect's input).
for leaf in \
modules/shared/niks3-post-deploy.nix \
modules/shared/niks3-upload-client.nix \
modules/shared/nixbuild-ssh.nix \
modules/services/beszel-agent-auth.nix \
modules/services/state-backups.nix; do
test -f "$leaf" || fail "retained leaf $leaf missing"
[ "$(grep -l "modules/.*$(basename "$leaf")" modules/hosts/*/default.nix | wc -l)" -eq 3 ] ||
fail "retained leaf $leaf must be imported by all three hosts"
done
if grep -RnE --include='*.nix' 'niks3-post-deploy|niks3-upload-client|nixbuild-ssh|beszel-agent-auth|state-backups' modules/flake; then
fail "retained leaves must not be drawn into flake-parts/aspect modules"
fi
grep -q 'inputs.nix-index-database.nixosModules.nix-index' modules/flake/aspects.nix || fail "shell aspect must import the nix-index-database module"
test -f modules/flake/_aspects/p10k.zsh || fail "p10k data must live with the private shell implementation"
grep -q 'builtins.readFile ./p10k.zsh' modules/flake/_aspects/shell.nix || fail "shell aspect must render the p10k data file"

echo "check-dendritic-scaffold-contract: PASS"
