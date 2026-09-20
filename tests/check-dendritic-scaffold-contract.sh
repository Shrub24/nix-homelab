#!/usr/bin/env bash
set -euo pipefail

# Dendritic scaffold contract (openspec changes dendritic-stage-1-scaffold-hosts
# task 4.1/6.4, dendritic-stage-2-foundation-aspects task 6.1,
# dendritic-stage-3-operational-aspects task 4.1,
# dendritic-stage-4-source-model-realignment tasks 4.1/4.2,
# dendritic-stage-5-shared-source-contributors task 5.2,
# dendritic-stage-6-music-composition tasks 5.1/5.2, and
# dendritic-stage-7-placement-aspects tasks 6.1-6.3;
# feature-owned-service-monitoring tasks 2.1-2.3 and 3.1/3.2 (MON-1..MON-4);
# design DS-1..DS-6,
# FND-1..FND-6, OPS-1..OPS-11, S4-1/S4-4/S4-5/S4-8, S5-6/S5-7, S6-2..S6-11,
# S7-2..S7-9).
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

# Root-evacuation guard (S5-6 design S5-7, S7-8): every converted legacy root
# must be gone, not merely unlisted. Prints the path of any surviving root.
# Check 1 and mutations 7l-1/7n-3 call this same predicate.
surviving_evacuated_roots() { # $1 repo root
  local r
  for r in shared storage applications providers; do
    test ! -e "$1/modules/$r" || printf '%s\n' "modules/$r"
  done
}

# The temporary import-tree filter literal, read without the flake so it also
# works against throwaway copies. Check 1 and mutation 7l-2 call this.
unconverted_roots() { # $1 repo root -> JSON list
  nix-instantiate --eval --strict --json "$1/modules/flake/_unconverted-nixos-dirs.nix"
}

# Throwaway repo copies for the negative mutation checks (7i/7j/7n). Heavy
# local-only dirs are excluded, but the copy keeps flake.nix/flake.lock,
# modules/, lib/, policy/, pkgs/, and the whole secrets/ tree (including
# secrets/opentofu, which host records reference through typed path options and
# which a component-wide --exclude=opentofu pattern used to drop).
MUT_LIST="$(mktemp /tmp/scaffold-mut-list.XXXXXX)"
cleanup_muts() {
  xargs -r rm -rf <"$MUT_LIST"
  rm -f "$MUT_LIST"
}
trap cleanup_muts EXIT
make_copy() { # prints path to a fresh repo copy
  local d
  d="$(mktemp -d /tmp/scaffold-mut.XXXXXX)"
  printf '%s\n' "$d" >>"$MUT_LIST"
  tar -C "$ROOT" \
    --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
    --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
    --exclude=.cortexkit --exclude=.tmp --exclude=.ruff_cache \
    --exclude=.pi --exclude=.firecrawl --exclude=.opencode \
    -cf - . | tar -C "$d" -xf -
  printf '%s' "$d"
}

# --- 1. Temporary import-tree boundary (DS-1) --------------------------------

LIST_FILE="modules/flake/_unconverted-nixos-dirs.nix"
test -f "$LIST_FILE" || fail "$LIST_FILE missing (Stage 1 boundary)"

# The named list must cover the plain-NixOS roots exactly (order is part of
# the contract so drift shows up as a visible diff). Stage 2 (foundation
# aspects) removed `core` and `profiles` after their contents became aspect
# contributors or were deleted. Stage 5 removed `shared` and `storage` (S5-6).
# Stage 7 removed `applications` and `providers` after every implementation
# leaf moved beside its discovered concern owner (S7-4/S7-5/S7-8). This exact
# single-entry equality is the future-work guard: the boundary may not grow
# again, and `services` is the explicit transition backlog.
actual="$(unconverted_roots "$ROOT")"
if [ "$actual" != '["services"]' ]; then
  fail "unconverted-dir list drifted from the final single root (services): $actual"
fi
# (Exact equality also proves no underscore path is enumerated here: import-tree
# underscore semantics, not this list, owns host-private files.)
for dir in services; do
  test -d "modules/$dir" || fail "excluded root modules/$dir must exist"
done
# Root evacuation (S5-6/S7-8): the four converted roots must be gone, not
# merely unlisted, and no underscore-renamed replacement root may exist. A fake
# shrink that drops an entry while the directory survives fails here.
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
test -f modules/hosts/oci-melb-1/_disko-single-disk-split.nix || fail "modules/hosts/oci-melb-1/_disko-single-disk-split.nix missing"
test -f modules/hosts/home-forge/_disko-two-disk.nix || fail "modules/hosts/home-forge/_disko-two-disk.nix missing"
# The successful flake evals below, with _bootstrap-config.nix absent and no
# underscore entry in the boundary list, are the proof that import-tree skipped
# the file by underscore semantics.

# --- 3. Typed registry materialized into nixosConfigurations (DS-2) ----------

# PostgreSQL provisioning ordering (D-058). nixpkgs creates databases and roles
# in `postgresql-setup.service`, which runs *after* `postgresql.service`; a
# consumer's credential or setup SQL therefore cannot live in `postStart` — on a
# fresh cluster the role does not exist yet and the unit fails (start-limit-hit,
# deploy rollback). Provisioning is its own unit, ordered after setup.
# Project only the fields under test: serialising a whole systemd unit forces
# every option, including ones with no default (startLimitBurst).
provision_probe='c: builtins.toJSON (
  (if c.systemd.services ? postgresql-provision then {
    hasUnit = true;
    requires = c.systemd.services.postgresql-provision.requires;
    after = c.systemd.services.postgresql-provision.after;
    partOf = c.systemd.services.postgresql-provision.partOf;
    user = c.systemd.services.postgresql-provision.serviceConfig.User;
  } else { hasUnit = false; })
  // { postStart = c.systemd.services.postgresql.postStart; }
)'
provision_forge="$(ne --raw --apply "$provision_probe" 'path:.#nixosConfigurations.home-forge.config')" ||
  fail "postgres provisioning probe does not evaluate on home-forge"
python3 - "$provision_forge" <<'PYEOF' || fail "postgres provisioning unit drifted (see message above)"
import json, sys
got = json.loads(sys.argv[1])
errs = []
if not got.get("hasUnit"):
    errs.append("home-forge registers a credentialled consumer, so postgresql-provision must exist")
else:
    if got.get("requires") != ["postgresql-setup.service"]:
        errs.append(f"provisioning must require postgresql-setup.service, got {got.get('requires')!r}")
    for dep in ("postgresql.service", "postgresql-setup.service"):
        if dep not in (got.get("after") or []):
            errs.append(f"provisioning must run after {dep}")
    if "postgresql.target" not in (got.get("partOf") or []):
        errs.append("provisioning must be partOf postgresql.target so a target restart re-applies credentials")
    if got.get("user") != "postgres":
        errs.append("provisioning must run as the postgres superuser")
if got["postStart"]:
    errs.append("provisioning must not live in postgresql.postStart: it runs before postgresql-setup.service creates roles and databases")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# A host whose consumers all authenticate over the Unix socket has nothing to
# apply, so it must not grow an idle provisioning unit.
provision_oci="$(ne --raw --apply 'c: builtins.toJSON (c.systemd.services ? postgresql-provision)' 'path:.#nixosConfigurations.oci-melb-1.config')" ||
  fail "postgres provisioning probe does not evaluate on oci-melb-1"
[ "$provision_oci" = "false" ] ||
  fail "oci-melb-1 registers only peer consumers, so no provisioning unit is needed"
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

# The host registry must materialize through inputs.nixpkgs.lib.nixosSystem
# (the public flake integration wrapper), never a direct eval-config.nix import
# or a hand-rolled source shim.
grep -q 'inputs.nixpkgs.lib.nixosSystem' modules/flake/host-registry.nix ||
  fail "host registry must materialize via inputs.nixpkgs.lib.nixosSystem (DS-2)"
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

# Stage 8 task 3.1 (HIC-3): every deploy host reference resolves to a declared
# canonical host ID, and an unknown reference fails closed at flake evaluation.
deploy_canonical="$(ne --raw --apply 'c: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames c))' 'path:.#nixosConfigurations')" ||
  fail "canonical host IDs must evaluate"
deploy_refs="$(ne --raw --apply 'd: builtins.toJSON {
  nodes = builtins.attrNames d.nodes;
  edgeHost = d.edgeHost;
  deployOrder = d.deployOrder;
}' 'path:.#deployHosts')" || fail "deploy metadata must evaluate"
python3 - "$deploy_canonical" "$deploy_refs" <<'PYEOF' || fail "deploy metadata must reference only declared canonical host IDs"
import json, sys
canonical = set(json.loads(sys.argv[1]))
got = json.loads(sys.argv[2])
references = set(got["nodes"]) | {got["edgeHost"]} | set(got["deployOrder"])
unknown = sorted(references - canonical)
if unknown:
    raise SystemExit(f"unknown deploy host references resolved: {unknown!r}")
PYEOF

# Negative: unknown references at all three sites must fail with the named
# error (node key, edgeHost, and deployOrder), never silently pass.
D="$(make_copy)"
python3 - "$D/lib/deploy/hosts.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
node_anchor = "    oci-melb-1 = {\n"
assert s.count(node_anchor) == 1, "node anchor drifted"
s = s.replace(node_anchor, "    ghost-node = {\n      hostName = \"ghost-node\";\n      sshUser = \"dev\";\n      system = \"x86_64-linux\";\n      remoteBuild = false;\n      strictSubstituteOnly = false;\n    };\n\n" + node_anchor, 1)
edge_anchor = '  edgeHost = "la-admin-1";'
assert s.count(edge_anchor) == 1, "edgeHost anchor drifted"
s = s.replace(edge_anchor, '  edgeHost = "ghost-edge";', 1)
order_anchor = '    "oci-melb-1"\n  ];'
assert s.count(order_anchor) == 1, "deployOrder anchor drifted"
s = s.replace(order_anchor, '    "oci-melb-1"\n    "ghost-order"\n  ];', 1)
open(p, "w").write(s)
PYEOF
for probe in deployHosts.edgeHost deploy.nodes; do
  set +e
  deploy_bad="$(nix eval --no-write-lock-file --raw "path:${D}#${probe}" 2>&1)"
  deploy_rc=$?
  set -e
  [ "$deploy_rc" -ne 0 ] || fail "3.1: unknown deploy host reference must fail closed (probe ${probe})"
  for want in ghost-node ghost-edge ghost-order; do
    case "$deploy_bad" in
      *"deploy: unknown host reference '$want' is not a declared canonical host ID"*) ;;
      *) fail "3.1: expected named unknown-reference error for '$want' (probe ${probe}), got: $(printf '%s' "$deploy_bad" | tail -3)" ;;
    esac
  done
done

# Negative: a node whose declared `system` disagrees with the canonical host
# record must fail closed with the named drift error. HIC-3 keeps the deploy
# metadata as the physical-facts authority (the value is detected, never
# derived), and deploy-rs picks its activation package from this field, so a
# silent disagreement would activate the wrong architecture.
D="$(make_copy)"
python3 - "$D/lib/deploy/hosts.nix" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
anchor = '      system = "aarch64-linux";'
assert s.count(anchor) == 1, "node system anchor drifted"
s = s.replace(anchor, '      system = "x86_64-linux";', 1)
open(p, "w").write(s)
PYEOF
set +e
system_bad="$(nix eval --no-write-lock-file --raw "path:${D}#deploy.nodes" 2>&1)"
system_rc=$?
set -e
[ "$system_rc" -ne 0 ] || fail "3.1: a deploy node system disagreeing with the canonical record must fail closed"
case "$system_bad" in
  *"deploy: node 'oci-melb-1' declares system 'x86_64-linux' but canonical host record declares 'aarch64-linux'"*) ;;
  *) fail "3.1: expected the named system-drift error, got: $(printf '%s' "$system_bad" | tail -3)" ;;
esac

# Stage 8 task 3.2 (HIC-3): host-backed web routing references canonical host
# identities, enforced in modules/flake/web-policy.nix against the declared
# nixos.hosts records, with policy/globals.nix as the single tailnet-suffix
# authority. Two independent copies isolate the two guards: the hosts-table key
# guard (outer) and the host-backed origin-FQDN guard (inner, reachable only
# while every hosts key is already canonical).
web_suffix="$(nix eval --impure --raw --no-write-lock-file --expr '(import ./policy/globals.nix).tailnet.suffix')" ||
  fail "3.2: the single tailnet suffix authority must evaluate"
[ -n "$web_suffix" ] || fail "3.2: the tailnet suffix authority must be non-empty"

D="$(make_copy)"
python3 - "$D/policy/web-services.nix" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
anchor = "  hosts = {\n    la-admin-1 = {"
assert s.count(anchor) == 1, "hosts-table anchor drifted"
s = s.replace(
    anchor,
    "  hosts = {\n"
    "    ghost-host = {\n"
    "      defaults = { };\n"
    "      services = { };\n"
    "    };\n"
    "    la-admin-1 = {",
    1,
)
open(p, "w").write(s)
PYEOF
set +e
web_bad_key="$(ne --raw "path:${D}#nixosConfigurations.la-admin-1.config.repo.web.hosts.la-admin-1.primaryDomain" 2>&1)"
web_bad_key_rc=$?
set -e
[ "$web_bad_key_rc" -ne 0 ] || fail "3.2: an unknown web-policy hosts key must fail closed"
case "$web_bad_key" in
  *"web-policy: unknown host reference 'ghost-host' is not a declared canonical host ID"*) ;;
  *) fail "3.2: expected the named unknown-host-key error, got: $(printf '%s' "$web_bad_key" | tail -n 3)" ;;
esac

D="$(make_copy)"
python3 - "$D/policy/web-services.nix" "$web_suffix" <<'PYEOF'
import sys

p, suffix = sys.argv[1], sys.argv[2]
s = open(p).read()
anchor = "            host = homeForge;\n            port = 4533;"
assert s.count(anchor) == 1, "navidrome origin anchor drifted"
s = s.replace(anchor, f'            host = "ghost-origin.{suffix}";\n            port = 4533;', 1)
open(p, "w").write(s)
PYEOF
set +e
web_bad_origin="$(ne --raw "path:${D}#nixosConfigurations.la-admin-1.config.repo.web.hosts.la-admin-1.primaryDomain" 2>&1)"
web_bad_origin_rc=$?
set -e
[ "$web_bad_origin_rc" -ne 0 ] || fail "3.2: a host-backed origin FQDN with no canonical identity must fail closed"
case "$web_bad_origin" in
  *"web-policy: origin FQDN 'ghost-origin.${web_suffix}' does not match any declared canonical host identity"*) ;;
  *) fail "3.2: expected the named origin-FQDN error, got: $(printf '%s' "$web_bad_origin" | tail -n 3)" ;;
esac

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
# Host record contributors (modules/hosts/<host>/default.nix) are flake-parts
# modules under Stage 8 HIC-1/HIC-2 and legitimately consume
# inputs.<x>.nixosModules for their record's composition.extraModules, exactly
# like modules/flake; host fragments (`_*.nix`) and service leaves stay
# prohibited.
# Only discovered first-party contributors may consume inputs/self: modules/flake/*
# (materialization and data projections), a host record
# (modules/hosts/<host>/default.nix), or a top-level domain contributor
# (modules/<domain>/<file>.nix, stage 8 task 5.1). Service leaves,
# underscore-private fragments, and nested files stay prohibited.
allow_contributor_arg() {
  awk -F: '
    {
      p = $1
      n = split(p, parts, "/")
      allow = 0
      if (p ~ /^modules\/flake\//) allow = 1
      else if (p ~ /^modules\/hosts\/[^\/]+\/default\.nix$/) allow = 1
      else if (n == 3 && parts[1] == "modules" && parts[2] != "services" && substr(parts[3], 1, 1) != "_") allow = 1
      if (!allow) {
        print
        found = 1
      }
    }
    END { exit(found ? 0 : 1) }'
}
if grep -RnE --include='*.nix' '^[[:space:]]*(inputs|self|ociImages),[[:space:]]*$' modules lib policy |
  allow_contributor_arg; then
  fail "lower-level module takes a prohibited self/inputs/ociImages argument"
fi
if grep -RnE --include='*.nix' '\{[^}]*\b(inputs|self|ociImages)\b[^}]*\}' modules lib policy |
  allow_contributor_arg; then
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
# modules/ minus the enumerated unconverted roots and minus underscore private
# paths (import-tree underscore semantics, matching flake.nix filterNot).
# Host contributors are discovered like any other module since stage 8 task 2.3
# removed `hosts` from the boundary, so they are NOT excluded here.
discovered_contributors() { # $1 repo root
  find "$1/modules" -type f -name '*.nix' \
    ! -path '*/_*' \
    ! -path '*/services/*' \
    -print
}
publication_files() { # $1 repo root -> discovered files that define a publication
  local f
  while IFS= read -r f; do
    if grep -qE '^[[:space:]]*flake\.modules\.nixos\.[a-z0-9-]+[[:space:]]*=' "$f"; then
      printf '%s\n' "$f"
    fi
  done < <(discovered_contributors "$1")
}
pub_names_of() { # $1 repo root -> sorted flake.modules.nixos.<name> definitions
  discovered_contributors "$1" \
    | xargs -r grep -hoE '^[[:space:]]*flake\.modules\.nixos\.[a-z0-9-]+[[:space:]]*=' \
    | sed -E 's/^[[:space:]]*//; s/[[:space:]]*=$//' | LC_ALL=C sort -u
}
registry_selections() { # $1 repo root -> "host aspect" pairs, in source order
  # Stage 8 HIC-1/HIC-2: hosts declare their selections in
  # modules/hosts/<host>/default.nix. modules/flake/registry.nix is still
  # parsed: it currently holds no selection table, so that half is inert, but
  # keeping it means a reintroduced table is at least parsed rather than
  # silently ignored (the exact-set 7b assertions are the non-vacuous guards.
  # Duplicate-selection protection lives in the identity test: LA across all
  # selections (§5.2) and oci/home-forge placement pins in that test's §13).
  awk '
    FNR == 1 { host = "" }
    match($0, /^  nixos\.hosts\.[a-z0-9-]+ = \{$/) {
      host = $0
      sub(/^  nixos\.hosts\./, "", host)
      sub(/ = \{$/, "", host)
      next
    }
    /^      [a-z0-9-]+ = \{/ { host = $1; next }
    host != "" {
      s = $0
      while (match(s, /aspects\.[a-z0-9-]+/)) {
        print host, substr(s, RSTART, RLENGTH)
        s = substr(s, RSTART + RLENGTH)
      }
    }
  ' "$1/modules/flake/registry.nix" "$1"/modules/hosts/*/default.nix
}
host_aspects() { # $1 repo root, $2 host -> sorted selected aspect names
  registry_selections "$1" | awk -v h="$2" '$1 == h { print $2 }' | LC_ALL=C sort -u
}
host_leaf_imports_of() { # $1 dir
  grep -RnE --include='*.nix' 'modules/((cache/state-backups|flake/observability-agent)|(cache/_backups/(niks3-upload-client|niks3-post-deploy)|flake/_builder-access/nixbuild-ssh))\.nix' "$1/modules/hosts" || true
}

# 7a. Exactly thirty-five publications are discovered across the distributed
# contributors: the infrastructure support quartet, the twelve Stage 2-6
# deployment aspects (base, shell, networking, tailscale, notify,
# state-backups, cache-publisher, builder-access, observability-agent, dj,
# music, identity-client), and the eighteen Stage 7 placement aspects (S7-2), plus the Stage 8 internal transport contracts publication (task 4.1).
# split-state-backups-cache-publication replaced the combined backups aspect
# with independent state-backups and cache-publisher aspects.
# decouple-identity-admin-capabilities
# task 3.3 extracted the six admin capabilities (termix, vaultwarden, gatus,
# beszel, homepage, webhook) into their own published aspects; admin-hub stays
# deleted. Registry references are not definition sites. No central publication
# file is pinned.
expected_pub="$(printf '%s\n' \
flake.modules.nixos.ai-gateway \
flake.modules.nixos.base \
flake.modules.nixos.beszel \
flake.modules.nixos.builder-access \
flake.modules.nixos.cache-publisher \
flake.modules.nixos.cockpit \
flake.modules.nixos.dj \
flake.modules.nixos.edge \
flake.modules.nixos.fleet-packages \
flake.modules.nixos.gatus \
flake.modules.nixos.homepage \
flake.modules.nixos.identity-client \
flake.modules.nixos.identity-provider \
flake.modules.nixos.internal-contracts \
flake.modules.nixos.karakeep \
flake.modules.nixos.music \
flake.modules.nixos.networking \
flake.modules.nixos.niks3-cache \
flake.modules.nixos.notify \
flake.modules.nixos.observability-agent \
flake.modules.nixos.oci \
flake.modules.nixos.oci-images \
flake.modules.nixos.omniroute \
flake.modules.nixos.paperless \
flake.modules.nixos.phoenix \
flake.modules.nixos.postgres \
flake.modules.nixos.provenance \
flake.modules.nixos.push-server \
flake.modules.nixos.shell \
flake.modules.nixos.state-backups \
flake.modules.nixos.tailscale \
flake.modules.nixos.termix \
flake.modules.nixos.vaultwarden \
flake.modules.nixos.web-policy \
flake.modules.nixos.webhook)"
pub_names="$(pub_names_of "$ROOT")"
if [ "$pub_names" != "$expected_pub" ]; then
  fail "discovered publications drifted from the support quartet + twelve deployment aspects + eighteen placement aspects + internal-contracts: $pub_names"
fi
if grep -RnE --include='*.nix' 'flake\.modules\.nixos\.cli|_aspects/cli|aspects\.cli' modules; then
fail "the deleted cli aspect must not be resurrected"
fi
# Underscore-private implementation leaves are not auto-discovered (import-tree
# underscore semantics, proven by the successful flake evals below) and must
# not smuggle a publication past discovery. Owner assertions stay where they
# are semantically meaningful: typed base facts (7c) and the shell leaf + p10k
# data (7g). No exact private-filename inventory is pinned.
for priv in modules/flake/_aspects modules/flake/_builder-access modules/edge/_edge modules/oci/_oci modules/cache/_backups modules/music/_dj; do
  test -d "$priv" || fail "private implementation dir $priv missing"
  if grep -RnE --include='*.nix' 'flake\.modules\.nixos\.[a-z0-9-]+[[:space:]]*=' "$priv"; then
    fail "underscore-private paths must not publish flake.modules.nixos aspects ($priv)"
  fi
done

# 7b. Per-host registry selections are semantically exact: every host selects
# the support quartet and the eight foundation/operational aspects; OCI and LA
# additionally select identity-client and their own Stage 7 placement set,
# while home-forge selects dj, music, and omniroute instead. Aspect order is
# not part of the contract, and host assemblies receive aspects only via the
# registry.
support_quartet="aspects.provenance
aspects.oci-images
aspects.fleet-packages
aspects.web-policy"
foundation_operational="aspects.base
aspects.shell
aspects.networking
aspects.tailscale
aspects.notify
aspects.state-backups
aspects.cache-publisher
aspects.internal-contracts
aspects.builder-access
aspects.observability-agent"
oci_placement="aspects.oci
aspects.edge
aspects.cockpit
aspects.paperless
aspects.postgres
aspects.ai-gateway
aspects.karakeep
aspects.niks3-cache
aspects.phoenix"
# The six admin capabilities extracted by decouple-identity-admin-capabilities
# task 3.3 are placed by their own aspects on la-admin-1 (exactly once, and
# admin-hub stays deleted).
la_placement="aspects.edge
aspects.cockpit
aspects.push-server
aspects.identity-provider
aspects.termix
aspects.vaultwarden
aspects.gatus
aspects.beszel
aspects.homepage
aspects.webhook"
oci_sel="$(printf '%s\n%s\n%s\naspects.identity-client\n' "$support_quartet" "$foundation_operational" "$oci_placement" | LC_ALL=C sort)"
la_sel="$(printf '%s\n%s\n%s\naspects.identity-client\n' "$support_quartet" "$foundation_operational" "$la_placement" | LC_ALL=C sort)"
forge_placement="aspects.postgres"
forge_sel="$(printf '%s\n%s\n%s\naspects.dj\naspects.music\naspects.omniroute\n' "$support_quartet" "$foundation_operational" "$forge_placement" | LC_ALL=C sort)"
[ "$(host_aspects "$ROOT" oci-melb-1)" = "$oci_sel" ] ||
  fail "registry: oci-melb-1 must select the support quartet + eight deployment aspects + identity-client + its nine placement aspects: $(host_aspects "$ROOT" oci-melb-1)"
[ "$(host_aspects "$ROOT" la-admin-1)" = "$la_sel" ] ||
  fail "registry: la-admin-1 must select the support quartet + eight deployment aspects + identity-client + its ten placement aspects: $(host_aspects "$ROOT" la-admin-1)"
[ "$(host_aspects "$ROOT" home-forge)" = "$forge_sel" ] ||
  fail "registry: home-forge must select the support quartet + eight deployment aspects + dj + music + omniroute + its postgres placement: $(host_aspects "$ROOT" home-forge)"
# Host records (modules/hosts/<host>/default.nix) are the aspect-selection
# authority since Stage 8 HIC-1/HIC-2; the private NixOS fragments (`_*.nix`)
# must still never import an aspect implementation.
if grep -RnE --include='_*.nix' 'aspects\.|_aspects' modules/hosts; then
fail "host fragments must receive aspects only via their host record"
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
  # Only code references count: contributor header prose legitimately names the
  # aspect it publishes (e.g. `aspects.termix` in its own comment), which is
  # not an import expression. Comment-only refs are skipped, so mutation 7k-3
  # still proves a real `imports = [ aspects.x ]` is caught.
  awk '
    /^[[:space:]]*#/ { if ($0 ~ /intrinsic/) just[NR] = 1; next }
    /aspects\.[a-z0-9-]+/ { ref[NR] = 1 }
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
grep -q 'key = "tailscale/auth_key"' modules/flake/tailscale.nix || fail "tailscale leaf must register key tailscale/auth_key"
grep -q 'path = "/run/secrets/tailscale.auth_key"' modules/flake/tailscale.nix || fail "tailscale leaf must render /run/secrets/tailscale.auth_key"
grep -q 'mode = "0400"' modules/flake/tailscale.nix || fail "tailscale auth-key secret must be mode 0400"
grep -q 'authKeyFile = lib.mkIf hasHostSecrets "/run/secrets/tailscale.auth_key"' modules/flake/tailscale.nix || fail "tailscale leaf must own authKeyFile"
grep -q 'TS_DEBUG_MTU = toString cfg.debugMtu' modules/flake/tailscale.nix || fail "tailscale leaf must render TS_DEBUG_MTU from debugMtu"
if grep -RnE 'tailscale_auth_key|authKeyFile|TS_DEBUG_MTU|tailscale\.auth_key' modules/hosts; then
fail "hosts must not repeat tailscale secret/MTU registration"
fi

# 7f. Notify composition (FND-5, apprise-notification-module spec): the notify
# aspect composes the notification-daemon leaf, enables it, and resolves the
# repo packages via withSystem; hosts keep only host-specific inputs.
grep -q 'options\.services\.notification-daemon' modules/notifications/notify.nix || fail "notify aspect must own the notification-daemon implementation body"
grep -q 'enable = true;' modules/notifications/notify.nix || fail "notify aspect must enable the daemon"
grep -q 'package = packages.notification-daemon;' modules/notifications/notify.nix || fail "notify aspect must pass the repo notification-daemon package"
grep -q 'notifyPackage = packages.notify;' modules/notifications/notify.nix || fail "notify aspect must pass the repo notify package"
if grep -RnE 'notification-daemon\.enable|notification-daemon\]' modules/hosts; then
fail "hosts must not re-enable or import the notification-daemon leaf"
fi

# 7g. Stage 3 composition ownership (OPS-1..OPS-9): the five deferred leaves
# exist (relocated beside their aspect owners under underscore-private paths,
# S5-3) and are imported by exactly their owning aspect; host assemblies never
# import, enable, or conventionally bind them; the upstream niks3-auto-upload
# module is imported only by the cache-publisher aspect (never by the registry); the
# retired fleet.nixbuild-ssh option is gone; and the post-deploy leaf takes
# its filter package from the typed option injected by the aspect (no hidden
# fleet-packages dependency). The services import-tree exclusion is unchanged
# (OPS-9, check 1).
for leaf in \
  modules/cache/state-backups.nix \
  modules/cache/_backups/niks3-upload-client.nix \
  modules/cache/_backups/niks3-post-deploy.nix \
  modules/flake/_builder-access/nixbuild-ssh.nix \
  modules/flake/observability-agent.nix; do
  test -f "$leaf" || fail "operational leaf $leaf missing"
done
grep -q 'options.services.state-backups' modules/cache/state-backups.nix || fail "state-backups aspect must own the state-backups implementation body"
# Word-boundary on `_backups` keeps the check meaningful now that the
# implementation body lives in this file: `state_backups_*` secret identifiers
# are not the `_backups` publication leaves.
if grep -qE '_backups\b|niks3' modules/cache/state-backups.nix; then
  fail "state-backups aspect must own no Niks3 upload/publication surface"
fi
grep -q './_backups/niks3-upload-client.nix' modules/cache/cache-publisher.nix || fail "cache-publisher aspect must import the niks3-upload-client leaf"
grep -q './_backups/niks3-post-deploy.nix' modules/cache/cache-publisher.nix || fail "cache-publisher aspect must import the niks3-post-deploy leaf"
grep -q './_builder-access/nixbuild-ssh.nix' modules/flake/builder-access.nix || fail "builder-access aspect must import the nixbuild-ssh leaf"
grep -q 'options\.services\.beszel-agent-auth' modules/flake/observability-agent.nix || fail "observability-agent aspect must own the beszel-agent-auth implementation body"
grep -q 'inputs.niks3.nixosModules.niks3-auto-upload' modules/cache/cache-publisher.nix || fail "cache-publisher aspect must import the upstream niks3-auto-upload module"
# Narrowed to the exact upstream module import (S5-7): the relocated
# post-deploy leaf mentions the `services.niks3-auto-upload` option, which must
# not false-positive as a second import site.
if grep -RnE 'inputs\.niks3\.nixosModules\.niks3-auto-upload' modules/flake | grep -v '^modules/cache/cache-publisher.nix:'; then
  fail "niks3-auto-upload must be imported only by the cache-publisher aspect (not the registry)"
fi
grep -qE 'inputs\.niks3\.nixosModules\.niks3[[:space:]]*$' modules/hosts/oci-melb-1/default.nix modules/hosts/la-admin-1/default.nix modules/hosts/home-forge/default.nix modules/flake/registry.nix || fail "OCI must keep the niks3 server module import"
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
grep -q 'filterPackage' modules/cache/_backups/niks3-post-deploy.nix || fail "post-deploy leaf must define the typed filterPackage option"
grep -q 'type = lib.types.package' modules/cache/_backups/niks3-post-deploy.nix || fail "filterPackage must be a typed package option"
grep -q 'filterPackage = packages.nix-path-filter' modules/cache/cache-publisher.nix || fail "cache-publisher aspect must inject nix-path-filter into post-deploy"
if grep -nE '^[^#]*config\.repo\.packages' modules/cache/_backups/niks3-post-deploy.nix; then
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
for idf in modules/identity/identity-oidc.nix modules/identity/kanidm-host-auth.nix; do
  test -f "$idf" || fail "identity contributor $idf missing"
  grep -q 'flake.modules.nixos.identity-client' "$idf" || fail "$idf must publish identity-client"
done
test ! -e modules/flake/_identity-client || fail "no _identity-client private leaf directory may exist (S5-5)"
if grep -RnE --include='*.nix' 'identity-oidc|kanidm-host-auth' modules/hosts modules/flake/*.nix modules/identity/*.nix | grep -vE '^modules/identity/(identity-oidc|kanidm-host-auth)\.nix'; then
  fail "no host or concern file may import an identity contributor directly (S5-5)"
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

# 7i-1. Backups without monitor enablement fails with the named monitor
# assertion (OPS-4). The notify leaf stays selected because every monitoring
# contributor (base, observability-agent, music, omniroute, and the OCI host
# assembly) now defines services.notification-daemon.monitor.units, so the
# monitor contract namespace is a hard prerequisite of those contributions;
# the mutation removes exactly the enablement the notify aspect owns. The host
# assembly no longer duplicates monitor.enable (MON-1/MON-3: one authority).
D="$(make_copy)"
sed -i '/monitor\.enable = true;/d' "$D/modules/notifications/notify.nix"
expect_eval_fail "$D" oci-melb-1 "services.notification-daemon.monitor.enable must be true"

# 7i-2. A derived bucket outside the S3 rule fails with the named assertion
# (OPS-11). nixpkgs itself rejects a trailing-hyphen hostName at the type
# level, so the tamper forces the trailing hyphen into the derived bucket. The
# bucket expression lives in the state-backups contributor.
D="$(make_copy)"
python3 - "$D/modules/cache/state-backups.nix" <<'PY'
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

# 7i-4. Backup-split subset isolation (split-state-backups-cache-publication
# 3.3a): selecting one of the split aspects alone must introduce only its own
# units. Each leg takes a FRESH make_copy (7i-3's copy legitimately tests the
# absent-secret gate and must not be reused). The composition imports the
# copy's contributor module plus the notify/monitor provider module over a
# minimal nixosSystem, so an unimported leaf's options are hard absences, and
# the state-backups contributor's monitor-enable assertion is satisfied by the
# imported notify leaf. The home-forge fixture hostname keeps the conventional
# host secret present so the gated enables are true.
subset_probe() { # $1 copy root, $2 aspect name -> eval report JSON
  local d="$1" aspect="$2" t out rc
  t="$(mktemp -d /tmp/scaffold-subset.XXXXXX)"
  cat >"$t/flake.nix" <<EOF2
{
  inputs.repo.url = "path:$d";
  outputs = { self, repo }: {
    report = let
      sys = repo.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          repo.inputs.sops-nix.nixosModules.sops
          repo.modules.nixos.notify
          repo.modules.nixos.$aspect
          { networking.hostName = "home-forge"; system.stateVersion = "25.11"; }
        ];
      };
      c = sys.config;
    in {
      resticBackupsEmpty = (c.services.restic.backups or { }) == { };
      resticUnitAbsent = !((c.systemd.services or { }) ? "restic-backups-state");
      clientEnable = c.services.niks3-auto-upload.enable or false;
      clientOptionAbsent = !((c.services.niks3-auto-upload or { }) ? enable);
      postEnable = c.services.niks3-post-deploy.enable or false;
      postOptionAbsent = !((c.services.niks3-post-deploy or { }) ? enable);
      postActivationPresent = (c.system.activationScripts.niks3-post-deploy or null) != null;
      postActivationAbsent = (c.system.activationScripts.niks3-post-deploy or null) == null;
      uploadUnitPresent = (c.systemd.services or { }) ? "niks3-auto-upload";
      postUnitPresent = (c.systemd.services or { }) ? "niks3-post-deploy";
    };
  };
}
EOF2
  out="$(nix eval --raw --impure --no-write-lock-file --expr "builtins.toJSON ((builtins.getFlake (toString $t)).report)")"
  rm -rf "$t"
  printf '%s' "$out"
}

D="$(make_copy)"
json="$(subset_probe "$D" cache-publisher)" ||
  fail "cache-publisher-only subset: composition must evaluate"
python3 - "$json" <<'PY' || fail "cache-publisher-only subset: observables violated: $json"
import json, sys
got = json.loads(sys.argv[1])
want = {"resticBackupsEmpty": True, "resticUnitAbsent": True,
        "clientEnable": True, "postEnable": True, "uploadUnitPresent": True,
        "postUnitPresent": True, "postActivationPresent": True,
        "postActivationAbsent": False,
        "postOptionAbsent": False, "clientOptionAbsent": False}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in want.items() if got.get(k) != v]
if errs:
    raise SystemExit("; ".join(errs))
PY

D="$(make_copy)"
json="$(subset_probe "$D" state-backups)" ||
  fail "state-backups-only subset: composition must evaluate"
python3 - "$json" <<'PY' || fail "state-backups-only subset: observables violated: $json"
import json, sys
got = json.loads(sys.argv[1])
want = {"resticBackupsEmpty": False, "resticUnitAbsent": False,
        "clientOptionAbsent": True, "postOptionAbsent": True}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in want.items() if got.get(k) != v]
if errs:
    raise SystemExit("; ".join(errs))
PY

# 7j. Tamper-proof source checks: the 7a/7b/7g pipelines must detect a
# regression (aspect unpublished, selection dropped, leaf re-imported by a
# host) on a throwaway copy. The publication tamper targets one distributed
# contributor (state-backups.nix). The re-import anchors on a host import line
# that survives the backup split and inserts a relocated private leaf path so
# host_leaf_imports_of is exercised.
D="$(make_copy)"
sed -i 's/flake.modules.nixos.state-backups =/flake.modules.nixos.state-backups-tampered =/' "$D/modules/cache/state-backups.nix"
# Stage 8 HIC-1/HIC-2: selections live in the host records, so the tamper
# drops the required selection from every converted contributor.
for h in oci-melb-1 la-admin-1 home-forge; do
  sed -i '/aspects.state-backups/d' "$D/modules/hosts/$h/default.nix"
done
sed -i '/\.\/_cockpit-auth\.nix/a\  ../../../modules/cache/_backups/niks3-post-deploy.nix' "$D/modules/hosts/oci-melb-1/_nixos.nix"
[ "$(pub_names_of "$D")" != "$expected_pub" ] ||
fail "7a publication check must detect an unpublished state-backups aspect"
[ "$(host_aspects "$D" oci-melb-1)" != "$oci_sel" ] ||
fail "7b selection check must detect a dropped aspect"
[ -n "$(host_leaf_imports_of "$D")" ] ||
fail "7g host-import check must detect a re-imported leaf"

# 7k. DJ selection semantics (S4-4, S4-8; tasks 4.1/4.2). DJ enablement comes
# from selecting the dj deployment aspect, not from discovery. The observable
# is the evaluated applications.dj.enable value; the throwaway mutations below
# prove discovery-only placement does not activate and selection owns
# enablement.
dj_enabled() { # $1 repo root, $2 host -> "true"/"false" through aspect selection
  local d="$1" host="$2" out err rc
  err="$(mktemp)"
  set +e
  out="$(nix eval --no-write-lock-file --raw --apply \
    'c: if ((c.applications.dj or { }).enable or false) then "true" else "false"' \
    "path:${d}#nixosConfigurations.${host}.config" 2>"$err")"
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    # stderr stays out of the probe value: store diagnostics are not the answer.
    tail -2 "$err" || true
    rm -f "$err"
    fail "dj probe ${host}: config does not evaluate"
  fi
  rm -f "$err"
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
sed -i '/applications\.dj\.enable = true;/d' "$D/modules/music/dj.nix"
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
# boundary entry (services) leaves the exact single-root set wrong even though the
# directory survives unconverted. This proves the current single-root equality is
# load-bearing and order-independent, independent of the root-evacuation guard.
D="$(make_copy)"
sed -i '/^  "services"$/d' "$D/modules/flake/_unconverted-nixos-dirs.nix"
test -d "$D/modules/services" || fail "7l-2: prepared copy must still contain modules/services"
[ "$(unconverted_roots "$D")" != '["services"]' ] ||
  fail "7l-2: fake filter shrink must break the exact single-root set"

# 7l-3. Private leaves must stay undiscoverable/non-publishing. A publication
# smuggled into an underscore-private path is caught by the 7a private-owner scan
# (same grep the working tree uses), and is invisible to discovery.
D="$(make_copy)"
printf '\n  flake.modules.nixos.evil-pub = { };\n' >>"$D/modules/cache/_backups/niks3-upload-client.nix"
grep -RnE --include='*.nix' 'flake\.modules\.nixos\.[a-z0-9-]+[[:space:]]*=' "$D/modules/cache/_backups" >/dev/null ||
  fail "7l-3: private-owner scan must reject a publication under _backups"
case "$(pub_names_of "$D")" in
  *evil-pub*) fail "7l-3: an underscore-private publication must not be discovered" ;;
esac

# 7l-4. Relocated private leaves and identity contributors must not be imported
# directly by a host. Fresh imports inserted on the surviving
# `./_cockpit-auth.nix` import line are detected by host_leaf_imports_of (for
# the relocated leaf) and by the 7g-2 identity-import grep (for the
# contributor) — both anchored on a line that survives this change, so the
# checks are exercised non-vacuously.
D="$(make_copy)"
sed -i '/\.\/_cockpit-auth\.nix/a\  ../../../modules/cache/_backups/niks3-post-deploy.nix' "$D/modules/hosts/oci-melb-1/_nixos.nix"
[ -n "$(host_leaf_imports_of "$D")" ] ||
  fail "7l-4: host_leaf_imports_of must detect a directly re-imported relocated leaf"
sed -i '/\.\/_cockpit-auth\.nix/a\  ../../../modules/identity/identity-oidc.nix' "$D/modules/hosts/oci-melb-1/_nixos.nix"
grep -RnE --include='*.nix' 'identity-oidc|kanidm-host-auth' "$D/modules/hosts" >/dev/null ||
  fail "7l-4: identity-import grep must detect a directly imported identity contributor"

# 7l-5. Identity must not activate on forge. Adding aspects.identity-client to
# the forge record is detected through the missing-services.identity observable,
# not a publication diff.
D="$(make_copy)"
sed -i '/aspects\.dj/i\        aspects.identity-client' "$D"/modules/hosts/*/default.nix
forge_identity_mut="$(ne --raw --apply 'c: builtins.toJSON (builtins.attrNames (c.services.identity or {}))' \
  "path:${D}#nixosConfigurations.home-forge.config")" ||
  fail "7l-5: forge identity mutation probe must evaluate"
[ "$forge_identity_mut" != '[]' ] ||
  fail "7l-5: forge must expose identity activation when identity-client is wrongly selected"

# 7l-6. Deleting the OIDC contributor removes OIDC behavior/eval while the
# sibling kanidm contributor still publishes identity-client. Detection is the
# missing services.identity.oidc option (eval failure), never a publication.
D="$(make_copy)"
rm "$D/modules/identity/identity-oidc.nix"
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
rm "$D/modules/identity/kanidm-host-auth.nix"
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

# --- 7m. Stage 6 music composition (S6-2..S6-11) -----------------------------
# (openspec change dendritic-stage-6-music-composition tasks 5.1/5.2)
#
# The `music` deployment aspect is published from the discovered contributor
# modules/music/music.nix and selected only on home-forge; selecting it is its
# top-level enablement. Its implementation files under modules/music/*.nix are
# discovered contributors that merge into that one aspect name (deferredModule),
# are never imported from outside the concern, and publish no second aspect.
# DJ consumes the read-only applications.music.contract through a named
# assertion. Ownership is asserted by contributor (host-import grep + foreign
# publication scan + outside-import check), never by a hardcoded operational
# predicate.

music_host_imports_of() { # $1 repo root
  grep -RnE --include='*.nix' 'modules/music' "$1/modules/hosts" || true
}
music_leaf_publishers_of() { # $1 repo root -> publications other than the music/dj aspects themselves
  # modules/music holds both concerns' contributors (music: the eight workload
  # implementations; dj: the dj aspect and its Windows VM runtime sibling), so
  # only those two aspect names are allowed to appear here.
  grep -RnE --include='*.nix' 'flake\.modules\.nixos\.[a-z0-9-]+[[:space:]]*=' "$1/modules/music" \
    | grep -vE 'flake\.modules\.nixos\.(music|dj)[[:space:]]*=' || true
}
music_leaf_import_sites_of() { # $1 repo root -> music implementations imported from outside the concern
  grep -REl --include='*.nix' \
    'music/(audiomuse|syncthing|navidrome|slskd|tagr|beets|ingest|storage|windows-vm)\.nix' \
    "$1/modules" | grep -vF "$1/modules/music/" || true
}
strip_host_block() { # $1 file, $2 "<option> = {" marker
  python3 - "$1" "$2" <<'PYEOF'
import sys
path, marker = sys.argv[1], sys.argv[2]
s = open(path).read()
start = s.index(marker)
i = s.index("{", start)
depth = 0
while True:
    if s[i] == "{":
        depth += 1
    elif s[i] == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
end = i + 1
if end < len(s) and s[end] == ";":
    end += 1
open(path, "w").write(s[:start] + s[end:])
PYEOF
}

# 7m-1. Privacy by owner and the legacy-coordinator deletion precondition.
test -f modules/music/music.nix || fail "7m-1: discovered music contributor missing"
test ! -e modules/applications || fail "7m-1: the evacuated application root must be deleted"
grep -q 'flake.modules.nixos.music' modules/music/music.nix ||
  fail "7m-1: modules/music/music.nix must publish flake.modules.nixos.music"
for leaf in audiomuse syncthing navidrome slskd tagr beets ingest storage; do
  test -f "modules/music/${leaf}.nix" ||
    fail "7m-1: music implementation modules/music/${leaf}.nix missing"
  grep -q 'flake\.modules\.nixos\.music[[:space:]]*=' "modules/music/${leaf}.nix" ||
    fail "7m-1: modules/music/${leaf}.nix must contribute to the music aspect"
done
[ -z "$(music_host_imports_of "$ROOT")" ] ||
  fail "7m-1: host assemblies must not import modules/music implementations directly: $(music_host_imports_of "$ROOT")"
[ -z "$(music_leaf_publishers_of "$ROOT")" ] ||
  fail "7m-1: modules/music contributors must publish only the music and dj aspects: $(music_leaf_publishers_of "$ROOT")"
[ -z "$(music_leaf_import_sites_of "$ROOT")" ] ||
  fail "7m-1: music implementations must not be imported from outside modules/music: $(music_leaf_import_sites_of "$ROOT")"

# 7m-2. Focused observable probe. Every field is forced through the full
# toplevel derivation (`drv`) so option-merge and assertion failures surface.
# home-forge proves selection-owned enablement, the contract, leaf activation,
# and DJ values; OCI/LA prove discovery without selection activates nothing.
MUSIC_PROBE='c:
let
  # S6-3 declares the contract as a typed submodule with no nullable/default
  # sentinel and assigns it only inside the enable-gated body: on a
  # selected-but-disabled host the declared option has no value, so a field
  # read fails ("accessed but has no value defined") instead of yielding null.
  # Probe each field under tryEval so "absent" covers both the unselected host
  # (option namespace missing) and the selected-but-disabled host (no value).
  contractField = field:
    builtins.tryEval (
      if (c.applications.music or { }) ? contract
      then (c.applications.music.contract.${field} or null)
      else null
    );
  contractText = field:
    let r = contractField field; in
    if r.success && r.value != null then r.value else "";
in {
  drv = c.system.build.toplevel.drvPath;
  musicOptionCount = builtins.length (builtins.attrNames (c.applications.music or { }));
  enable = (c.applications.music or { }).enable or false;
  contractPresent = (contractField "storageRoot").success && (contractField "storageRoot").value != null;
  contractStorageRoot = contractText "storageRoot";
  contractLibraryDir = contractText "libraryDir";
  contractPlaylistsDir = contractText "playlistsDir";
  storageRoot = (c.applications.music or { }).storageRoot or "";
  ingest = c.services.musicIngest.enable or false;
  storage = c.services.musicStorage.enable or false;
  ffmpegUnit = c.systemd.services ? ffmpeg-preprocess;
  reconcileUnit = c.systemd.services ? media-permission-reconcile;
  dropboxPath = c.systemd.paths ? dropbox-inbox;
  dropboxTimer = c.systemd.timers ? dropbox-settle;
  slskdTimer = c.systemd.timers ? slskd-settle;
  gidMusicIngest = (c.users.groups.music-ingest or { }).gid or null;
  gidMedia = (c.users.groups.media or { }).gid or null;
  onSuccess = c.services.beets.onSuccessUnits or [ ];
  importReadyFlag = c.services.beets.importReadyFlag or "";
  renderedStandard = if (c.applications.music or { }).enable or false then (c.services.beets.renderedConfigFiles.standard or "") else "";
  renderedQuarantine = if (c.applications.music or { }).enable or false then (c.services.beets.renderedConfigFiles.quarantine or "") else "";
  djEnable = (c.applications.dj or { }).enable or false;
  djShare = ((c.applications.dj or { }).engine or { }).sharePath or "";
  djRoot = ((c.applications.dj or { }).engine or { }).musicStorageRoot or "";
  djTraktor = ((c.applications.dj or { }).engine or { }).traktorStateDir or "";
  musicPkgs = builtins.sort builtins.lessThan (builtins.filter (n: builtins.elem n [ "ffmpeg-preprocess" "beets-interactive" "beets-dupes" "beets-merge-splits" "beets-prune-empty" "media-fixperms" ]) (builtins.map (p: p.name or "") (c.environment.systemPackages or [ ])));
  tmpfilesHasStorageRoot = builtins.elem "d /srv/storage/media/music 0755 root root - -" (c.systemd.tmpfiles.rules or [ ]);
  tmpfilesHasUntagged = builtins.elem "d /srv/storage/media/music/quarantine/untagged 2775 root music-ingest - -" (c.systemd.tmpfiles.rules or [ ]);
  tmpfilesHasSlskdEnv = builtins.elem "f /var/lib/slskd/environment 0640 slskd slskd - -" (c.systemd.tmpfiles.rules or [ ]);
}'

probe_music() { # $1 host, $2 expected JSON (python dict literal)
  local host="$1" json
  json="$(ne --json --apply "$MUSIC_PROBE" "path:.#nixosConfigurations.${host}.config")" ||
    fail "${host}: music probe does not evaluate"
  python3 - "$host" "$2" "$json" <<'PYEOF' || fail "${host}: observable music contract violated"
import json, sys
host, exp_raw, got_raw = sys.argv[1], sys.argv[2], sys.argv[3]
exp = json.loads(exp_raw)
got = json.loads(got_raw)
errs = []
music_clis = ["beets-dupes", "beets-interactive", "beets-merge-splits", "beets-prune-empty", "ffmpeg-preprocess", "media-fixperms"]
if host == "home-forge":
    if got["musicOptionCount"] <= 0:
        errs.append("music options must exist on the selected host")
    if got["musicPkgs"] != music_clis:
        errs.append(f"music package contributions drifted: {got['musicPkgs']!r}")
else:
    if got["musicOptionCount"] != 0:
        errs.append(f"discovered-but-unselected host exposes music options: {got['musicOptionCount']}")
    if got["musicPkgs"]:
        errs.append(f"discovered-but-unselected host exposes music packages: {got['musicPkgs']!r}")
for k, v in exp.items():
    if got.get(k) != v:
        errs.append(f"{k}: got {got.get(k)!r} want {v!r}")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

probe_music home-forge '{"enable":true,"contractPresent":true,"contractStorageRoot":"/srv/storage/media/music","contractLibraryDir":"/srv/storage/media/music/library","contractPlaylistsDir":"/srv/storage/media/music/playlists","storageRoot":"/srv/storage/media/music","ingest":true,"storage":true,"ffmpegUnit":true,"reconcileUnit":true,"dropboxPath":true,"dropboxTimer":true,"slskdTimer":true,"gidMusicIngest":990,"gidMedia":987,"onSuccess":["media-permission-reconcile.service","navidrome-scan.service"],"importReadyFlag":"/var/lib/beets/ffmpeg-preprocess/inbox-ready","renderedStandard":"/run/secrets/rendered/beets-config.yaml","renderedQuarantine":"/run/secrets/rendered/beets-quarantine-config.yaml","djEnable":true,"djShare":"/srv/storage/media/music","djRoot":"/srv/storage/media/music","djTraktor":"/srv/data/traktor-m3u-sync","tmpfilesHasStorageRoot":true,"tmpfilesHasUntagged":true,"tmpfilesHasSlskdEnv":true}'
probe_music oci-melb-1 '{"enable":false,"contractPresent":false,"contractStorageRoot":"","contractLibraryDir":"","contractPlaylistsDir":"","storageRoot":"","ingest":false,"storage":false,"ffmpegUnit":false,"reconcileUnit":false,"dropboxPath":false,"dropboxTimer":false,"slskdTimer":false,"gidMusicIngest":null,"gidMedia":null,"onSuccess":[],"importReadyFlag":"","renderedStandard":"","renderedQuarantine":"","djEnable":false,"djShare":"","djRoot":"","djTraktor":"","tmpfilesHasStorageRoot":false,"tmpfilesHasUntagged":false,"tmpfilesHasSlskdEnv":false}'
probe_music la-admin-1 '{"enable":false,"contractPresent":false,"contractStorageRoot":"","contractLibraryDir":"","contractPlaylistsDir":"","storageRoot":"","ingest":false,"storage":false,"ffmpegUnit":false,"reconcileUnit":false,"dropboxPath":false,"dropboxTimer":false,"slskdTimer":false,"gidMusicIngest":null,"gidMedia":null,"onSuccess":[],"importReadyFlag":"","renderedStandard":"","renderedQuarantine":"","djEnable":false,"djShare":"","djRoot":"","djTraktor":"","tmpfilesHasStorageRoot":false,"tmpfilesHasUntagged":false,"tmpfilesHasSlskdEnv":false}'

# 7m-3. Semantic throwaway mutations (S6-12). Each runs in a fresh copy and
# forces the full toplevel through the probe expression.
music_mutation_probe() { # $1 copy, $2 host -> JSON (toplevel forced via drv)
  nix eval --json --no-write-lock-file --apply "$MUSIC_PROBE" "path:${1}#nixosConfigurations.${2}.config"
}
assert_probe() { # $1 host, $2 json, $3 semantic check name
  python3 - "$1" "$2" "$3" <<'PYEOF' || fail "7m mutation $1: $3 failed"
import json, sys
host, raw, check = sys.argv[1], sys.argv[2], sys.argv[3]
got = json.loads(raw)
errs = []
if check == "disabled":
    if got["enable"]:
        errs.append(f"enable still {got['enable']!r}")
    if got["contractPresent"]:
        errs.append("contract still present")
    if got["ingest"] or got["storage"]:
        errs.append("private leaves still enabled")
    if got["ffmpegUnit"] or got["reconcileUnit"]:
        errs.append("music units still active")
elif check == "explicit-dj":
    if got["musicOptionCount"] != 0:
        errs.append("music options must stay absent without selection")
    if got["djShare"] != "/srv/storage/media/music" or got["djRoot"] != "/srv/storage/media/music":
        errs.append(f"explicit DJ values not honoured: {got['djShare']!r}/{got['djRoot']!r}")
elif check == "music-no-dj":
    if not got["enable"] or not got["contractPresent"]:
        errs.append("music must stay enabled with its contract")
    if not got["ffmpegUnit"] or not got["reconcileUnit"]:
        errs.append("music units missing")
    if got["djEnable"]:
        errs.append("dj must stay disabled")
else:
    errs.append(f"unknown check {check}")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

assert_probe_result() { # $1 host, $2 copy, $3 semantic check name
  local host="$1" copy="$2" check="$3" result
  result="$(music_mutation_probe "$copy" "$host")" || fail "7m mutation ${host}: ${check} probe did not evaluate"
  assert_probe "$host" "$result" "$check"
}

# 7m-3a. Discovery is not placement: adding aspects.music without host
# bindings cannot silently activate the stack (selection is the activation
# edge and requires explicit host values).
D="$(make_copy)"
python3 - "$D/modules/hosts/la-admin-1/default.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index("la-admin-1 = {")
j = s.index("aspects.identity-client", i)
k = s.index("\n", j)
open(p, "w").write(s[: k + 1] + "        aspects.music\n" + s[k + 1 :])
PYEOF
expect_eval_fail "$D" la-admin-1 "applications.music.dataRoot"

# 7m-3b. Removing the selected aspect's enablement leaves the selection in
# place but disables the application (enable false, contract unset, leaves and
# units inert). The copy restores pre-contract explicit DJ values so the named
# DJ assertion is not what this probe exercises.
D="$(make_copy)"
sed -i '/applications\.music\.enable = true;/d' "$D/modules/music/music.nix"
python3 - "$D/modules/hosts/home-forge/_nixos.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """  applications.dj = {
    engine = {
      enable = true;
"""
new = """  applications.dj = {
    engine = {
      enable = true;
      sharePath = musicStorageRoot;
      musicStorageRoot = musicStorageRoot;
"""
assert old in s
open(p, "w").write(s.replace(old, new))
PYEOF
assert_probe_result home-forge "$D" disabled

# 7m-3c. A host direct import of a music implementation is detected by the
# owner-import predicate, and the import cannot silently merge into a host
# assembly: music implementations are flake-parts contributors, so importing one
# as a NixOS module fails evaluation loudly instead of activating placement.
D="$(make_copy)"
sed -i '/\.\/_disko-two-disk\.nix/a\    ../../../modules/music/ingest.nix' "$D/modules/hosts/home-forge/_nixos.nix"
[ -n "$(music_host_imports_of "$D")" ] ||
  fail "7m-3c: host-import predicate must detect a direct modules/music import"
expect_eval_fail "$D" home-forge "The option \`flake' does not exist"

# 7m-3d. A foreign publication smuggled into the music contributor set is
# rejected by the publication scan and shows up as publication-inventory drift
# (the exact-set equality in 7a is what catches a new publication, since music
# contributors are discovered); selecting nothing keeps it inert.
D="$(make_copy)"
cat >"$D/modules/music/evil-pub.nix" <<'EOF'
{ ... }:
{
  flake.modules.nixos.evil-music-pub = { };
}
EOF
[ -n "$(music_leaf_publishers_of "$D")" ] ||
  fail "7m-3d: music publication scan must reject a foreign flake.modules.nixos publication"
[ "$(pub_names_of "$D")" != "$expected_pub" ] ||
  fail "7m-3d: a foreign music publication must show up as publication-inventory drift"
nix eval --raw --no-write-lock-file "path:${D}#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath" >/dev/null ||
  fail "7m-3d: an unselected publication must not affect the host toplevel eval"

# 7m-3e. Deleting the music aspect entry is detected through the observable it
# owns, not through publication loss: the eight sibling contributors still
# publish flake.modules.nixos.music (deferredModule merge), while the option
# namespace the host record writes into is gone.
D="$(make_copy)"
rm "$D/modules/music/music.nix"
[ "$(pub_names_of "$D")" = "$expected_pub" ] ||
  fail "7m-3e: sibling music contributors must still publish the music aspect after the entry is deleted"
expect_eval_fail "$D" home-forge "The option \`applications.music' does not exist"

# 7m-3f. DJ selected/enabled without music and without explicit values fails
# with the exact named assertion; with both values explicit it succeeds.
D="$(make_copy)"
sed -i '/aspects\.music/d' "$D"/modules/hosts/*/default.nix
strip_host_block "$D/modules/hosts/home-forge/_nixos.nix" "applications.music = {"
expect_eval_fail "$D" home-forge "applications.dj.engine requires applications.music.contract"

D="$(make_copy)"
sed -i '/aspects\.music/d' "$D"/modules/hosts/*/default.nix
strip_host_block "$D/modules/hosts/home-forge/_nixos.nix" "applications.music = {"
python3 - "$D/modules/hosts/home-forge/_nixos.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = """  applications.dj = {
    engine = {
      enable = true;
"""
new = """  applications.dj = {
    engine = {
      enable = true;
      sharePath = musicStorageRoot;
      musicStorageRoot = musicStorageRoot;
"""
assert old in s
open(p, "w").write(s.replace(old, new))
PYEOF
assert_probe_result home-forge "$D" explicit-dj

# 7m-3g. Music selected without DJ succeeds and retains its observables.
D="$(make_copy)"
sed -i '/aspects\.dj/d' "$D"/modules/hosts/*/default.nix
strip_host_block "$D/modules/hosts/home-forge/_nixos.nix" "applications.dj = {"
assert_probe_result home-forge "$D" music-no-dj

# --- 7n. Stage 7 placement aspects (S7-2..S7-9) ------------------------------
# (openspec change dendritic-stage-7-placement-aspects tasks 6.1-6.3)
#
# Every deployed product/platform capability is placed by explicit selection of
# a discovered aspect; hosts import no workload implementation; private
# implementation leaves are owned by exactly one concern; discovery alone
# activates nothing; the two removed roots stay absent; and the transitional
# boundary is exactly hosts+services. Every semantic mutation below runs
# against a throwaway copy and forces the full toplevel derivation through
# PLACEMENT_PROBE.

# Placement contributors: the eleven historical Stage 7 aspects (S7-2) plus
# the six capabilities extracted by decouple-identity-admin-capabilities
# (termix, vaultwarden, gatus, beszel, homepage, webhook). Every placement
# contributor publishes its own flake.modules.nixos.<name> aspect; settled
# concerns live in their domain directory (stage 8 task 5.1), the rest still
# sit in modules/flake/.
placement_dir_of() {
  case "$1" in
    push-server) echo modules/notifications ;;
    identity-provider) echo modules/identity ;;
    niks3-cache) echo modules/cache ;;
    edge) echo modules/edge ;;
    oci) echo modules/oci ;;
    cockpit | termix | vaultwarden | gatus | beszel | homepage | webhook) echo modules/admin ;;
    *) echo modules/flake ;;
  esac
}
placement_aspects="oci edge cockpit push-server identity-provider paperless postgres ai-gateway karakeep niks3-cache phoenix omniroute termix vaultwarden gatus beszel homepage webhook"
for a in $placement_aspects; do
  a_dir="$(placement_dir_of "$a")"
  test -f "$a_dir/$a.nix" || fail "7n: placement contributor $a_dir/$a.nix missing"
  grep -qE "^[[:space:]]*flake\.modules\.nixos\.${a}[[:space:]]*=" "$a_dir/$a.nix" ||
    fail "7n: $a_dir/$a.nix must publish flake.modules.nixos.$a"
done
# Private implementations live beside their concern owner (S7-3/S7-4/S7-5) and
# are reachable only through it.
test -f modules/oci/_oci/default.nix || fail "7n: relocated OCI provider leaf missing"
test -f modules/edge/_edge/edge-ingress.nix || fail "7n: relocated edge-ingress implementation missing"
test -f modules/music/_dj/default.nix || fail "7n: relocated DJ composition missing"
test -f modules/music/_dj/engine-dj.nix || fail "7n: relocated DJ engine implementation missing"
grep -q '\./_oci/default\.nix' modules/oci/oci.nix || fail "7n: the oci aspect must import its private leaf"
grep -q '\./_edge/edge-ingress\.nix' modules/edge/edge.nix || fail "7n: the edge aspect must import its private leaf"
grep -q '\./_dj' modules/music/dj.nix || fail "7n: the dj aspect must import its private leaf"
# Ownership is asserted on import *expressions*, not on prose: current-state docs and
# comments legitimately name these paths (e.g. the consumers note in
# modules/music/windows-vm.nix), while a real import from another
# concern must still be rejected. Mutation 7n-3f-2 proves the predicate still fires.
private_leaf_stray="$(grep -REl --include='*.nix' -e '_oci/default\.nix' -e '_edge/edge-ingress\.nix' modules | grep -vE '^modules/(oci/oci|edge/edge)\.nix$' || true)"
[ -z "$private_leaf_stray" ] ||
  fail "7n: only the owning concern may import a Stage 7 private leaf: $private_leaf_stray"
dj_leaf_stray="$(grep -REl --include='*.nix' -e '\./_dj([^a-zA-Z0-9_-]|$)' -e '_dj/default\.nix' -e '_dj/engine-dj\.nix' modules | grep -vE '^modules/music/(dj\.nix|_dj/)' || true)"
[ -z "$dj_leaf_stray" ] || fail "7n: only the dj concern may import the _dj private leaves: $dj_leaf_stray"
# The evaluator-class roots are deleted, not renamed (S7-4/S7-5/S7-8).
[ -z "$(surviving_evacuated_roots "$ROOT")" ] ||
  fail "7n: converted application/provider roots must be deleted: $(surviving_evacuated_roots "$ROOT")"
test ! -e modules/flake/_applications || fail "7n: no underscore-renamed applications root may exist"
test ! -e modules/flake/_providers || fail "7n: no underscore-renamed providers root may exist"

# 7n-1. Hosts import no workload implementation; host-local disk/hardware/policy
# fragments and overlays remain allowed (S7-6, task 6.3: the guard forbids
# boundary growth and direct host-to-workload imports without banning
# host-private fragments).
#
# The guard is a positive allowlist over every entry of every `imports` list in
# host assemblies. Only host-local `./...` paths without a `..` segment and
# `modulesPath`-derived entries are permitted; the opening bracket may be on the
# assignment line or the following line.
host_workload_imports_of() { # $1 repo root
  find "$1/modules/hosts" -type f -name '*.nix' -print0 |
    xargs -0 -r awk '
      BEGIN { inlist = 0; pending = 0; depth = 0 }
      {
        if (!inlist && !pending && $0 ~ /(^|[[:space:]])imports[[:space:]]*=/) pending = 1
        if (pending && $0 ~ /\[/) { inlist = 1; pending = 0 }
        if (!inlist) next
        line = $0
        opens = gsub(/\[/, "", line)
        closes = gsub(/\]/, "", line)
        entry = $0
        sub(/^[[:space:]]*/, "", entry)
        sub(/^imports[[:space:]]*=[[:space:]]*/, "", entry)
        sub(/^\[[[:space:]]*/, "", entry)
        gsub(/\]/, "", entry)
        sub(/;[[:space:]]*$/, "", entry)
        sub(/^[[:space:]]*/, "", entry)
        sub(/[[:space:]]*$/, "", entry)
        host_local = entry ~ /^\.\// && entry !~ /(^|\/)\.\.($|\/)/
        if (entry != "" && entry !~ /^#/ && !host_local && entry !~ /modulesPath/) {
          print FILENAME ":" FNR ":" entry
        }
        depth += opens - closes
        if (depth <= 0) inlist = 0
      }
    ' 2>/dev/null || true
}
[ -z "$(host_workload_imports_of "$ROOT")" ] ||
  fail "7n-1: host assemblies must not import application/provider/workload implementations: $(host_workload_imports_of "$ROOT")"
for f in \
  modules/hosts/oci-melb-1/_disko-single-disk-split.nix \
  modules/hosts/oci-melb-1/facter.json \
  modules/hosts/home-forge/_disko-two-disk.nix; do
  test -e "$f" || fail "7n-1: host-local fragment $f must be retained"
done
grep -q '\./_cockpit-auth\.nix' modules/hosts/la-admin-1/_nixos.nix ||
  fail "7n-1: the direct-import guard must permit host-private fragments"

# 7n-2. Semantic placement matrix. Each field is read defensively so an
# unselected host renders false/absent rather than failing, and the toplevel
# derivation is forced so option-merge and assertion failures surface.
PLACEMENT_PROBE='c: {
  drv = c.system.build.toplevel.drvPath;
  ociSerialConsole = builtins.elem "console=ttyAMA0,115200n8" (c.boot.kernelParams or [ ]);
  # Presence, not a frozen list: `boot.loader.grub.devices` is currently set by
  # both the `oci` private leaf and the disko-derived value, so it legitimately
  # contains a pre-existing duplicate that Stage 7 must not pin as a contract.
  grubHasSda = builtins.elem "/dev/sda" (c.boot.loader.grub.devices or [ ]);
  serialGetty = c.systemd.services ? "serial-getty@ttyAMA0";
  edgeEnable = (c.applications."edge-ingress" or { }).enable or false;
  edgeRole = (c.applications."edge-ingress" or { }).role or "";
  # Semantic route assertions rather than a brittle exact count: the edge
  # contract is that the host policy routes are projected, plus representative
  # catalog keys, so a future route addition cannot fail this check.
  edgeHasRoutes = (builtins.attrNames ((c.applications."edge-ingress" or { }).routes or { })) != [ ];
  edgeRouteSample = builtins.sort builtins.lessThan (
    builtins.filter
      (k: builtins.elem k [ "navidrome" "termix-admin" "kanidm-admin" "admin-homepage" "webhook-admin" ])
      (builtins.attrNames ((c.applications."edge-ingress" or { }).routes or { }))
  );
  caddyEnable = c.services.caddy.enable or false;
  cockpitEnable = c.services.admin.cockpit.enable or false;
  cockpitServiceUser = c.services.admin.cockpit.serviceUser.name or "";
  cockpitSecret = c.sops.secrets.cockpit_service_user_password_hash.path or "";
  ntfyServerEnable = c.services.ntfy.enable or false;
  kanidmEnable = c.services.identity.kanidm.enable or false;
  kanidmAppUrl = c.services.identity.kanidm.appUrl or "";
  termixEnable = c.services.admin.termix.enable or false;
  adminSshSecrets = builtins.length (builtins.filter (n: n == "admin_ssh_identity" || n == "admin_ssh_known_hosts") (builtins.attrNames c.sops.secrets));
  paperlessEnable = c.services.paperless.enable or false;
  postgresEnable = c.services.postgres.enable or false;
  postgresInstances = builtins.attrNames (c.services.postgres.instances or { });
  postgresConsumers = builtins.attrNames (c.services.postgres.consumers or { });
  bifrostEnable = c.services.bifrost-gateway.enable or false;
  karakeepEnable = c.services.karakeep-pod.enable or false;
  niks3CacheEnable = c.services.niks3-cache.enable or false;
  niks3ServerEnable = c.services.niks3.enable or false;
  phoenixEnable = c.services.phoenix.enable or false;
  omnirouteEnable = c.services.omniroute.enable or false;
  omnirouteMonitor = builtins.hasAttr "podman-omniroute" (c.services.notification-daemon.monitor.units or { });
  monitorUnits = builtins.attrNames (c.services.notification-daemon.monitor.units or { });
}'

probe_placement() { # $1 repo root, $2 host -> JSON
  nix eval --json --no-write-lock-file --apply "$PLACEMENT_PROBE" "path:${1}#nixosConfigurations.${2}.config"
}

assert_placement() { # $1 host, $2 probe JSON, $3 expected JSON (dict subset)
  python3 - "$1" "$2" "$3" <<'PYEOF' || fail "7n-2: $1 placement observables violated"
import json, sys
host, got_raw, exp_raw = sys.argv[1], sys.argv[2], sys.argv[3]
got, exp = json.loads(got_raw), json.loads(exp_raw)
if not got.get("drv"):
    print(f"{host}: placement probe did not force the toplevel", file=sys.stderr)
    sys.exit(1)
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in exp.items() if got.get(k) != v]
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

placement_json="$(probe_placement "$ROOT" oci-melb-1)" || fail "7n-2: oci-melb-1 placement probe does not evaluate"
assert_placement oci-melb-1 "$placement_json" '{"ociSerialConsole":true,"grubHasSda":true,"serialGetty":true,"edgeEnable":true,"edgeRole":"origin","edgeHasRoutes":false,"edgeRouteSample":[],"caddyEnable":false,"cockpitEnable":true,"cockpitServiceUser":"cockpit-svc","cockpitSecret":"/run/secrets/cockpit.service_user.password_hash","ntfyServerEnable":false,"kanidmEnable":false,"adminSshSecrets":0,"paperlessEnable":true,"postgresEnable":true,"postgresInstances":["postgres"],"postgresConsumers":["paperless"],"bifrostEnable":true,"karakeepEnable":true,"niks3CacheEnable":true,"niks3ServerEnable":true,"phoenixEnable":true,"omnirouteEnable":false,"omnirouteMonitor":false}'
placement_json="$(probe_placement "$ROOT" la-admin-1)" || fail "7n-2: la-admin-1 placement probe does not evaluate"
assert_placement la-admin-1 "$placement_json" '{"ociSerialConsole":false,"grubHasSda":false,"serialGetty":false,"edgeEnable":true,"edgeRole":"edge","edgeHasRoutes":true,"edgeRouteSample":["admin-homepage","kanidm-admin","navidrome","termix-admin","webhook-admin"],"caddyEnable":true,"cockpitEnable":true,"cockpitServiceUser":"cockpit-svc","cockpitSecret":"/run/secrets/cockpit.service_user.password_hash","ntfyServerEnable":true,"kanidmEnable":true,"kanidmAppUrl":"https://id.shrublab.xyz","termixEnable":true,"adminSshSecrets":2,"paperlessEnable":false,"postgresEnable":false,"postgresInstances":[],"postgresConsumers":[],"bifrostEnable":false,"karakeepEnable":false,"niks3CacheEnable":false,"niks3ServerEnable":false,"phoenixEnable":false,"omnirouteEnable":false,"omnirouteMonitor":false}'
placement_json="$(probe_placement "$ROOT" home-forge)" || fail "7n-2: home-forge placement probe does not evaluate"
assert_placement home-forge "$placement_json" '{"ociSerialConsole":false,"grubHasSda":false,"serialGetty":false,"edgeEnable":false,"edgeRole":"","edgeHasRoutes":false,"edgeRouteSample":[],"caddyEnable":false,"cockpitEnable":false,"cockpitServiceUser":"","cockpitSecret":"","ntfyServerEnable":false,"kanidmEnable":false,"adminSshSecrets":0,"paperlessEnable":false,"postgresEnable":true,"postgresInstances":["forge"],"postgresConsumers":["audiomuse"],"bifrostEnable":false,"karakeepEnable":false,"niks3CacheEnable":false,"niks3ServerEnable":false,"phoenixEnable":false,"omnirouteEnable":true,"omnirouteMonitor":true}'

# 7n-3. Semantic throwaway mutations (tasks 6.2/6.3). Each fails for its
# intended semantic reason rather than a generic parse error, and the working
# tree is never modified.

# 7n-3a. Missing placement: dropping a host's aspect selection disables exactly
# that capability while the toplevel still evaluates.
D="$(make_copy)"
sed -i '/aspects\.phoenix/d' "$D"/modules/hosts/*/default.nix
json="$(probe_placement "$D" oci-melb-1)" || fail "7n-3a: OCI must still evaluate without the phoenix aspect"
assert_placement oci-melb-1 "$json" '{"phoenixEnable":false}'

# 7n-3b. Extra placement: adding an unselected aspect to a host activates the
# capability there, so accidental placement is observable.
D="$(make_copy)"
sed -i '/aspects\.phoenix/i\        aspects.omniroute' "$D"/modules/hosts/*/default.nix
json="$(probe_placement "$D" oci-melb-1)" || fail "7n-3b: OCI must still evaluate with a wrongly selected aspect"
assert_placement oci-melb-1 "$json" '{"omnirouteEnable":true}'

# 7n-3c. Selection no longer supplying top-level enablement is detected: the
# selected aspect stays in the registry but the capability is inert.
D="$(make_copy)"
sed -i '/services\.phoenix\.enable = true;/d' "$D/modules/flake/phoenix.nix"
json="$(probe_placement "$D" oci-melb-1)" || fail "7n-3c: OCI must still evaluate with the enablement removed"
assert_placement oci-melb-1 "$json" '{"phoenixEnable":false}'

# 7n-3d. A direct host import of a workload implementation is detected by the
# guard, and it cannot silently place the workload: discovered contributors are
# flake-parts modules, so importing one into a host assembly fails evaluation
# loudly instead of activating it (import != placement, enforced twice).
D="$(make_copy)"
sed -i '/^    \.\/_cockpit-auth\.nix$/i\    ../../../modules/flake/phoenix.nix' "$D/modules/hosts/la-admin-1/_nixos.nix"
[ -n "$(host_workload_imports_of "$D")" ] ||
  fail "7n-3d: the host-import guard must detect a directly imported workload implementation"
expect_eval_fail "$D" la-admin-1 "The option \`flake' does not exist"

# 7n-3d-2. Path-form-independent guard: plain and `./..`-prefixed relative
# workload imports plus host-side re-enablement contain no `modules/...` text and
# no `aspects.` reference. The guard must reject both forms, and the bypass must
# not evaluate at all (an aspect contributor is not a NixOS module), so the
# mutation cannot pass vacuously by merely failing to activate.
D="$(make_copy)"
python3 - "$D/modules/hosts/la-admin-1/_nixos.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
assert s.count("    ./_cockpit-auth.nix\n") == 1, "import anchor drifted"
assert s.count("  services = {\n") == 1, "services anchor drifted"
s = s.replace("    ./_cockpit-auth.nix\n", "    ../../flake/phoenix.nix\n    ./_cockpit-auth.nix\n", 1)
s = s.replace("  services = {\n", "  services = {\n    phoenix.enable = true;\n", 1)
open(p, "w").write(s)
PYEOF
[ -n "$(host_workload_imports_of "$D")" ] ||
  fail "7n-3d-2: the path-form-independent guard must reject ../../flake/phoenix.nix + enablement"
expect_eval_fail "$D" la-admin-1 "The option \`flake' does not exist"
sed -i 's#../../flake/phoenix\.nix#./../../flake/phoenix.nix#' "$D/modules/hosts/la-admin-1/_nixos.nix"
[ -n "$(host_workload_imports_of "$D")" ] ||
  fail "7n-3d-2: the host-import guard must reject ./../../flake/phoenix.nix"

# 7n-3e. Discovery alone is inert: a freshly published, unselected aspect does
# not activate anything, and selecting it is the only activation edge.
D="$(make_copy)"
cat >"$D/modules/flake/tamper-aspect.nix" <<'EOF'
{ ... }:
{
  flake.modules.nixos.tamper-aspect = {
    # A REAL unit (`podman-prune` is implemented on every host) so the
    # fail-closed monitor contract stays satisfied and only contribution
    # visibility is under test (MON-1/MON-3).
    services.notification-daemon.monitor.units."podman-prune".onFailure = true;
  };
}
EOF
json="$(probe_placement "$D" la-admin-1)" || fail "7n-3e: LA must still evaluate with an unselected publication"
python3 - "$json" <<'PYEOF' || fail "7n-3e: an unselected discovered aspect must not activate"
import json, sys
got = json.loads(sys.argv[1])
if "podman-prune" in got["monitorUnits"]:
    raise SystemExit(f"discovery alone activated an aspect: {got['monitorUnits']!r}")
PYEOF
python3 - "$D/modules/hosts/la-admin-1/default.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index("la-admin-1 = {")
j = s.index("        aspects.identity-provider", i)
k = s.index("\n", j)
open(p, "w").write(s[: k + 1] + "        aspects.tamper-aspect\n" + s[k + 1 :])
PYEOF
json="$(probe_placement "$D" la-admin-1)" || fail "7n-3e: LA must evaluate with the tamper aspect selected"
python3 - "$json" <<'PYEOF' || fail "7n-3e: selecting the discovered aspect must activate it"
import json, sys
got = json.loads(sys.argv[1])
if "podman-prune" not in got["monitorUnits"]:
    raise SystemExit(f"selection did not activate the aspect: {got['monitorUnits']!r}")
PYEOF
json="$(probe_placement "$D" oci-melb-1)" || fail "7n-3e: OCI must still evaluate with the tamper contributor present"
python3 - "$json" <<'PYEOF' || fail "7n-3e: a selection on one host must not activate another host"
import json, sys
got = json.loads(sys.argv[1])
if "podman-prune" in got["monitorUnits"]:
    raise SystemExit(f"unselected host activated the aspect: {got['monitorUnits']!r}")
PYEOF

# 7n-3f. A publication smuggled into an underscore-private leaf is rejected by
# the private-owner scan and stays invisible to discovery.
D="$(make_copy)"
printf '\n  flake.modules.nixos.evil-edge = { };\n' >>"$D/modules/edge/_edge/edge-ingress.nix"
grep -RnE --include='*.nix' 'flake\.modules\.nixos\.[a-z0-9-]+[[:space:]]*=' "$D/modules/edge/_edge" >/dev/null ||
  fail "7n-3f: the private-owner scan must reject a publication under _edge"
case "$(pub_names_of "$D")" in
  *evil-edge*) fail "7n-3f: an underscore-private publication must not be discovered" ;;
esac

# 7n-3f-2. Both import-form ownership predicates still fire on a real import of a
# private leaf from another concern, so narrowing them away from prose (which must
# be allowed to name these paths) did not make them vacuous.
D="$(make_copy)"
printf '\n  imports = [\n    ./_dj\n    ./_oci/default.nix\n  ];\n' >>"$D/modules/flake/phoenix.nix"
[ -n "$(grep -REl --include='*.nix' -e '\./_dj([^a-zA-Z0-9_-]|$)' -e '_dj/default\.nix' -e '_dj/engine-dj\.nix' "$D/modules" |
  grep -vE "^$D/modules/music/(dj\.nix|_dj/)" || true)" ] ||
  fail "7n-3f-2: the _dj ownership predicate must detect an import from another concern"
[ -n "$(grep -REl --include='*.nix' -e '_oci/default\.nix' -e '_edge/edge-ingress\.nix' "$D/modules" |
  grep -vE "^$D/modules/(oci/oci|edge/edge)\.nix\$" || true)" ] ||
  fail "7n-3f-2: the _oci/_edge ownership predicate must detect an import from another concern"

# 7n-3f-3. A prose reference to a private path outside an import list is allowed
# (current-state docs and consumer comments legitimately name them), while the
# import-form predicate above still rejects real imports.
D="$(make_copy)"
printf '\n# consumers (e.g. modules/music/_dj) are documented here\n' >>"$D/modules/flake/phoenix.nix"
[ -z "$(grep -REl --include='*.nix' -e '\./_dj([^a-zA-Z0-9_-]|$)' -e '_dj/default\.nix' -e '_dj/engine-dj\.nix' "$D/modules" |
  grep -vE "^$D/modules/music/(dj\.nix|_dj/)" || true)" ] ||
  fail "7n-3f-3: a prose mention of a private path must not be treated as an import"

# 7n-3g. A reintroduced compatibility root is rejected even when the boundary
# list is widened to hide it.
D="$(make_copy)"
mkdir -p "$D/modules/applications"
printf '{ ... }: { }\n' >"$D/modules/applications/wrapper.nix"
[ "$(surviving_evacuated_roots "$D")" = "modules/applications" ] ||
  fail "7n-3g: the root-evacuation predicate must detect a reintroduced modules/applications"
sed -i '/^  "services"$/i\  "applications"' "$D/modules/flake/_unconverted-nixos-dirs.nix"
[ "$(unconverted_roots "$D")" != '["services"]' ] ||
  fail "7n-3g: widening the boundary back to applications must break the exact single-root set"

# 7n-3h. The transitional boundary may not grow and may not be thinned without
# deleting the directory.
D="$(make_copy)"
sed -i '/^  "services"$/a\  "core"' "$D/modules/flake/_unconverted-nixos-dirs.nix"
[ "$(unconverted_roots "$D")" != '["services"]' ] ||
  fail "7n-3h: a widened services boundary must be rejected"
D="$(make_copy)"
sed -i '/^  "services"$/d' "$D/modules/flake/_unconverted-nixos-dirs.nix"
test -d "$D/modules/services" || fail "7n-3h: prepared copy must still contain modules/services"
[ "$(unconverted_roots "$D")" != '["services"]' ] ||
  fail "7n-3h: an unbacked boundary shrink must be rejected"

# --- 7o. Feature-owned monitor contract (MON-1..MON-4) ----------------------
# (openspec change feature-owned-service-monitoring tasks 2.1-2.3, 3.1, 3.2.)
# Monitoring participation is contributed by the capability that owns each
# unit, so the observable contract is per host: the old list option and every
# reverse index are gone, only real implementations are monitored, the Beets
# units follow the music placement (home-forge yes, OCI no synthetic
# fragments), and owner-defined hooks survive the additive merge.

# 7o-1. The host-maintained list option is gone: no assignment survives in
# source, and the checks probe the typed contract instead of the removed list.
if grep -RnE --include='*.nix' 'monitor\.services' modules lib policy; then
  fail "7o-1: the removed monitor.services list must have no assignment left"
fi
if grep -RnE --include='*.nix' 'monitor\.services' tests; then
  fail "7o-1: checks must probe monitor.units, not the removed monitor.services list"
fi
grep -q 'monitor\.units' modules/notifications/notify.nix ||
  fail "7o-1: the typed monitor.units contract must be declared by the notify aspect"

# 7o-2. Per-host observable monitoring contract. Every contributed unit must
# have a real implementation, the contribution set must match the owning
# capabilities exactly (no host reverse index, no phantom Beets fragment), and
# each contributed unit must really receive its declared generic hooks.
MONITOR_PROBE='c: let
  units = c.services.notification-daemon.monitor.units or { };
  svc = c.systemd.services or { };
  isReal = n: let s = svc.${n} or null; in
    s != null && ((s.serviceConfig.ExecStart or null) != null || ((s.script or "") != ""));
  render = e:
    if builtins.isString e then e
    else if builtins.isPath e then builtins.toString e
    else builtins.toJSON e;
  cmds = v:
    if v == null then [ ]
    else if builtins.isList v then builtins.map render v
    else [ (render v) ];
  isBeets = n: builtins.match "beets-.*" n != null;
  names = builtins.attrNames units;
  beets = builtins.filter isBeets (builtins.attrNames svc);
in {
  drv = c.system.build.toplevel.drvPath;
  enable = c.services.notification-daemon.monitor.enable or false;
  names = builtins.sort builtins.lessThan names;
  unreal = builtins.filter (n: !(isReal n)) names;
  beetsAttrs = builtins.sort builtins.lessThan beets;
  beetsReal = builtins.filter isReal (builtins.filter isBeets names);
  beetsInboxPresent = svc ? "beets-inbox";
  hooks = builtins.listToAttrs (map (n: {
    name = n;
    value = {
      onFailure = svc.${n}.onFailure or [ ];
      execStartPost = cmds (svc.${n}.serviceConfig.ExecStartPost or null);
      execStopPost = cmds (svc.${n}.serviceConfig.ExecStopPost or null);
    };
  }) names);
}'

probe_monitor() { # $1 host -> JSON
  nix eval --json --no-write-lock-file --apply "$MONITOR_PROBE" "path:${ROOT}#nixosConfigurations.${1}.config"
}

monitor_json="$(probe_monitor oci-melb-1)" || fail "7o-2: oci-melb-1 monitor probe does not evaluate"
python3 - oci-melb-1 "$monitor_json" <<'PYEOF' || fail "7o-2: oci-melb-1 monitor contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if not got["enable"]:
    errs.append("monitor.enable must be true on a notify-selected host")
if got["unreal"]:
    errs.append(f"contributed units without an implementation: {got['unreal']!r}")
if got["names"] != ["beszel-agent", "nh-clean", "podman-storage-prune"]:
    errs.append(f"contributed units drifted from the owning capabilities: {got['names']!r}")
if got["beetsAttrs"]:
    errs.append(f"OCI must evaluate no Beets service fragments: {got['beetsAttrs']!r}")
if got["beetsInboxPresent"]:
    errs.append("OCI must not define a beets-inbox unit")
for name, hooks in got["hooks"].items():
    if not any(c.endswith(f"{name}.service") and "svc-monitor" in c for c in hooks["onFailure"]):
        errs.append(f"{name}: OnFailure monitor hook missing ({hooks['onFailure']!r})")
    if not any("svc-monitor" in c and "onStart" in c for c in hooks["execStartPost"]):
        errs.append(f"{name}: ExecStartPost monitor hook missing ({hooks['execStartPost']!r})")
    if not any("svc-monitor" in c and "onSuccess" in c for c in hooks["execStopPost"]):
        errs.append(f"{name}: ExecStopPost monitor hook missing ({hooks['execStopPost']!r})")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

monitor_json="$(probe_monitor la-admin-1)" || fail "7o-2: la-admin-1 monitor probe does not evaluate"
python3 - la-admin-1 "$monitor_json" <<'PYEOF' || fail "7o-2: la-admin-1 monitor contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if not got["enable"]:
    errs.append("monitor.enable must be true on a notify-selected host")
if got["unreal"]:
    errs.append(f"contributed units without an implementation: {got['unreal']!r}")
if got["names"] != ["beszel-agent", "nh-clean"]:
    errs.append(f"contributed units drifted from the owning capabilities: {got['names']!r}")
if got["beetsAttrs"]:
    errs.append(f"la-admin-1 must evaluate no Beets service fragments: {got['beetsAttrs']!r}")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

monitor_json="$(probe_monitor home-forge)" || fail "7o-2: home-forge monitor probe does not evaluate"
python3 - home-forge "$monitor_json" <<'PYEOF' || fail "7o-2: home-forge Beets monitoring contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if not got["enable"]:
    errs.append("monitor.enable must be true on a notify-selected host")
if got["unreal"]:
    errs.append(f"contributed units without an implementation: {got['unreal']!r}")
expected = ["beets-duplicates", "beets-inbox", "beets-reconcile", "beszel-agent", "nh-clean", "podman-omniroute"]
if got["names"] != expected:
    errs.append(f"contributed units drifted from the owning capabilities: {got['names']!r}")
if got["beetsReal"] != ["beets-duplicates", "beets-inbox", "beets-reconcile"]:
    errs.append(f"real Beets units drifted: {got['beetsReal']!r}")
# The interactive quarantine review worker is not an automated runner and must
# stay unmonitored (it keeps only its own failure hook).
hooks = got["hooks"]
for unit in ("beets-inbox", "beets-reconcile", "beets-duplicates"):
    h = hooks.get(unit)
    if h is None:
        errs.append(f"{unit}: no monitor hooks")
        continue
    if not any(c.endswith(f"{unit}.service") and "svc-monitor" in c for c in h["onFailure"]):
        errs.append(f"{unit}: OnFailure monitor hook missing ({h['onFailure']!r})")
    if not any("svc-monitor" in c and "onStart" in c for c in h["execStartPost"]):
        errs.append(f"{unit}: ExecStartPost monitor hook missing ({h['execStartPost']!r})")
    if not any("svc-monitor" in c and "onSuccess" in c for c in h["execStopPost"]):
        errs.append(f"{unit}: ExecStopPost monitor hook missing ({h['execStopPost']!r})")
# Feature-owned Beets hooks (deployed baseline: OnFailure retry timer plus the
# failure notification template) survive the additive merge.
inbox = hooks.get("beets-inbox", {})
if "beets-inbox-retry.timer" not in inbox.get("onFailure", []):
    errs.append(f"beets-inbox: feature-owned retry timer lost ({inbox.get('onFailure')!r})")
if not any("beets-notify-failure" in c for c in inbox.get("onFailure", [])):
    errs.append(f"beets-inbox: feature-owned failure notification lost ({inbox.get('onFailure')!r})")
# Preprocess cleanup ExecStartPost is preserved and deterministically ordered
# after the monitor's start report.
post = inbox.get("execStartPost", [])
if not any("rm -f" in c and "inbox-ready" in c for c in post):
    errs.append(f"beets-inbox: feature-owned preprocess cleanup lost ({post!r})")
elif not ("svc-monitor" in post[0] and "rm -f" in post[-1]):
    errs.append(f"beets-inbox: ExecStartPost order is not monitor-then-cleanup ({post!r})")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 7o-3. Negative: a contribution naming a unit with no implementation fails
# closed and names that unit.
D="$(make_copy)"
python3 - "$D/modules/hosts/oci-melb-1/_nixos.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '      monitor.units."podman-storage-prune" = {\n'
assert anchor in s, "monitor anchor drifted"
s = s.replace(anchor, '      monitor.units."phantom-unit".onFailure = true;\n' + anchor, 1)
open(p, "w").write(s)
PYEOF
expect_eval_fail "$D" oci-melb-1 "'phantom-unit' is contributed for monitoring but has no systemd service implementation"

# 7o-4. Negative: the stale wrong-host Beets registration is rejected instead of
# silently materialising a fragment. OCI owns no Beets unit, so a Beets monitor
# contribution there must fail closed (this is the deployed-baseline drift).
D="$(make_copy)"
python3 - "$D/modules/hosts/oci-melb-1/_nixos.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '      monitor.units."podman-storage-prune" = {\n'
assert anchor in s, "monitor anchor drifted"
s = s.replace(anchor, '      monitor.units."beets-inbox".onFailure = true;\n' + anchor, 1)
open(p, "w").write(s)
PYEOF
expect_eval_fail "$D" oci-melb-1 "'beets-inbox' is contributed for monitoring but has no systemd service implementation"

# 7o-5. Negative: a phantom target contributed through a throwaway aspect is
# rejected too, so the fail-closed check is about the implementation and not
# about which file the contribution came from.
D="$(make_copy)"
cat >"$D/modules/flake/tamper-monitor-aspect.nix" <<'EOF'
{ ... }:
{
  flake.modules.nixos.tamper-monitor-aspect = {
    services.notification-daemon.monitor.units."ghost-unit".onStart = true;
  };
}
EOF
python3 - "$D/modules/hosts/oci-melb-1/default.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
i = s.index("oci-melb-1 = {")
j = s.index("        aspects.oci", i)
k = s.index("\n", j)
open(p, "w").write(s[: k + 1] + "        aspects.tamper-monitor-aspect\n" + s[k + 1 :])
PYEOF
expect_eval_fail "$D" oci-melb-1 "'ghost-unit' is contributed for monitoring but has no systemd service implementation"


# 8a. Canonical host registry schema and generic materializer
# (dendritic-stage-8-host-identity-contracts task 2.1, design HIC-1/HIC-2).
# modules/flake/host-registry.nix declares the flake-level option family
# nixos.hosts; concrete records are declared by host contributors (task 2.2),
# so these checks inject a synthetic registry through a throwaway flake-parts
# flake that imports only that discovered contributor. Named 'host-registry:'
# errors must fail closed, and a minimal valid record must materialize an
# evaluable nixosConfiguration.
host_registry_probe() { # $1 copy root, $2 nixos.hosts literal, $3 function over the registry flake
  local d="$1" hosts="$2" fn="$3" t out rc
  t="$(mktemp -d /tmp/scaffold-hostreg.XXXXXX)"
  cat >"$t/flake.nix" <<EOF2
{
  inputs.repo.url = "path:$d";
  inputs.flake-parts.follows = "repo/flake-parts";
  inputs.nixpkgs.follows = "repo/nixpkgs";
  outputs =
    { self, repo, ... }@inputs:
    let
      registry = inputs.flake-parts.lib.mkFlake { inherit inputs; } {
        systems = [ "x86_64-linux" ];
        imports = [
          "$d/modules/flake/host-registry.nix"
          ({ lib, ... }: { nixos.hosts = $hosts; })
          ({ config, ... }: {
            flake.probe = {
              hosts = config.nixos.hosts;
              hostValidationErrors = config.nixos.hostValidationErrors;
            };
          })
        ];
      };
    in
    {
      inherit (registry) nixosConfigurations;
      hosts = registry.probe.hosts;
      hostValidationErrors = registry.probe.hostValidationErrors;
    };
}
EOF2
  out="$(nix eval --raw --impure --no-write-lock-file --expr "builtins.getFlake (toString $t)" --apply "r: builtins.toJSON (($fn) r)" 2>"$t.err")"
  rc=$?
  cat "$t.err" >&2
  rm -rf "$t" "$t.err"
  if [ "$rc" -eq 0 ]; then
    printf '%s' "$out"
    return 0
  fi
  return "$rc"
}

# Invalid registry: two records claim one host ID, one ID breaks the kebab-case
# shape, two records claim the fleet's existing Tailscale identity, and one
# record omits the two required fields.
HOSTREG_BAD=$(cat <<'NIX'
{
  synth-dup-a = {
    system = "x86_64-linux";
    hostId = "dup";
    tailscale.hostname = "synth-dup-a";
  };
  synth-dup-b = {
    system = "x86_64-linux";
    hostId = "dup";
    tailscale.hostname = "synth-dup-b";
  };
  synth-shape = {
    system = "x86_64-linux";
    hostId = "Bad_Host";
    tailscale.hostname = "synth-shape";
  };
  synth-ts-a = {
    system = "x86_64-linux";
    tailscale.hostname = "la-admin-1";
  };
  synth-ts-b = {
    system = "x86_64-linux";
    tailscale.hostname = "la-admin-1";
  };
  synth-missing = { };
}
NIX
)

D="$(make_copy)"
bad_errors="$(host_registry_probe "$D" "$HOSTREG_BAD" 'h: h.hostValidationErrors')" ||
  fail "8a-1: an invalid registry must report named errors instead of throwing"
for want in \
  "host-registry: duplicate host ID 'dup' is declared by more than one host record" \
  "host-registry: invalid host ID 'Bad_Host' must match ^[a-z0-9][a-z0-9-]*\$" \
  "host-registry: host ID 'Bad_Host' does not match its registry key 'synth-shape'" \
  "host-registry: duplicate Tailscale identity 'la-admin-1' is used by more than one host record" \
  "host-registry: host 'synth-missing' is missing required system or tailscale.hostname"; do
  case "$bad_errors" in
    *"$want"*) ;;
    *) fail "8a-1: expected named error missing: $want (got: $bad_errors)" ;;
  esac
done

# 8a-2. Fail-closed materialization: an invalid registry must not silently
# produce a partial nixosConfigurations set.
errlog="$(mktemp /tmp/scaffold-hostreg-err.XXXXXX)"
if host_registry_probe "$D" "$HOSTREG_BAD" 'h: h.nixosConfigurations.synth-dup-a.config.system.build.toplevel.drvPath' 2>"$errlog"; then
  fail "8a-2: materialization must fail closed while the registry is invalid"
fi
grep -q "host-registry: refusing to materialize hosts" "$errlog" ||
  fail "8a-2: materialization must fail with the named host-registry error (got: $(cat "$errlog"))"
grep -q "duplicate host ID 'dup'" "$errlog" ||
  fail "8a-2: the fail-closed error must name the offending host ID (got: $(cat "$errlog"))"
rm -f "$errlog"

# 8a-3. Minimal valid record: no validation errors, the Tailscale FQDN derives
# from hostname + tailnetSuffix, and the record materializes to a drvPath.
HOSTREG_VALID=$(cat <<'NIX'
{
  synth-valid = {
    system = "x86_64-linux";
    tailscale = {
      hostname = "synth-valid";
      tailnetSuffix = "tail0fe19b.ts.net";
    };
    composition.fragments = [
      {
        system.stateVersion = "25.11";
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub.enable = false;
        boot.loader.systemd-boot.enable = true;
      }
    ];
  };
}
NIX
)

D="$(make_copy)"
valid_report="$(host_registry_probe "$D" "$HOSTREG_VALID" 'h: {
  errors = h.hostValidationErrors;
  fqdn = h.hosts.synth-valid.tailscale.fqdn;
  drv = h.nixosConfigurations.synth-valid.config.system.build.toplevel.drvPath;
}')" ||
  fail "8a-3: a minimal valid record must materialize an evaluable nixosConfiguration"
python3 - "$valid_report" <<'PY' || fail "8a-3: valid-record observables violated: $valid_report"
import json, sys
got = json.loads(sys.argv[1])
errs = []
if got.get("errors") != []:
    errs.append(f"errors: {got.get('errors')!r}")
if got.get("fqdn") != "synth-valid.tail0fe19b.ts.net":
    errs.append(f"fqdn: {got.get('fqdn')!r}")
drv = got.get("drv") or ""
if not drv.endswith(".drv") or "nixos-system-synth-valid" not in drv:
    errs.append(f"drv: {drv!r}")
if errs:
    raise SystemExit("; ".join(errs))
PY

# 8a-4. Availability after task 2.3: the transitional loader and the `hosts`
# discovery exclusion are gone, so every record is declared by its discovered
# contributor exactly once and the three canonical nixosConfigurations outputs
# must still materialize.
registry_keys_real="$(ne --raw --apply 'c: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames c))' 'path:.#nixosConfigurations')" ||
  fail "8a-4: the real flake must still materialize nixosConfigurations"
[ "$registry_keys_real" = '["home-forge","la-admin-1","oci-melb-1"]' ] ||
  fail "8a-4: all three hosts must materialize from discovered contributor records (got: $registry_keys_real)"

# 8a-5. Single-load structural guard: the record contributors must be reached
# only through import-tree discovery (task 2.3 deleted the explicit loader), so
# no .nix file may import a host default.nix. A re-added explicit import would
# double-merge each record into two module instances (the 2.2 review's ordering
# constraint), so this structural assertion is the duplicate-load detector.
[ -z "$(grep -RnE --include='*.nix' '^[[:space:]]*[^#]*\.\.[a-z.-]*/hosts/[^"]*/default\.nix|^[[:space:]]*[^#]*modules/hosts/[^"]*/default\.nix' modules lib policy flake.nix 2>/dev/null || true)" ] ||
  fail "8a-5: host contributors must load only through discovery (found explicit default.nix import)"

echo "check-dendritic-scaffold-contract: PASS"
