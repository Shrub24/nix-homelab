#!/usr/bin/env bash
set -euo pipefail

# Dendritic scaffold contract (openspec changes dendritic-stage-1-scaffold-hosts
# task 4.1/6.4, dendritic-stage-2-foundation-aspects task 6.1,
# dendritic-stage-3-operational-aspects task 4.1,
# dendritic-stage-4-source-model-realignment tasks 4.1/4.2, and
# dendritic-stage-5-shared-source-contributors task 5.2; design DS-1..DS-6,
# FND-1..FND-6, OPS-1..OPS-11, S4-1/S4-4/S4-5/S4-8, S5-6/S5-7).
#
# Prefers observable evaluations; exact source invariants are used only where
# import-tree behavior cannot be observed from outside. Publications are now
# distributed across auto-discovered per-concern contributors, so check 7
# discovers them across the discovered contributor set and verifies per-host
# selections semantically rather than pinning one central file or import order.
# A plain NixOS leaf leaking into flake-parts discovery fails the flake evals
# below loudly, and the Stage 0 path/shape fails check 1 immediately (no
# boundary list file). Negative mutation checks (7i/7j/7k) run against
# throwaway repo copies so the working tree is never modified.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-dendritic-scaffold-contract: $*" >&2
  exit 1
}

ne() { nix eval --no-write-lock-file "$@"; }

# Root-evacuation guard (S5-6, design S5-7): both legacy roots must be gone,
# not merely unlisted. Prints the path of any surviving root. Check 1 and
# mutation 7l-1 call this same predicate.
surviving_evacuated_roots() { # $1 repo root
  local r
  for r in shared storage; do
    test ! -e "$1/modules/$r" || printf '%s\n' "modules/$r"
  done
}

# The temporary import-tree filter literal, read without the flake so it also
# works against throwaway copies. Check 1 and mutation 7l-2 call this.
unconverted_roots() { # $1 repo root -> JSON list
  nix-instantiate --eval --strict --json "$1/modules/flake/_unconverted-nixos-dirs.nix"
}

# Throwaway repo copies for the negative mutation checks (7i/7j). Heavy
# local-only dirs are excluded; the copy keeps flake.nix/flake.lock, modules/,
# lib/, policy/, pkgs/, and secrets/ so pathExists gates behave identically.
MUT_DIRS=()
cleanup_muts() {
  local d
  for d in "${MUT_DIRS[@]:-}"; do
    rm -rf "$d"
  done
}
trap cleanup_muts EXIT
make_copy() { # prints path to a fresh repo copy
  local d
  d="$(mktemp -d /tmp/scaffold-mut.XXXXXX)"
  MUT_DIRS+=("$d")
  tar -C "$ROOT" \
    --exclude=.git --exclude=.jj --exclude=opentofu \
    --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
    --exclude=.cortexkit --exclude=.tmp --exclude=.ruff_cache \
    --exclude=.pi --exclude=.firecrawl \
    -cf - . | tar -C "$d" -xf -
  printf '%s' "$d"
}

# --- 1. Temporary import-tree boundary (DS-1) --------------------------------

LIST_FILE="modules/flake/_unconverted-nixos-dirs.nix"
test -f "$LIST_FILE" || fail "$LIST_FILE missing (Stage 1 boundary)"

# The named list must cover the plain-NixOS roots exactly (order is part of
# the contract so drift shows up as a visible diff). Stage 2 (foundation
# aspects) removed `core` and `profiles` after their contents became aspect
# contributors or were deleted. Stage 5 removed `shared` and `storage` after
# their leaves were relocated beside their aspect owners or deleted (S5-6).
actual="$(unconverted_roots "$ROOT")"
if [ "$actual" != '["applications","hosts","providers","services"]' ]; then
  fail "unconverted-dir list drifted from the Stage 5 four roots: $actual"
fi
# (Exact equality also proves no underscore path is enumerated here: import-tree
# underscore semantics, not this list, owns host-private files.)
for dir in applications hosts providers services; do
  test -d "modules/$dir" || fail "excluded root modules/$dir must exist"
done
# Root evacuation (S5-6): the two removed roots must be gone, not merely
# unlisted. A fake shrink that drops an entry while the directory survives
# fails here.
surviving="$(surviving_evacuated_roots "$ROOT")"
[ -z "$surviving" ] || fail "evacuated roots must be deleted (S5-6 root evacuation): $surviving"

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

# --- 7. Foundation and operational aspects (FND-1..FND-6, OPS-1..OPS-11) ----
# (openspec changes dendritic-stage-2-foundation-aspects task 6.1,
# dendritic-stage-3-operational-aspects task 4.1, and
# dendritic-stage-4-source-model-realignment task 4.1; design S4-5, S4-8)
#
# flake.modules.nixos is an internal flake-parts option, so publication
# exactness is discovered across the auto-discovered contributor set (not one
# central file) and the per-host registry selections are verified semantically,
# independent of import order. The selection-is-enablement contract is then
# proven observationally per host below. FND-2 typed facts and the boot/`/build`
# render are exact evaluated values, not restatements of module source.

# Files import-tree actually treats as first-party flake-parts contributors:
# modules/ minus the four enumerated unconverted roots and minus underscore
# private paths (import-tree underscore semantics, matching flake.nix filterNot).
discovered_contributors() { # $1 repo root
  find "$1/modules" -type f -name '*.nix' \
    ! -path '*/_*' \
    ! -path '*/applications/*' ! -path '*/hosts/*' ! -path '*/providers/*' \
    ! -path '*/services/*' \
    -print
}
publication_files() { # $1 repo root -> discovered files that define a publication
  local f
  while IFS= read -r f; do
    if grep -qE '^[[:space:]]*flake\.modules\.nixos\.[a-z-]+[[:space:]]*=' "$f"; then
      printf '%s\n' "$f"
    fi
  done < <(discovered_contributors "$1")
}
pub_names_of() { # $1 repo root -> sorted flake.modules.nixos.<name> definitions
  discovered_contributors "$1" \
    | xargs -r grep -hoE '^[[:space:]]*flake\.modules\.nixos\.[a-z-]+[[:space:]]*=' \
    | sed -E 's/^[[:space:]]*//; s/[[:space:]]*=$//' | LC_ALL=C sort -u
}
registry_selections() { # $1 repo root -> "host aspect" pairs, in source order
  awk '
    /^      [a-z0-9-]+ = \{/ { host = $1; next }
    host != "" {
      s = $0
      while (match(s, /aspects\.[a-z-]+/)) {
        print host, substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$1/modules/flake/registry.nix"
}
host_aspects() { # $1 repo root, $2 host -> sorted selected aspect names
  registry_selections "$1" | awk -v h="$2" '$1 == h { print $2 }' | LC_ALL=C sort -u
}
host_leaf_imports_of() { # $1 dir
  grep -RnE --include='*.nix' 'modules/(services/(state-backups|beszel-agent-auth)|flake/(_backups/(niks3-upload-client|niks3-post-deploy)|_builder-access/nixbuild-ssh))\.nix' "$1/modules/hosts" || true
}

# 7a. Exactly fourteen publications are discovered across the distributed
# contributors: the infrastructure support quartet plus the ten host-selected
# deployment aspects (base, shell, networking, tailscale, notify, backups,
# builder-access, observability-agent, dj, identity-client). Registry references
# are not definition sites. No central publication file or private filename
# inventory is pinned.
expected_pub="$(printf '%s\n' \
flake.modules.nixos.backups \
flake.modules.nixos.base \
flake.modules.nixos.builder-access \
flake.modules.nixos.dj \
flake.modules.nixos.fleet-packages \
flake.modules.nixos.identity-client \
flake.modules.nixos.networking \
flake.modules.nixos.notify \
flake.modules.nixos.observability-agent \
flake.modules.nixos.oci-images \
flake.modules.nixos.provenance \
flake.modules.nixos.shell \
flake.modules.nixos.tailscale \
flake.modules.nixos.web-policy)"
pub_names="$(pub_names_of "$ROOT")"
if [ "$pub_names" != "$expected_pub" ]; then
  fail "discovered publications drifted from the support quartet + ten deployment aspects: $pub_names"
fi
if grep -RnE --include='*.nix' 'flake\.modules\.nixos\.cli|_aspects/cli|aspects\.cli' modules; then
fail "the deleted cli aspect must not be resurrected"
fi
# Underscore-private implementation leaves are not auto-discovered (import-tree
# underscore semantics, proven by the successful flake evals below) and must
# not smuggle a publication past discovery. Owner assertions stay where they
# are semantically meaningful: typed base facts (7c) and the shell leaf + p10k
# data (7g). No exact private-filename inventory is pinned.
for priv in _aspects _backups _builder-access; do
  test -d "modules/flake/$priv" || fail "private implementation dir modules/flake/$priv missing"
  if grep -RnE --include='*.nix' 'flake\.modules\.nixos\.[a-z-]+[[:space:]]*=' "modules/flake/$priv"; then
    fail "underscore-private paths must not publish flake.modules.nixos aspects ($priv)"
  fi
done

# 7b. Per-host registry selections are semantically exact: every host selects
# the support quartet and the eight foundation/operational aspects; OCI and LA
# additionally select identity-client, home-forge selects dj instead. Aspect
# order is not part of the contract, and host assemblies receive aspects only
# via the registry.
support_quartet="aspects.provenance
aspects.oci-images
aspects.fleet-packages
aspects.web-policy"
foundation_operational="aspects.base
aspects.shell
aspects.networking
aspects.tailscale
aspects.notify
aspects.backups
aspects.builder-access
aspects.observability-agent"
regular_sel="$(printf '%s\n%s\naspects.identity-client\n' "$support_quartet" "$foundation_operational" | LC_ALL=C sort)"
forge_sel="$(printf '%s\n%s\naspects.dj\n' "$support_quartet" "$foundation_operational" | LC_ALL=C sort)"
for host in oci-melb-1 la-admin-1; do
  [ "$(host_aspects "$ROOT" "$host")" = "$regular_sel" ] ||
    fail "registry: $host must select the support quartet + eight deployment aspects + identity-client: $(host_aspects "$ROOT" "$host")"
done
[ "$(host_aspects "$ROOT" home-forge)" = "$forge_sel" ] ||
  fail "registry: home-forge must select the support quartet + eight deployment aspects + dj: $(host_aspects "$ROOT" home-forge)"
if grep -RnE 'aspects\.|_aspects' modules/hosts; then
fail "host assemblies must receive foundation aspects only via the registry"
fi
test ! -e modules/core || fail "modules/core must be deleted (FND-6)"
test ! -e modules/profiles || fail "modules/profiles must be deleted (FND-6)"
if grep -RnE --include='*.nix' 'import.*modules/(core|profiles)/' modules; then
fail "no module may import a deleted core/profiles path"
fi

# 7b-2. Composition is relationship-specific (S4-5). A public aspect definition
# may only import another public aspect when an adjacent comment justifies it as
# intrinsic composition; no such import exists today. Registry selection
# references are not definition sites and are not scanned.
unjustified_aspect_refs_of() { # $1 file -> "<file>:<line>" for unmarked aspect refs
  awk '
    /aspects\.[a-z-]+/ { ref[NR] = 1 }
    /^[[:space:]]*#.*intrinsic/ { just[NR] = 1 }
    END {
      for (n in ref) {
        ok = 0
        for (i = n - 2; i <= n + 2; i++) if (i in just) ok = 1
        if (!ok) print FILENAME ":" n
      }
    }
  ' "$1"
}
unjustified_aspect_refs="$(publication_files "$ROOT" | while IFS= read -r f; do
  unjustified_aspect_refs_of "$f"
done)"
[ -z "$unjustified_aspect_refs" ] ||
  fail "direct public-aspect imports require an adjacent intrinsic-composition justification: $unjustified_aspect_refs"

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
# ownership, notify composition with the repo packages, and DJ selection
# enablement (S4-4: forge true; OCI/LA discovered-but-unselected false).
probe() { # $1 host, $2 expected JSON (python dict literal)
  local host="$1" json
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
dj = c.applications.dj.enable or false;
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

probe oci-melb-1 '{"bootLoader":"grub","buildTmpfsSize":"8G","systemdBoot":false,"grub":true,"efiRemovable":true,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":"1200","tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemon":true,"dj":false}'
probe la-admin-1 '{"bootLoader":"systemd-boot","buildTmpfsSize":"50%","systemdBoot":true,"grub":false,"efiRemovable":false,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":"1200","tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemon":true,"dj":false}'
probe home-forge '{"bootLoader":"systemd-boot","buildTmpfsSize":"50%","systemdBoot":true,"grub":false,"efiRemovable":false,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":null,"tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemon":true,"dj":true}'

# 7d-2. Stage 5 web/identity observables (S5-4, S5-5, S5-8). web-policy is an
# all-host infrastructure-support selection: config.repo.web resolves on every
# host and the ntfy serverUrl default derives from it (LA keeps its explicit
# loopback override). identity-client is selected on OCI/LA only: both expose
# the policy-derived provider URL, clients, hostAuth, and Kanidm URI; forge
# evaluates with services.identity absent (probed via `or {}`).
probe_web_identity() { # $1 host, $2 expected JSON (python dict literal)
  local host="$1" json
  json="$(ne --json --apply 'c: {
    webHosts = builtins.attrNames (c.repo.web.hosts or {});
    webCatalog = builtins.attrNames (c.repo.web.catalog or {});
    ntfyUrl = c.services.notification-daemon.ntfy.serverUrl or "";
    ntfyDefault = c.repo.web.catalog."ntfy-admin".publicUrl or "";
    providerUrl = (c.services.identity.oidc.providerUrl or null);
    hostAuth = (c.services.identity.hostAuth.enable or false);
    kanidmUri = if (c.services.kanidm.client.enable or false) then (c.services.kanidm.client.settings.uri or null) else null;
  }' "path:.#nixosConfigurations.${host}.config")" ||
  fail "${host}: web/identity probe does not evaluate"
  python3 - "$host" "$2" "$json" <<'PYEOF' || fail "${host}: observable web/identity contract violated"
import json, sys
host, exp_raw, got_raw = sys.argv[1], sys.argv[2], sys.argv[3]
exp = json.loads(exp_raw)
got = json.loads(got_raw)
errs = []
for k, v in exp.items():
    if k == "ntfyOverride":
        continue  # probe-control flag, not an observable
    if got.get(k) != v:
        errs.append(f"{k}: got {got.get(k)!r} want {v!r}")
# web-policy resolves on every host and the ntfy default is policy-derived.
# currentHost is policy data (only la-admin-1 is a web-services host today);
# the contract is that repo.web evaluates and the catalog resolves.
if not got["webHosts"] or not got["webCatalog"]:
    errs.append(f"repo.web did not resolve: {got['webHosts']!r}/{got['webCatalog']!r}")
if got["ntfyDefault"] == "":
    errs.append("repo.web.catalog.ntfy-admin.publicUrl is empty")
# LA overrides ntfy to loopback; every other host must derive it from policy.
if not exp.get("ntfyOverride") and got["ntfyUrl"] != got["ntfyDefault"]:
    errs.append(f"ntfyUrl: {got['ntfyUrl']!r} != policy default {got['ntfyDefault']!r}")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

# OCI/forge derive ntfy from policy; LA overrides to loopback.
probe_web_identity oci-melb-1 '{"providerUrl":"https://id.shrublab.xyz","hostAuth":true,"kanidmUri":"https://id.shrublab.xyz"}'
probe_web_identity la-admin-1 '{"providerUrl":"https://id.shrublab.xyz","hostAuth":true,"kanidmUri":"https://id.shrublab.xyz","ntfyUrl":"http://127.0.0.1:2586","ntfyOverride":true}'
probe_web_identity home-forge '{"providerUrl":null,"hostAuth":false,"kanidmUri":null}'
# Identity clients are the policy-derived oauth2 set on OCI/LA; forge has none.
for host in oci-melb-1 la-admin-1; do
  clients="$(ne --raw --apply 'c: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames (c.services.identity.oidc.clients or {})))' "path:.#nixosConfigurations.${host}.config")" ||
    fail "${host}: identity clients do not evaluate"
  [ "$clients" = '["beszel","cloudflare-access","karakeep","paperless","quantum","termix"]' ] ||
    fail "${host}: identity clients drifted: $clients"
done
# Forge must not activate identity: services.identity is absent, not merely disabled.
forge_identity="$(ne --raw --apply 'c: builtins.toJSON (builtins.attrNames (c.services.identity or {}))' 'path:.#nixosConfigurations.home-forge.config')" ||
  fail "home-forge: identity absence probe does not evaluate"
[ "$forge_identity" = '[]' ] || fail "home-forge must not activate identity (services.identity present: $forge_identity)"

# 7d-3. Recovery observable (S5-8): the relocated host-recovery leaf stays owned
# by the base aspect, so both units are present on every host.
for host in oci-melb-1 la-admin-1 home-forge; do
  recovery="$(ne --raw --apply 'c: builtins.toJSON {
    svc = c.systemd.services ? host-recovery-reboot;
    timer = c.systemd.timers ? host-recovery-reboot;
  }' "path:.#nixosConfigurations.${host}.config")" ||
    fail "${host}: recovery probe does not evaluate"
  [ "$recovery" = '{"svc":true,"timer":true}' ] ||
    fail "${host}: host-recovery units missing after relocation: $recovery"
done

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
grep -q 'imports = \[ ../services/notification-daemon \]' modules/flake/notify.nix || fail "notify aspect must compose the notification-daemon leaf"
grep -q 'enable = true;' modules/flake/notify.nix || fail "notify aspect must enable the daemon"
grep -q 'package = packages.notification-daemon;' modules/flake/notify.nix || fail "notify aspect must pass the repo notification-daemon package"
grep -q 'notifyPackage = packages.notify;' modules/flake/notify.nix || fail "notify aspect must pass the repo notify package"
if grep -RnE 'notification-daemon\.enable|notification-daemon\]' modules/hosts; then
fail "hosts must not re-enable or import the notification-daemon leaf"
fi

# 7g. Stage 3 composition ownership (OPS-1..OPS-9): the five deferred leaves
# exist (relocated beside their aspect owners under underscore-private paths,
# S5-3) and are imported by exactly their owning aspect; host assemblies never
# import, enable, or conventionally bind them; the upstream niks3-auto-upload
# module is imported only by the backups aspect (never by the registry); the
# retired fleet.nixbuild-ssh option is gone; and the post-deploy leaf takes
# its filter package from the typed option injected by the aspect (no hidden
# fleet-packages dependency). The services import-tree exclusion is unchanged
# (OPS-9, check 1).
for leaf in \
  modules/services/state-backups.nix \
  modules/flake/_backups/niks3-upload-client.nix \
  modules/flake/_backups/niks3-post-deploy.nix \
  modules/flake/_builder-access/nixbuild-ssh.nix \
  modules/services/beszel-agent-auth.nix; do
  test -f "$leaf" || fail "operational leaf $leaf missing"
done
grep -q '../services/state-backups.nix' modules/flake/backups.nix || fail "backups aspect must import the state-backups leaf"
grep -q './_backups/niks3-upload-client.nix' modules/flake/backups.nix || fail "backups aspect must import the niks3-upload-client leaf"
grep -q './_backups/niks3-post-deploy.nix' modules/flake/backups.nix || fail "backups aspect must import the niks3-post-deploy leaf"
grep -q './_builder-access/nixbuild-ssh.nix' modules/flake/builder-access.nix || fail "builder-access aspect must import the nixbuild-ssh leaf"
grep -q '../services/beszel-agent-auth.nix' modules/flake/observability-agent.nix || fail "observability-agent aspect must import the beszel-agent-auth leaf"
grep -q 'inputs.niks3.nixosModules.niks3-auto-upload' modules/flake/backups.nix || fail "backups aspect must import the upstream niks3-auto-upload module"
# Narrowed to the exact upstream module import (S5-7): the relocated
# post-deploy leaf mentions the `services.niks3-auto-upload` option, which must
# not false-positive as a second import site.
if grep -RnE 'inputs\.niks3\.nixosModules\.niks3-auto-upload' modules/flake | grep -v '^modules/flake/backups.nix:'; then
  fail "niks3-auto-upload must be imported only by the backups aspect (not the registry)"
fi
grep -qE 'inputs\.niks3\.nixosModules\.niks3[[:space:]]*$' modules/flake/registry.nix || fail "OCI must keep the niks3 server module import"
[ -z "$(host_leaf_imports_of "$ROOT")" ] || fail "host assemblies must not import the five operational leaves directly"
if grep -RnE 'services\.(state-backups|niks3-post-deploy|niks3-auto-upload|beszel-agent-auth)\.enable' modules/hosts; then
  fail "host assemblies must not repeat operational enablement"
fi
if grep -RnE 'state-backups\.(secretFile|bucket)|beszel-agent-auth\.secretFiles|shrublab-backup-' modules/hosts; then
  fail "host assemblies must not repeat conventional secret/bucket bindings"
fi
if grep -RnE '^[^#]*fleet\.nixbuild-ssh' modules; then
  fail "the retired fleet.nixbuild-ssh option must be gone"
fi
grep -q 'filterPackage' modules/flake/_backups/niks3-post-deploy.nix || fail "post-deploy leaf must define the typed filterPackage option"
grep -q 'type = lib.types.package' modules/flake/_backups/niks3-post-deploy.nix || fail "filterPackage must be a typed package option"
grep -q 'filterPackage = packages.nix-path-filter' modules/flake/backups.nix || fail "backups aspect must inject nix-path-filter into post-deploy"
if grep -nE '^[^#]*config\.repo\.packages' modules/flake/_backups/niks3-post-deploy.nix; then
  fail "post-deploy leaf must not read config.repo.packages (no hidden fleet-packages dependency)"
fi
grep -q 'inputs.nix-index-database.nixosModules.nix-index' modules/flake/shell.nix || fail "shell aspect must import the nix-index-database module"
test -f modules/flake/_aspects/p10k.zsh || fail "p10k data must live with the private shell implementation"
grep -q 'builtins.readFile ./p10k.zsh' modules/flake/_aspects/shell.nix || fail "shell aspect must render the p10k data file"

# 7g-2. Identity is the multi-contributor single-aspect merge (S5-5): two
# discovered top-level contributors each nest their body directly inside the
# same identity-client publication, with no private leaf, wrapper, or
# cross-import; no host or application file imports either contributor
# directly (discovery + registry selection is the only path).
for idf in modules/flake/identity-oidc.nix modules/flake/kanidm-host-auth.nix; do
  test -f "$idf" || fail "identity contributor $idf missing"
  grep -q 'flake.modules.nixos.identity-client' "$idf" || fail "$idf must publish identity-client"
done
test ! -e modules/flake/_identity-client || fail "no _identity-client private leaf directory may exist (S5-5)"
if grep -RnE --include='*.nix' 'identity-oidc|kanidm-host-auth' modules/hosts modules/applications; then
  fail "no host or application file may import an identity contributor directly (S5-5)"
fi

# 7h. Stage 3 observable contract (OPS-1..OPS-8): derived bucket and secret
# path, selection-is-enablement for backups/post-deploy/client/Beszel, OCI
# token ownership and loopback endpoint, builder SSH trust, Beszel KEY/TOKEN
# scopes, and the notify-owned monitor wiring (OPS-4).
probe_ops() { # $1 host, $2 expected JSON (python dict literal)
  local host="$1" json
  json="$(ne --json --apply 'c: {
    bucket = c.services.state-backups.bucket or "";
    secretFile = c.services.state-backups.secretFile or "";
    sbEnable = c.services.state-backups.enable or false;
    postEnable = c.services.niks3-post-deploy.enable or false;
    clientEnable = c.services.niks3-auto-upload.enable or false;
    serverUrl = c.services.niks3-auto-upload.serverUrl or "";
    tokenOwner = (c.sops.secrets.niks3_api_token.owner or null);
    niks3Srv = c.services.niks3.enable or false;
    beszelEnable = c.services.beszel-agent-auth.enable or false;
    beszelAgent = c.services.beszel.agent.enable or false;
    beszelHost = (c.services.beszel-agent-auth.secretFiles.host or "");
    beszelKeySops = (baseNameOf (c.sops.secrets.beszel_agent_key.sopsFile or ""));
    beszelTokenSops = (baseNameOf (c.sops.secrets.beszel_agent_token.sopsFile or ""));
    monitor = c.services.notification-daemon.monitor.enable or false;
    onFailure = (c.systemd.services."restic-backups-state".onFailure or []);
    nixbuildHosts = (c.programs.ssh.knownHosts.nixbuild.hostNames or []);
    nixbuildExtra = c.programs.ssh.extraConfig or "";
    stagingRoot = c.services.state-backups.stagingRoot or "";
    hostCorePaths = (c.services.state-backups.services.host-core.paths or []);
  }' "path:.#nixosConfigurations.${host}.config")" ||
  fail "${host}: operational probe does not evaluate"
  python3 - "$host" "$2" "$json" <<'PYEOF' || fail "${host}: observable operational contract violated"
import json, sys
host, exp_raw, got_raw = sys.argv[1], sys.argv[2], sys.argv[3]
exp = json.loads(exp_raw)
got = json.loads(got_raw)
errs = []
for k, v in exp.items():
    if got.get(k) != v:
        errs.append(f"{k}: got {got.get(k)!r} want {v!r}")
if not got["secretFile"].endswith(f"/secrets/hosts/{host}/system.yaml"):
    errs.append(f"secretFile: {got['secretFile']!r} not the conventional host secret path")
if not got["beszelHost"].endswith(f"/secrets/hosts/{host}/system.yaml"):
    errs.append(f"beszelHost: {got['beszelHost']!r} not the conventional host secret path")
if "svc-monitor@restic-backups-state.service" not in got["onFailure"]:
    errs.append(f"onFailure: missing svc-monitor wiring in {got['onFailure']!r}")
if "eu.nixbuild.net" not in got["nixbuildHosts"]:
    errs.append(f"nixbuildHosts: {got['nixbuildHosts']!r} missing eu.nixbuild.net")
if "eu.nixbuild.net" not in got["nixbuildExtra"]:
    errs.append("nixbuildExtra: missing eu.nixbuild.net host config")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

probe_ops oci-melb-1 '{"bucket":"shrublab-backup-oci-melb-1","sbEnable":true,"postEnable":true,"clientEnable":true,"serverUrl":"http://127.0.0.1:5751","tokenOwner":"niks3","niks3Srv":true,"beszelEnable":true,"beszelAgent":true,"beszelKeySops":"common.yaml","beszelTokenSops":"system.yaml","monitor":true,"stagingRoot":"/srv/data/state-backups","hostCorePaths":[]}'
probe_ops la-admin-1 '{"bucket":"shrublab-backup-la-admin-1","sbEnable":true,"postEnable":true,"clientEnable":true,"serverUrl":"http://oci-melb-1:5751","tokenOwner":null,"niks3Srv":false,"beszelEnable":true,"beszelAgent":true,"beszelKeySops":"common.yaml","beszelTokenSops":"system.yaml","monitor":true,"stagingRoot":"/srv/data/state-backups","hostCorePaths":[]}'
probe_ops home-forge '{"bucket":"shrublab-backup-home-forge","sbEnable":true,"postEnable":true,"clientEnable":true,"serverUrl":"http://oci-melb-1:5751","tokenOwner":null,"niks3Srv":false,"beszelEnable":true,"beszelAgent":true,"beszelKeySops":"common.yaml","beszelTokenSops":"system.yaml","monitor":true,"stagingRoot":"/srv/data/state-backups","hostCorePaths":["/etc/ssh"]}'

# 7i. Negative mutation checks (OPS-4, OPS-11, OPS-3/OPS-8 bootstrap gates).
# Each runs against a throwaway copy so the working tree is never modified.
# NixOS assertions are only forced by the toplevel derivation, so negative
# evals target system.build.toplevel.drvPath.
expect_eval_fail() { # $1 copy, $2 host, $3 expected message substring
  local d="$1" host="$2" want="$3" out rc
  set +e
  out="$(nix eval --no-write-lock-file --raw "path:${d}#nixosConfigurations.${host}.config.system.build.toplevel.drvPath" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "mutation ${host}: expected eval failure, got success"
  case "$out" in
    *"$want"*) ;;
    *) fail "mutation ${host}: expected message containing '$want', got: $(printf '%s' "$out" | tail -3)" ;;
  esac
}

# 7i-1. Backups without notify fails with the named monitor assertion (OPS-4).
# The host's own notification-daemon block is removed too, otherwise the
# undefined-option error masks the assertion.
D="$(make_copy)"
sed -i '/aspects.notify/d' "$D/modules/flake/registry.nix"
python3 - "$D/modules/hosts/oci-melb-1/default.nix" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
start = s.index("notification-daemon = {")
i = s.index("{", start)
depth = 0
while True:
    if s[i] == "{": depth += 1
    elif s[i] == "}":
        depth -= 1
        if depth == 0: break
    i += 1
end = i + 1
if end < len(s) and s[end] == ";":
    end += 1
open(p, "w").write(s[:start] + s[end:])
PY
expect_eval_fail "$D" oci-melb-1 "services.notification-daemon.monitor.enable must be true"

# 7i-2. A derived bucket outside the S3 rule fails with the named assertion
# (OPS-11). nixpkgs itself rejects a trailing-hyphen hostName at the type
# level, so the tamper forces the trailing hyphen into the derived bucket. The
# bucket expression lives in the backups concern contributor (S4-2).
D="$(make_copy)"
python3 - "$D/modules/flake/backups.nix" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'bucketName = "shrublab-backup-${config.networking.hostName}";'
new = 'bucketName = "shrublab-backup-${config.networking.hostName}-";'
assert old in s
open(p, "w").write(s.replace(old, new))
PY
expect_eval_fail "$D" oci-melb-1 "must be a valid S3 bucket name"

# 7i-3. Missing conventional host secret disables backups/post-deploy/Beszel
# without failing the base activation (OPS-3/OPS-8 two-step bootstrap).
D="$(make_copy)"
mv "$D/secrets/hosts/home-forge/system.yaml" "$D/secrets/hosts/home-forge/system.yaml.moved"
json="$(ne --json --apply 'c: {
  sb = c.services.state-backups.enable or false;
  post = c.services.niks3-post-deploy.enable or false;
  client = c.services.niks3-auto-upload.enable or false;
  beszel = c.services.beszel-agent-auth.enable or false;
  agent = c.services.beszel.agent.enable or false;
}' "path:${D}#nixosConfigurations.home-forge.config")" ||
fail "home-forge without host secrets must still evaluate (two-step bootstrap)"
python3 - "$json" <<'PY' || fail "home-forge without host secrets must disable backups/post-deploy/Beszel: $json"
import json, sys
got = json.loads(sys.argv[1])
want = {"sb": False, "post": False, "client": False, "beszel": False, "agent": False}
if got != want:
    raise SystemExit(f"got {got!r} want {want!r}")
PY

# 7j. Tamper-proof source checks: the 7a/7b/7g pipelines must detect a
# Stage-2-shaped regression (aspect unpublished, selection dropped, leaf
# re-imported by a host) on a throwaway copy. The publication tamper targets
# one distributed contributor (backups.nix), not the deleted central file. The
# re-import anchors on a host import line that survives Stage 5 and inserts a
# relocated private leaf path so host_leaf_imports_of is exercised.
D="$(make_copy)"
sed -i 's/flake.modules.nixos.backups =/flake.modules.nixos.backups-tampered =/' "$D/modules/flake/backups.nix"
sed -i '/aspects.backups/d' "$D/modules/flake/registry.nix"
sed -i '/modules\/services\/paperless/a\  ../../../modules/flake/_backups/niks3-post-deploy.nix' "$D/modules/hosts/oci-melb-1/default.nix"
[ "$(pub_names_of "$D")" != "$expected_pub" ] ||
fail "7a publication check must detect an unpublished backups aspect"
[ "$(host_aspects "$D" oci-melb-1)" != "$regular_sel" ] ||
fail "7b selection check must detect a dropped aspect"
[ -n "$(host_leaf_imports_of "$D")" ] ||
fail "7g host-import check must detect a re-imported leaf"

# 7k. DJ selection semantics (S4-4, S4-8; tasks 4.1/4.2). DJ enablement comes
# from selecting the dj deployment aspect, not from discovery. The observable
# is the evaluated applications.dj.enable value; the throwaway mutations below
# prove discovery-only placement does not activate and selection owns
# enablement.
dj_enabled() { # $1 repo root, $2 host -> "true"/"false" through aspect selection
  local d="$1" host="$2" out rc
  set +e
  out="$(nix eval --no-write-lock-file --raw --apply \
    'c: if ((c.applications.dj or { }).enable or false) then "true" else "false"' \
    "path:${d}#nixosConfigurations.${host}.config" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "dj probe ${host}: config does not evaluate: $(printf '%s' "$out" | tail -2)"
  printf '%s' "$out"
}
# Discovery alone is not placement: the dj publication exists for every host,
# yet OCI/LA never select it and expose no DJ contract, while forge selects it
# and evaluates DJ enabled.
[ "$(dj_enabled "$ROOT" home-forge)" = true ] || fail "unmodified home-forge must activate DJ via aspect selection"
[ "$(dj_enabled "$ROOT" oci-melb-1)" = false ] || fail "unmodified oci-melb-1 must not activate discovered-but-unselected DJ"
[ "$(dj_enabled "$ROOT" la-admin-1)" = false ] || fail "unmodified la-admin-1 must not activate discovered-but-unselected DJ"

# 7k-1. Removing DJ's top-level enablement from the selected dj aspect leaves
# the selection in place but no longer satisfies forge's DJ contract. The test
# names the failure (no eval assertion exists for a disabled aspect).
D="$(make_copy)"
sed -i '/applications\.dj\.enable = true;/d' "$D/modules/flake/dj.nix"
[ "$(dj_enabled "$D" home-forge)" = false ] ||
  fail "7k-1: forge must fail the DJ enablement contract when the selected dj aspect does not set applications.dj.enable"

# 7k-2. Removing one distributed required contributor is detected by the
# publication inventory (there is no central publication file to fall back on).
D="$(make_copy)"
rm "$D/modules/flake/base.nix"
[ "$(pub_names_of "$D")" != "$expected_pub" ] ||
  fail "7k-2: publication discovery must detect a deleted distributed contributor"

# 7k-3. A new direct public-aspect import without intrinsic justification is
# rejected by the 7b-2 scanner, and the same import with the marker is allowed.
D="$(make_copy)"
printf '\n  flake.modules.nixos.base = { imports = [ aspects.notify ]; };\n' >>"$D/modules/flake/base.nix"
[ -n "$(unjustified_aspect_refs_of "$D/modules/flake/base.nix")" ] ||
  fail "7k-3: scanner must reject a direct public-aspect import without intrinsic justification"
printf '  # intrinsic composition: base requires notify placement\n' >>"$D/modules/flake/base.nix"
[ -z "$(unjustified_aspect_refs_of "$D/modules/flake/base.nix")" ] ||
  fail "7k-3: scanner must accept a direct public-aspect import with adjacent intrinsic justification"

# 7l. Stage 5 semantic negative mutations (S5-6, S5-7). Each runs against a
# throwaway copy so the working tree is never modified, and each fails for its
# intended semantic reason rather than a generic parse/eval error. Contributor
# deletion is detected through the missing OIDC or host-auth/Kanidm
# observable/eval — never a missing publication, because the sibling
# contributor still defines identity-client.

# 7l-1. A surviving evacuated root must be rejected even when the filter no
# longer lists it (a fake shrink that untracks the directory instead of
# deleting it). The shared root-evacuation predicate must name the survivor.
D="$(make_copy)"
mkdir -p "$D/modules/storage"
touch "$D/modules/storage/disko-root.nix"
[ "$(surviving_evacuated_roots "$D")" = "modules/storage" ] ||
  fail "7l-1: root-evacuation predicate must detect a surviving modules/storage"

# 7l-2. A fake filter shrink must be rejected: dropping a still-present root's
# boundary entry (services) leaves the exact four-root set wrong even though the
# directory survives unconverted. This proves the four-root equality is
# load-bearing and order-independent, independent of the root-evacuation guard.
D="$(make_copy)"
sed -i 's/"services"//' "$D/modules/flake/_unconverted-nixos-dirs.nix"
test -d "$D/modules/services" || fail "7l-2: prepared copy must still contain modules/services"
[ "$(unconverted_roots "$D")" != '["applications","hosts","providers","services"]' ] ||
  fail "7l-2: fake filter shrink must break the exact four-root set"

# 7l-3. Private leaves must stay undiscoverable/non-publishing. A publication
# smuggled into an underscore-private path is caught by the 7a private-owner scan
# (same grep the working tree uses), and is invisible to discovery.
D="$(make_copy)"
printf '\n  flake.modules.nixos.evil-pub = { };\n' >>"$D/modules/flake/_backups/niks3-upload-client.nix"
grep -RnE --include='*.nix' 'flake\.modules\.nixos\.[a-z-]+[[:space:]]*=' "$D/modules/flake/_backups" >/dev/null ||
  fail "7l-3: private-owner scan must reject a publication under _backups"
case "$(pub_names_of "$D")" in
  *evil-pub*) fail "7l-3: an underscore-private publication must not be discovered" ;;
esac

# 7l-4. Relocated private leaves and identity contributors must not be imported
# directly by a host. Fresh imports inserted on the surviving
# `modules/services/paperless` line are detected by host_leaf_imports_of (for
# the relocated leaf) and by the 7g-2 identity-import grep (for the
# contributor) — both anchored on a line that survives this change, so the
# checks are exercised non-vacuously.
D="$(make_copy)"
sed -i '/modules\/services\/paperless/a\  ../../../modules/flake/_backups/niks3-post-deploy.nix' "$D/modules/hosts/oci-melb-1/default.nix"
[ -n "$(host_leaf_imports_of "$D")" ] ||
  fail "7l-4: host_leaf_imports_of must detect a directly re-imported relocated leaf"
sed -i '/modules\/services\/paperless/a\  ../../../modules/flake/identity-oidc.nix' "$D/modules/hosts/oci-melb-1/default.nix"
grep -RnE --include='*.nix' 'identity-oidc|kanidm-host-auth' "$D/modules/hosts" >/dev/null ||
  fail "7l-4: identity-import grep must detect a directly imported identity contributor"

# 7l-5. Identity must not activate on forge. Adding aspects.identity-client to
# the forge record is detected through the missing-services.identity observable,
# not a publication diff.
D="$(make_copy)"
sed -i '/aspects\.dj/i\            aspects.identity-client' "$D/modules/flake/registry.nix"
forge_identity_mut="$(ne --raw --apply 'c: builtins.toJSON (builtins.attrNames (c.services.identity or {}))' \
  "path:${D}#nixosConfigurations.home-forge.config")" ||
  fail "7l-5: forge identity mutation probe must evaluate"
[ "$forge_identity_mut" != '[]' ] ||
  fail "7l-5: forge must expose identity activation when identity-client is wrongly selected"

# 7l-6. Deleting the OIDC contributor removes OIDC behavior/eval while the
# sibling kanidm contributor still publishes identity-client. Detection is the
# missing services.identity.oidc option (eval failure), never a publication.
D="$(make_copy)"
rm "$D/modules/flake/identity-oidc.nix"
[ "$(pub_names_of "$D" | grep -c 'identity-client')" -ge 1 ] ||
  fail "7l-6: sibling contributor must still publish identity-client after OIDC deletion"
set +e
oidc_out="$(nix eval --no-write-lock-file --raw \
  "path:${D}#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath" 2>&1)"
oidc_rc=$?
set -e
[ "$oidc_rc" -ne 0 ] || fail "7l-6: deleting the OIDC contributor must break OCI identity eval"
case "$oidc_out" in
  *"services.identity.oidc' does not exist"*) ;;
  *) fail "7l-6: expected missing services.identity.oidc, got: $(printf '%s' "$oidc_out" | tail -3)" ;;
esac

# 7l-7. Deleting the Kanidm host-auth contributor removes host-auth/Kanidm
# behavior/eval while the sibling OIDC contributor still publishes
# identity-client. Detection is the missing services.identity.hostAuth option.
D="$(make_copy)"
rm "$D/modules/flake/kanidm-host-auth.nix"
[ "$(pub_names_of "$D" | grep -c 'identity-client')" -ge 1 ] ||
  fail "7l-7: sibling contributor must still publish identity-client after host-auth deletion"
set +e
hostauth_out="$(nix eval --no-write-lock-file --raw \
  "path:${D}#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath" 2>&1)"
hostauth_rc=$?
set -e
[ "$hostauth_rc" -ne 0 ] || fail "7l-7: deleting the host-auth contributor must break OCI Kanidm eval"
case "$hostauth_out" in
  *"services.identity.hostAuth' does not exist"*) ;;
  *) fail "7l-7: expected missing services.identity.hostAuth, got: $(printf '%s' "$hostauth_out" | tail -3)" ;;
esac

echo "check-dendritic-scaffold-contract: PASS"
