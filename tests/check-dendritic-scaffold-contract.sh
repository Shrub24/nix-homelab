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
# Observable evaluations define the contract; negative behavior probes use
# throwaway copies so the working tree remains untouched.

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
  for r in shared storage applications providers services; do
    test ! -e "$1/modules/$r" || printf '%s\n' "modules/$r"
  done
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

# --- 1. Discovery boundary: none remains (DS-1) ------------------------------

# The import-tree boundary was retired with the transition: the generated
# flake.nix discovers ./modules unfiltered, so a plain-NixOS module directory
# fails loudly at discovery instead of being excluded by a list. What remains is
# the root-evacuation guard — the converted roots must be gone, not merely
# unlisted, and no underscore-renamed replacement root may exist.
surviving="$(surviving_evacuated_roots "$ROOT")"
[ -z "$surviving" ] || fail "evacuated roots must be deleted (S5-6 root evacuation): $surviving"

# Generated flake freshness is checked by the dedicated flake-file contract.

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
# Successful flake evaluations below establish that the private host file is
# compatible with the current discovery boundary.

# --- 3. Typed registry materialized into nixosConfigurations (DS-2) ----------

# PostgreSQL provisioning ordering. nixpkgs creates databases and roles
# in `postgresql-setup.service`, which runs *after* `postgresql.service`; a
# consumer's credential or setup SQL therefore cannot live in `postStart` — on a
# fresh cluster the role does not exist yet and the unit fails (start-limit-hit,
# deploy rollback). Provisioning is its own unit, ordered after setup, and it
# converges consumer roles and databases itself from a script rendered per
# generation under /etc, so a unit definition systemd already had loaded
# can never provision a stale consumer set.
# Project only the fields under test: serialising a whole systemd unit forces
# every option, including ones with no default (startLimitBurst).
provision_probe='c: builtins.toJSON (
  (if c.systemd.services ? postgresql-provision then {
    hasUnit = true;
    requires = c.systemd.services.postgresql-provision.requires;
    after = c.systemd.services.postgresql-provision.after;
    partOf = c.systemd.services.postgresql-provision.partOf;
    user = c.systemd.services.postgresql-provision.serviceConfig.User;
    script = c.systemd.services.postgresql-provision.script;
    restartTriggers = builtins.length c.systemd.services.postgresql-provision.restartTriggers;
  pgRestartTriggers = builtins.length c.systemd.services.postgresql.restartTriggers;
    etcProvision = builtins.hasAttr "postgres/provision.sh" c.environment.etc;
    ensureUsers = builtins.length c.services.postgresql.ensureUsers;
    ensureDatabases = builtins.length c.services.postgresql.ensureDatabases;
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
    # Membership, not exact match: both edges are pins — setup (credential
    # application needs the schema) and postgresql (provisioning follows the
    # server's restart).
    for dep in ("postgresql-setup.service", "postgresql.service"):
        if dep not in (got.get("requires") or []):
            errs.append(f"provisioning must require {dep}, got {got.get('requires')!r}")
    for dep in ("postgresql.service", "postgresql-setup.service"):
        if dep not in (got.get("after") or []):
            errs.append(f"provisioning must run after {dep}")
    if "postgresql.target" not in (got.get("partOf") or []):
        errs.append("provisioning must be partOf postgresql.target so a target restart re-applies credentials")
    if "postgresql.service" not in (got.get("partOf") or []):
        errs.append("provisioning must be partOf postgresql.service so it re-runs only after the ordered server restart")
    if got.get("user") != "postgres":
        errs.append("provisioning must run as the postgres superuser")
    if got.get("script") != "exec /etc/postgres/provision.sh":
        errs.append(f"provisioning must exec the /etc trampoline, got {got.get('script')!r}")
    if not got.get("pgRestartTriggers"):
        errs.append("the consumer script must ride postgresql's own restart set (partOf orders provisioning after the server)")
    if got.get("restartTriggers"):
        errs.append("provisioning must not carry its own restartTriggers: an independent enqueue races postgresql's restart order")
    if not got.get("etcProvision"):
        errs.append("the provisioning script must be rendered under /etc")
    if got.get("ensureUsers") or got.get("ensureDatabases"):
        errs.append(
            "consumer roles and databases are the substrate's to converge, not nixpkgs' ensureUsers/ensureDatabases (D-069)"
        )
if got["postStart"]:
    errs.append("provisioning must not live in postgresql.postStart: it runs before postgresql-setup.service creates roles and databases")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# home-forge has a credentialled TCP consumer (langfuse), so the unit must exist.
provision_forge="$(ne --raw --apply 'c: builtins.toJSON (c.systemd.services ? postgresql-provision)' 'path:.#nixosConfigurations.home-forge.config')" ||
  fail "postgres provisioning probe does not evaluate on home-forge"
[ "$provision_forge" = "true" ] ||
  fail "home-forge registers a credentialled TCP consumer (langfuse), so postgresql-provision must exist"

# pg_hba rows carry a mask. A maskless address shifts the auth-method column into
# the netmask field and postgres refuses to load the entire file, which would take
# the cluster down on the next activation.
for host in home-forge la-admin-1 oci-melb-1; do
  hba_rows="$(ne --raw --apply 'c: c.services.postgresql.authentication' "path:.#nixosConfigurations.${host}.config")" ||
    fail "${host}: pg_hba rows do not evaluate"
  python3 - "$host" "$hba_rows" <<'PYEOF' || fail "${host}: pg_hba rows drifted (see message above)"
import sys
host = sys.argv[1]
rows = [r.strip() for r in sys.argv[2].splitlines() if r.strip() and not r.lstrip().startswith("#")]
errs = []
for row in rows:
    fields = row.split()
    if fields[0] != "host":
        continue
    if len(fields) != 5:
        errs.append(f"{row!r} must be: host <db> <role> <cidr> <method>")
    elif "/" not in fields[3] and fields[3] not in ("all", "samehost", "samenet"):
        errs.append(f"{row!r} needs a masked address (postgres rejects a maskless one)")
langfuse_rows = [r for r in rows if "langfuse" in r]
if host == "home-forge":
    if "host langfuse langfuse 10.255.0.1/32 scram-sha-256" not in langfuse_rows:
        errs.append("langfuse must accept the service address (host-netns containers arrive as 10.255.0.1)")
    if any(r.endswith(" md5") or r.endswith(" trust") for r in langfuse_rows):
        errs.append(f"langfuse rows must use scram-sha-256: {langfuse_rows!r}")
# Every role's allow rows must precede its catch-all reject (first match wins).
reject_at = {}
for i, row in enumerate(rows):
    f = row.split()
    if len(f) == 5 and f[:2] == ["host", "all"] and f[4] == "reject":
        reject_at.setdefault(f[3], i)
for i, row in enumerate(rows):
    f = row.split()
    if len(f) == 5 and f[0] == "host" and f[1] != "all" and f[3] in reject_at and i > reject_at[f[3]]:
        errs.append(f"{row!r} lands after the catch-all reject for role {f[3]!r} and can never match")
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
done
# The evaluated Postgres probes below exercise consumer database contracts.
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

# Host-registry validity and materialization are verified by evaluated outputs below.

# --- 4. Preserved flake output contracts (DS-6) ------------------------------

for out in bootstrap checks deploy deployHosts devShells formatter nixosConfigurations packages; do
  ne --apply '_: true' "path:.#${out}" >/dev/null || fail "flake output .${out} missing"
done

# The deploy surface is reachable from the standard checks output (FB-4): each
# host's activatable profile is a check on the system that builds it, and both
# outputs resolve the same derivation, so CI needs no bespoke aggregate.
# Both paths are read from ONE flake instance. A path reference copies the tree
# per evaluation and the published provenance embeds `self.outPath`, so two
# evaluations of a tree whose `.git` moved in between produce different — but
# equivalent — derivations, and comparing across them fails for the wrong
# reason.
for pair in "x86_64-linux la-admin-1" "x86_64-linux home-forge" "aarch64-linux oci-melb-1"; do
  # shellcheck disable=SC2086
  set -- $pair
  drvs="$(ne --impure --raw --expr "let f = builtins.getFlake (toString $ROOT); in f.checks.$1.host-$2.drvPath + \" \" + f.packages.$1.host-$2.drvPath")" ||
    fail "checks.$1.host-$2 or packages.$1.host-$2 is missing"
  check_drv="${drvs%% *}"
  package_drv="${drvs##* }"
  [ "$check_drv" = "$package_drv" ] ||
    fail "checks.$1.host-$2 ($check_drv) and packages.$1.host-$2 ($package_drv) must be the same profile"
  case "$check_drv" in
    *activatable-nixos-system-"$2"-*) ;;
    *) fail "checks.$1.host-$2 is not the activatable profile: $check_drv" ;;
  esac
done

# Deploy node keys match the registry; physical edge/order metadata unchanged.
deploy_keys="$(ne --raw --apply 'n: builtins.toJSON (builtins.sort builtins.lessThan (builtins.attrNames n))' 'path:.#deploy.nodes')"
[ "$deploy_keys" = "$registry_keys" ] || fail "deploy node keys $deploy_keys != registry keys $registry_keys"
# The edge-host fact and the policy's host key name the same thing (the ingress
# host), so they must agree: exactly one policy host key, equal to edgeHost.
edge_host="$(ne --raw 'path:.#deployHosts.edgeHost')"
policy_hosts="$(ne --raw --apply 'h: builtins.toJSON (builtins.attrNames h)' 'path:.#nixosConfigurations.oci-melb-1.config.repo.web.hosts')"
[ "$policy_hosts" = "[\"$edge_host\"]" ] ||
  fail "edgeHost $edge_host must be the single policy host key, got $policy_hosts"
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
edge_anchor = '  edgeHost = "oci-melb-1";'
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
# identities, enforced in modules/web/web-policy.nix against the declared
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
anchor = "  hosts = {\n    oci-melb-1 = {"
assert s.count(anchor) == 1, "hosts-table anchor drifted"
s = s.replace(
    anchor,
    "  hosts = {\n"
    "    ghost-host = {\n"
    "      defaults = { };\n"
    "      services = { };\n"
    "    };\n"
    "    oci-melb-1 = {",
    1,
)
open(p, "w").write(s)
PYEOF
set +e
web_bad_key="$(ne --raw "path:${D}#nixosConfigurations.oci-melb-1.config.repo.web.hosts.oci-melb-1.primaryDomain" 2>&1)"
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
anchor = '            provider = "home-forge";\n            port = 4533;'
assert s.count(anchor) == 1, "navidrome origin anchor drifted"
s = s.replace(anchor, f'            provider = "ghost-origin.{suffix}";\n            port = 4533;', 1)
open(p, "w").write(s)
PYEOF
set +e
web_bad_origin="$(ne --raw "path:${D}#nixosConfigurations.oci-melb-1.config.repo.web.hosts.oci-melb-1.primaryDomain" 2>&1)"
web_bad_origin_rc=$?
set -e
[ "$web_bad_origin_rc" -ne 0 ] || fail "3.2: an origin provider with no canonical identity must fail closed"
case "$web_bad_origin" in
  *"web-policy: origin provider 'ghost-origin.${web_suffix}' is not a declared canonical host ID"*) ;;
  *) fail "3.2: expected the named origin-provider error, got: $(printf '%s' "$web_bad_origin" | tail -n 3)" ;;
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

# Aspect composition and placement are verified through evaluated outputs below.

# 7c. Typed facts and their rendered values are verified by the per-host
# evaluated probe below.

# 7d. Per-host observable contract: typed facts, boot/`/build` rendering,
# the five aspect markers (selection is enablement), Tailscale MTU/auth-key
# ownership, the notify composition with the shared nix-fleet mechanism and its
# packages, and DJ selection enablement (S4-4: forge true; OCI/LA
# discovered-but-unselected false).
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
daemonUnit = (c.systemd.services or { }) ? "notify";
daemonPkg = (c.services.notify.package or {}).name or "";
dj = c.applications.dj.enable or false;
containers = builtins.length (builtins.attrNames (c.virtualisation.oci-containers.containers or { }));
containerLimits = builtins.all (n: c.systemd.services."podman-${n}".startLimitIntervalSec == 3600 && c.systemd.services."podman-${n}".startLimitBurst == 5) (builtins.attrNames (c.virtualisation.oci-containers.containers or { }));
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
if not got["daemonPkg"].startswith("notify-"):
    errs.append(f"daemonPkg: {got['daemonPkg']!r} not the shared notify package (daemon + CLI + handler)")
if not got["containerLimits"]:
    errs.append("container units must bound their restart loop (startLimitIntervalSec=300, startLimitBurst=5)")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

probe oci-melb-1 '{"bootLoader":"grub","buildTmpfsSize":"8G","systemdBoot":false,"grub":true,"efiRemovable":true,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":"1200","tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemonUnit":true,"dj":false,"containers":6,"containerLimits":true}'
probe la-admin-1 '{"bootLoader":"systemd-boot","buildTmpfsSize":"50%","systemdBoot":true,"grub":false,"efiRemovable":false,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":"1200","tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemonUnit":true,"dj":false,"containers":0,"containerLimits":true}'
probe home-forge '{"bootLoader":"systemd-boot","buildTmpfsSize":"50%","systemdBoot":true,"grub":false,"efiRemovable":false,"dev":true,"zsh":true,"networkd":true,"ts":true,"tsMtu":null,"tsAuthKeyFile":"/run/secrets/tailscale.auth_key","daemonUnit":true,"dj":true,"containers":17,"containerLimits":true}'

# 7d-2. Stage 5 web/identity observables (S5-4, S5-5, S5-8). web-policy is an
# all-host infrastructure-support selection: config.repo.web resolves on every
# host and the ntfy serverUrl default derives from the catalog endpoint (loopback
# where ntfy is served). kanidm-host-auth is selected on OCI/LA only: both expose
# the policy-derived provider URL, clients, hostAuth, and Kanidm URI; forge
# carries only the intrinsic contract the Grafana it runs reads (`or {}` keeps
# the probe total where an option is absent).
probe_web_identity() { # $1 host, $2 expected JSON (python dict literal)
  local host="$1" json
  json="$(ne --json --apply 'c: {
    webHosts = builtins.attrNames (c.repo.web.hosts or {});
    webCatalog = builtins.attrNames (c.repo.web.catalog or {});
    ntfyUrl = c.services.notify.ntfy.serverUrl or "";
    ntfyDefault = c.repo.web.catalog."ntfy-admin".endpoint.url or "";
    providerUrl = (c.services.identity.oidc.providerUrl or null);
    hostAuth = (c.services.identity.hostAuth.enable or false);
    kanidmUri = if (c.services.kanidm.client.enable or false) then (c.services.kanidm.client.settings.uri or null) else null;
    fronts = builtins.sort builtins.lessThan (builtins.filter (n: builtins.match "tailscale-serve-.*" n != null) (builtins.attrNames c.systemd.services));
    kanidmExposureMode = c.repo.web.originServices."kanidm-admin".exposureMode or null;
    catalogExposureModes = builtins.sort builtins.lessThan (
      builtins.attrNames (
        builtins.listToAttrs (
          builtins.map (s: { name = s.exposureMode; value = null; }) (builtins.attrValues c.repo.web.catalog)
        )
      )
    );
    kanidmUpstream = c.repo.web.currentHost.services."kanidm-admin".upstream or null;
    kanidmSni = c.repo.web.currentHost.services."kanidm-admin".upstreamTlsServerName or null;
    kanidmFrontLoopback = builtins.match ".*--https=8443 https\\+insecure://127\\.0\\.0\\.1:8443" (c.systemd.services."tailscale-serve-kanidm-admin".serviceConfig.ExecStart or "") != null;
    kanidmTlsChain = c.services.identity.kanidm.tlsChainFile or null;
    kanidmTlsGroups = c.services.identity.kanidm.tlsReaderGroups or [];
    kanidmAfterCaddy = builtins.elem "caddy.service" (c.systemd.services.kanidm.after or []);
  }' "path:.#nixosConfigurations.${host}.config")" ||
  fail "${host}: web/identity probe does not evaluate"
  python3 - "$host" "$2" "$json" <<'PYEOF' || fail "${host}: observable web/identity contract violated"
import json, sys
host, exp_raw, got_raw = sys.argv[1], sys.argv[2], sys.argv[3]
exp = json.loads(exp_raw)
got = json.loads(got_raw)
errs = []
for k, v in exp.items():
    if got.get(k) != v:
        errs.append(f"{k}: got {got.get(k)!r} want {v!r}")
# web-policy resolves on every host and the ntfy default is policy-derived.
# currentHost is policy data (only la-admin-1 is a web-services host today);
# the contract is that repo.web evaluates and the catalog resolves.
if not got["webHosts"] or not got["webCatalog"]:
    errs.append(f"repo.web did not resolve: {got['webHosts']!r}/{got['webCatalog']!r}")
if got["ntfyDefault"] == "":
    errs.append("repo.web.catalog.ntfy-admin.endpoint.url is empty")
# Every host derives its ntfy dial from the catalog endpoint.
if got["ntfyUrl"] != got["ntfyDefault"]:
    errs.append(f"ntfyUrl: {got['ntfyUrl']!r} != policy default {got['ntfyDefault']!r}")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

# Every host derives ntfy from the catalog endpoint (loopback where ntfy is
# served). The private
# origin transport is provider-side: the provider renders the front the edge
# dials, the edge only dials the canonical private name.
probe_web_identity oci-melb-1 '{"providerUrl":"https://id.shrublab.xyz","hostAuth":true,"kanidmUri":"https://id.shrublab.xyz","fronts":["tailscale-serve-cockpit","tailscale-serve-geopulse","tailscale-serve-homarr"],"kanidmExposureMode":null,"catalogExposureModes":["direct","tailscale-only","tailscale-serve","tailscale-upstream"],"kanidmUpstream":"https://la-admin-1.tail0fe19b.ts.net:8443","kanidmSni":null,"kanidmFrontLoopback":false,"kanidmTlsChain":null,"kanidmTlsGroups":[],"kanidmAfterCaddy":false}'
probe_web_identity la-admin-1 '{"providerUrl":"https://id.shrublab.xyz","hostAuth":true,"kanidmUri":"https://id.shrublab.xyz","ntfyUrl":"http://127.0.0.1:2586","fronts":["tailscale-serve-kanidm-admin"],"kanidmExposureMode":"tailscale-serve","catalogExposureModes":["direct","tailscale-only","tailscale-serve","tailscale-upstream"],"kanidmUpstream":null,"kanidmSni":null,"kanidmFrontLoopback":true,"kanidmTlsChain":"/srv/data/kanidm/tls/fullchain.pem","kanidmTlsGroups":[],"kanidmAfterCaddy":false}'
probe_web_identity home-forge '{"providerUrl":"https://id.shrublab.xyz","hostAuth":false,"kanidmUri":null,"fronts":[],"kanidmExposureMode":null,"catalogExposureModes":["direct","tailscale-only","tailscale-serve","tailscale-upstream"],"kanidmUpstream":null,"kanidmSni":null,"kanidmFrontLoopback":false,"kanidmTlsChain":null,"kanidmTlsGroups":[],"kanidmAfterCaddy":false}'
# Forge carries only the intrinsic OIDC contract, because the Grafana it runs
# reads the derived endpoints; identity machinery itself — provider, host-auth,
# client — stays absent, not merely disabled.
forge_identity="$(ne --raw --apply 'c: builtins.toJSON (builtins.attrNames (c.services.identity or {}))' 'path:.#nixosConfigurations.home-forge.config')" ||
  fail "home-forge: identity absence probe does not evaluate"
[ "$forge_identity" = '["oidc"]' ] || fail "home-forge must carry only the intrinsic OIDC contract (services.identity namespaces: $forge_identity)"
forge_identity_machinery="$(ne --raw --apply 'c: builtins.toJSON { hostAuth = c.services.identity ? hostAuth; kanidm = c.services.identity ? kanidm; }' 'path:.#nixosConfigurations.home-forge.config')" ||
  fail "home-forge: identity machinery probe does not evaluate"
[ "$forge_identity_machinery" = '{"hostAuth":false,"kanidm":false}' ] || fail "home-forge must not carry identity machinery: $forge_identity_machinery"

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

test ! -d pkgs/notification-daemon || fail "the notification daemon implementation belongs to nix-fleet, not pkgs/"
test ! -d pkgs/notify || fail "the notify CLI implementation belongs to nix-fleet, not pkgs/"
# The retired option namespace must not reappear in a host assembly (the
# secret *file* keeps its historical name until the operator re-encrypts it).

# 7g. Operational behavior and capability boundaries are verified through the
# evaluated host probes and subset-isolation cases below.
for leaf in \
  modules/backups/state-backups.nix \
  modules/backups/state-backups/_consumer.nix \
  modules/flake/builder-access.nix \
  modules/flake/build-account.nix \
  modules/flake/observability-agent.nix; do
  test -f "$leaf" || fail "operational leaf $leaf missing"
done
# Identity isolation and intrinsic-contract behavior are covered by evaluated mutations below.

# 7h. Stage 3 observable contract (OPS-1..OPS-8): derived bucket and secret
# path, selection-is-enablement for backups/publication/client/Beszel, OCI
# token ownership and loopback endpoint, fleet-registry builder trust, Beszel
# KEY-only enrollment scopes.
probe_ops() { # $1 host, $2 expected JSON (python dict literal)
  local host="$1" json
  json="$(ne --json --apply 'c: {
    bucket = c.services.state-backups.bucket or "";
    secretFile = c.services.state-backups.secretFile or "";
    sbEnable = c.services.state-backups.enable or false;
    clientEnable = c.services.niks3-auto-upload.enable or false;
    serverUrl = c.services.niks3-auto-upload.serverUrl or "";
    tokenOwner = (c.sops.secrets.niks3_api_token.owner or null);
    niks3Srv = c.services.niks3.enable or false;
    beszelAgent = c.services.beszel.agent.enable or false;
    beszelKey = (c.services.beszel.agent.environment.KEY or "");
    beszelEnvFile = (c.services.beszel.agent.environmentFile or null);
    beszelKeySops = !(c.sops.secrets ? beszel_agent_key);
    beszelTokenAbsent = !(c.sops.secrets ? beszel_agent_token);
    onFailure = (c.systemd.services."restic-backups-state".onFailure or []);
    buildMachines = builtins.length (c.nix.buildMachines or [ ]);
    stagingRoot = c.services.state-backups.stagingRoot or "";
    hostCorePaths = (c.services.state-backups.services.host-core.paths or []);
    docsMcpCmd = (c.virtualisation.oci-containers.containers.docs-mcp.cmd or []);
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
if not got["beszelKey"].startswith("ssh-ed25519 "):
    errs.append(f"beszelKey: {got['beszelKey']!r} is not the hub's public key")
if got["beszelEnvFile"] is not None:
    errs.append(f"beszelEnvFile: {got['beszelEnvFile']!r}; the agent holds no secret file")
if not got["beszelKeySops"]:
    errs.append("beszel_agent_key: beszel must register no sops secret")
if not any(c.endswith("restic-backups-state.service") for c in got["onFailure"]):
    errs.append(f"onFailure: missing the notify aspect handler for restic-backups-state ({got['onFailure']!r})")
if got["buildMachines"] != 0:
    errs.append(f"buildMachines: {got['buildMachines']!r} entries; scheduling must stay off (CI builds)")
if not got["beszelTokenAbsent"]:
    errs.append("beszel_agent_token: the retired per-host agent token must not be registered")
# Run-unified-mode (standalone `mcp` serves the protocol only): the dashboard and
# the MCP endpoint share one port, which is what makes the UI reachable at all.
if got["docsMcpCmd"] and got["docsMcpCmd"][0] != "server":
    errs.append(f"docs-mcp cmd: {got['docsMcpCmd']!r}; the container must run unified mode (`server`)")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

probe_ops oci-melb-1 '{"bucket":"shrublab-backup-oci-melb-1","sbEnable":true,"clientEnable":true,"serverUrl":"http://127.0.0.1:5751","tokenOwner":"niks3","niks3Srv":true,"beszelAgent":true,"beszelEnvFile":null,"beszelKeySops":true,"beszelTokenAbsent":true,"buildMachines":0,"stagingRoot":"/srv/data/state-backups","hostCorePaths":[]}'
probe_ops la-admin-1 "$(printf '{"bucket":"shrublab-backup-la-admin-1","sbEnable":true,"clientEnable":true,"serverUrl":"http://oci-melb-1.%s:5751","tokenOwner":null,"niks3Srv":false,"beszelAgent":true,"beszelEnvFile":null,"beszelKeySops":true,"beszelTokenAbsent":true,"buildMachines":0,"stagingRoot":"/srv/data/state-backups","hostCorePaths":[]}' "$web_suffix")"
probe_ops home-forge "$(printf '{"bucket":"shrublab-backup-home-forge","sbEnable":true,"clientEnable":true,"serverUrl":"http://oci-melb-1.%s:5751","tokenOwner":null,"niks3Srv":false,"beszelAgent":true,"beszelEnvFile":null,"beszelKeySops":true,"beszelTokenAbsent":true,"buildMachines":0,"stagingRoot":"/srv/data/state-backups","hostCorePaths":["/etc/ssh"]}' "$web_suffix")"

# The canonical inventory's host keys are the trust half of the builder
# contract; pin one end to end rather than trusting the entry names alone.
registry_key="$(ne --raw --apply 'c: c.programs.ssh.knownHosts."host-oci-melb-1".publicKey' path:.#nixosConfigurations.oci-melb-1.config 2>/dev/null)"
case "$registry_key" in
  'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC8NW1V+x+tvbwzPMEcGRlK2V1XXAuDgdJ2dUQssiWaC root@oci-melb-1') ;;
  *) fail "fleet inventory: host-oci-melb-1 known-hosts entry is '${registry_key}'" ;;
esac
for host in home-forge la-admin-1 oci-melb-1; do
  host_key="$(ne --raw --apply "c: c.programs.ssh.knownHosts.\"host-${host}\".publicKey" path:.#nixosConfigurations.oci-melb-1.config 2>/dev/null)"
  case "$host_key" in
    'ssh-ed25519 '*) ;;
    *) fail "fleet inventory: host-${host} known-hosts entry is '${host_key}'" ;;
  esac
done

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

expect_eval_fail_any() { # $1 copy, $2 host, $3... expected message substrings (any match)
  local d="$1" host="$2" wanted out rc
  shift 2
  set +e
  out="$(nix eval --no-write-lock-file --raw "path:${d}#nixosConfigurations.${host}.config.system.build.toplevel.drvPath" 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "mutation ${host}: expected eval failure, got success"
  for wanted in "$@"; do
    case "$out" in
      *"$wanted"*) return 0 ;;
    esac
  done
  fail "mutation ${host}: expected a message containing one of '$*', got: $(printf '%s' "$out" | tail -3)"
}

# A CREATEDB consumer without declared satellite databases must fail closed
# with the registration-specific assertion, not merely fail evaluation.
D="$(make_copy)"
python3 - "$D/modules/observability/latitude.nix" <<'PYEOF'
import sys
path = sys.argv[1]
source = open(path).read()
start = source.index("extraDatabases = [")
end = source.index("];", start) + 2
open(path, "w").write(source[:start] + "extraDatabases = [ ];" + source[end:])
PYEOF
expect_eval_fail "$D" home-forge "services.postgres.consumers.latitude: setupSQL grants CREATEDB but extraDatabases is empty"

# Latitude's evaluated access rules must admit its Temporal databases before
# the role's catch-all reject; otherwise auto-setup cannot connect to them.
satellite_hba="$(ne --raw --apply 'c: c.services.postgresql.authentication' 'path:.#nixosConfigurations.home-forge.config')" ||
  fail "Latitude satellite-database pg_hba rules do not evaluate"
python3 - "$satellite_hba" <<'PYEOF' || fail "Latitude satellite-database access must precede its catch-all reject"
import sys
rows = [line.split() for line in sys.argv[1].splitlines() if line.strip() and not line.lstrip().startswith("#")]
for database in ("temporal", "temporal_visibility"):
    allowed = [i for i, row in enumerate(rows) if len(row) == 5 and row[0] == "host" and row[1] == database and row[2] == "latitude"]
    rejected = [i for i, row in enumerate(rows) if len(row) == 5 and row[:3] == ["host", "all", "latitude"] and row[4] == "reject"]
    if not allowed:
        raise SystemExit(f"no pg_hba allow rule for latitude database {database!r}")
    if not rejected or min(allowed) >= min(rejected):
        raise SystemExit(f"latitude database {database!r} is not admitted before the catch-all reject")
PYEOF

# 7i-1. Backups without the notify aspect fails closed (OPS-4). The whole
# notification mechanism — the daemon's option surface and the
# services.notify.events registration contract — is declared by the shared
# nix-fleet notify aspect the notify foundation aspect consumes,
# so dropping that selection cannot silently lose restic failure notifications:
# the composition fails on the missing contract. Both surfaces are accepted as
# the reported one because module traversal order is not a contract.
D="$(make_copy)"
sed -i '/aspects\.notify/d' "$D/modules/hosts/oci-melb-1/default.nix"
expect_eval_fail_any "$D" oci-melb-1 "services.notify"

# 7i-2. A derived bucket outside the S3 rule fails with the named assertion
# (OPS-11). nixpkgs itself rejects a trailing-hyphen hostName at the type
# level, so the tamper forces the trailing hyphen into the derived bucket. The
# bucket expression lives in the state-backups contributor.
D="$(make_copy)"
python3 - "$D/modules/backups/state-backups.nix" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = 'bucketName = "shrublab-backup-${config.networking.hostName}";'
new = 'bucketName = "shrublab-backup-${config.networking.hostName}-";'
assert old in s
open(p, "w").write(s.replace(old, new))
PY
expect_eval_fail "$D" oci-melb-1 "must be a valid S3 bucket name"

# 7i-3. Missing conventional host secret disables backups/publication without
# failing the base activation (OPS-3 two-step bootstrap). Beszel is unaffected:
# the agent holds no secret, so it stays enabled either way.
D="$(make_copy)"
mv "$D/secrets/hosts/home-forge/system.yaml" "$D/secrets/hosts/home-forge/system.yaml.moved"
json="$(ne --json --apply 'c: {
  sb = c.services.state-backups.enable or false;
  client = c.services.niks3-auto-upload.enable or false;
  beszelAgent = (c.services.beszel-agent or { }) != { };
  agent = c.services.beszel.agent.enable or false;
}' "path:${D}#nixosConfigurations.home-forge.config")" ||
fail "home-forge without host secrets must still evaluate (two-step bootstrap)"
python3 - "$json" <<'PY' || fail "home-forge without host secrets must disable backups/publication/Beszel: $json"
import json, sys
got = json.loads(sys.argv[1])
want = {"sb": False, "client": False, "beszelAgent": True, "agent": True}
if got != want:
    raise SystemExit(f"got {got!r} want {want!r}")
PY

# 7i-4. Backup-split subset isolation (split-state-backups-cache-publication
# 3.3a): selecting one of the split aspects alone must introduce only its own
# units. Each leg takes a FRESH make_copy (7i-3's copy legitimately tests the
# absent-secret gate and must not be reused). The composition imports the
# copy's contributor module plus the notify provider module over a minimal
# nixosSystem, so an unimported leaf's options are hard absences, and the
# state-backups contributor's registration contract is declared by the imported
# notify leaf. The home-forge fixture hostname keeps the conventional host
# secret present so the gated enables are true.
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
          # The publication aspect resolves its write endpoint from the
          # cross-host service catalog, so the catalog is part of its
          # composition — as it is on every host that selects the aspect.
          repo.modules.nixos.web-policy
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
      uploadUnitPresent = (c.systemd.services or { }) ? "niks3-auto-upload";
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
        "clientEnable": True, "clientOptionAbsent": False,
        "uploadUnitPresent": True}
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
        "clientOptionAbsent": True, "uploadUnitPresent": False}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in want.items() if got.get(k) != v]
if errs:
    raise SystemExit("; ".join(errs))
PY

# 7i-5. Declaration-surface independence: a feature that registers into
# `services.state-backups.services` must evaluate on a host that does not
# select the state-backups aspect. Only the declaration fragment is imported,
# so the registry exists without the mechanism (and the aspect's capture
# renderer stays absent).
fragment_probe() { # $1 copy root -> eval report JSON
  local d="$1" t out
  t="$(mktemp -d /tmp/scaffold-fragment.XXXXXX)"
  cat >"$t/flake.nix" <<EOF2
{
  inputs.repo.url = "path:$d";
  outputs = { self, repo }: {
    report = let
      sys = repo.inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          (import "$d/modules/backups/state-backups/_consumer.nix")
          {
            services.state-backups.services.probe = {
              mode = "live";
              paths = [ "/tmp/probe" ];
            };
            networking.hostName = "probe-host";
            system.stateVersion = "25.11";
          }
        ];
      };
      c = sys.config;
    in {
      registered = (c.services.state-backups.services or { }) ? probe;
      mode = c.services.state-backups.services.probe.mode or "";
      captureEnable = c.services.state-backups.enable or false;
      resticAbsent = !((c.services.restic.backups or { }) != { });
    };
  };
}
EOF2
  out="$(nix eval --raw --impure --no-write-lock-file --expr "builtins.toJSON ((builtins.getFlake (toString $t)).report)")"
  rm -rf "$t"
  printf '%s' "$out"
}

D="$(make_copy)"
json="$(fragment_probe "$D")" ||
  fail "7i-5: the declaration surface must evaluate without the state-backups aspect"
python3 - "$json" <<'PY' || fail "7i-5: declaration-surface observables violated: $json"
import json, sys
got = json.loads(sys.argv[1])
want = {"registered": True, "mode": "live", "captureEnable": False, "resticAbsent": True}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in want.items() if got.get(k) != v]
if errs:
    raise SystemExit("; ".join(errs))
PY


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

# 7l. Stage 5 semantic negative mutations (S5-6, S5-7). Each runs against a
# throwaway copy so the working tree is never modified, and each fails for its
# intended semantic reason rather than a generic parse/eval error. Identity
# contributor deletion is detected twice over: the capability owns its aspect
# name, so removing it leaves the host's selection unresolvable (7l-7), while
# the intrinsic contract is a private module no aspect carries, so its
# presence is what a consumer depends on (7l-6).

# 7l-1. A surviving evacuated root must be rejected even when the filter no
# longer lists it (a fake shrink that untracks the directory instead of
# deleting it). The shared root-evacuation predicate must name the survivor.
D="$(make_copy)"
mkdir -p "$D/modules/storage"
touch "$D/modules/storage/disko-root.nix"
[ "$(surviving_evacuated_roots "$D")" = "modules/storage" ] ||
  fail "7l-1: root-evacuation predicate must detect a surviving modules/storage"

# 7l-2. The boundary list is gone: a transitional-root name reappearing under
# modules/ is caught by the root-evacuation predicate (7l-1), not by a list.

# 7l-5. Identity must not activate on forge. Adding aspects.kanidm-host-auth to
# the forge record is detected through the missing-services.identity observable,
# not a publication diff.
D="$(make_copy)"
sed -i '/aspects\.dj/i\        aspects.kanidm-host-auth' "$D"/modules/hosts/*/default.nix
forge_identity_mut="$(ne --raw --apply 'c: builtins.toJSON (builtins.attrNames (c.services.identity or {}))' \
  "path:${D}#nixosConfigurations.home-forge.config")" ||
  fail "7l-5: forge identity mutation probe must evaluate"
[ "$forge_identity_mut" != '[]' ] ||
  fail "7l-5: forge must expose identity activation when kanidm-host-auth is wrongly selected"

# 7l-6. The intrinsic contract replaces the retired selection: a composition
# whose only identity participants are importing consumers still evaluates and
# resolves the canonical client records, and a consumer whose client is absent
# from policy fails through its own named assertion rather than a missing-option
# namespace. The host's `identity.hostAuth` assignment goes with the deselected
# capability because the capability declares that namespace (select-then-
# configure coupling, not a contract dependency). The host's providerUrl write
# stays: the contract's web-policy default only resolves on hosts declared in
# policy/web-services.nix, so this leg proves consumer independence given that
# write rather than the policy-default path on a consumer host.
D="$(make_copy)"
python3 - "$D" <<'PYEOF' > /dev/null || fail "7l-6 consumer-only mutation script failed"
import sys

d = sys.argv[1]

p = d + "/modules/hosts/oci-melb-1/default.nix"
s = open(p).read()
assert s.count("        aspects.kanidm-host-auth\n") == 1, "kanidm-host-auth selection anchor drifted"
open(p, "w").write(s.replace("        aspects.kanidm-host-auth\n", "", 1))

p = d + "/modules/hosts/oci-melb-1/_nixos.nix"
s = open(p).read()
block = """    identity.hostAuth = {
      enable = true;
      sshIntegration = true;
      pamAllowedLoginGroups = [ "admins" ];
    };
"""
assert s.count(block) == 1, "identity.hostAuth consumer block drifted"
open(p, "w").write(s.replace(block, "", 1))
PYEOF
consumer_json="$(ne --raw --apply 'c: builtins.toJSON {
  providerUrl = c.services.identity.oidc.providerUrl;
  identityNamespaces = builtins.attrNames c.services.identity;
  paperlessClientId = c.services.paperless.oidc.clientId;
  paperlessWellknownAligned = c.services.paperless.oidc.wellknownUrl == "${c.services.identity.oidc.providerUrl}/oauth2/openid/paperless/.well-known/openid-configuration";
  karakeepClientId = c.services.karakeep-pod.oidc.clientId;
  kanidmUnixEnable = c.services.kanidm.unix.enable or false;
}' "path:${D}#nixosConfigurations.oci-melb-1.config")" ||
  fail "7l-6: consumer-only composition (OCI without the host-auth capability) does not evaluate"
python3 - "$consumer_json" <<'PYEOF' || fail "7l-6: consumer-only composition must resolve the canonical client records"
import json, sys
got = json.loads(sys.argv[1])
expected = {
    "providerUrl": "https://id.shrublab.xyz",
    "identityNamespaces": ["oidc"],
    "paperlessClientId": "paperless",
    "paperlessWellknownAligned": True,
    "karakeepClientId": "karakeep",
    "kanidmUnixEnable": False,
}
errs = [f"{k}: got {got.get(k)!r} want {v!r}" for k, v in expected.items() if got.get(k) != v]
if errs:
    print("; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
# 7l-6b. Same composition, with the client disabled in canonical policy: OIDC
# stays enabled through web policy, the contract stops carrying the client, and
# the consumer must fail through its named assertion.
python3 - "$D" <<'PYEOF' > /dev/null || fail "7l-6b policy mutation script failed"
import json, sys

p = sys.argv[1] + "/policy/identity.json"
d = json.load(open(p))
assert d["systems"]["oauth2"]["paperless"]["enable"] is True, "paperless policy anchor drifted"
d["systems"]["oauth2"]["paperless"]["enable"] = False
json.dump(d, open(p, "w"), indent=2)
PYEOF
set +e
assertion_out="$(nix eval --no-write-lock-file --raw \
  "path:${D}#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath" 2>&1)"
assertion_rc=$?
set -e
[ "$assertion_rc" -ne 0 ] || fail "7l-6b: a missing canonical client must fail the consumer's assertions"
case "$assertion_out" in
  *"canonical OIDC client 'paperless' is missing"*) ;;
  *) fail "7l-6b: expected the Paperless named assertion, got: $(printf '%s' "$assertion_out" | tail -3)" ;;
esac

# The host-auth capability's fail-closed by-name selection rejection is
# exercised by the evaluated materialization below.
D="$(make_copy)"
rm "$D/modules/identity/kanidm-host-auth.nix"
set +e
hostauth_out="$(nix eval --no-write-lock-file --raw \
  "path:${D}#nixosConfigurations.oci-melb-1.config.system.build.toplevel.drvPath" 2>&1)"
hostauth_rc=$?
set -e
[ "$hostauth_rc" -ne 0 ] || fail "7l-7: deleting the host-auth contributor must break OCI Kanidm eval"
case "$hostauth_out" in
  *"attribute 'kanidm-host-auth' missing"*) ;;
  *) fail "7l-7: expected the unresolvable kanidm-host-auth selection, got: $(printf '%s' "$hostauth_out" | tail -3)" ;;
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
# assertion. Evaluated probes below verify enabled and isolated behavior.

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
j = s.index("aspects.kanidm-host-auth", i)
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
# The evaluator-class roots are deleted, not renamed (S7-4/S7-5/S7-8).
[ -z "$(surviving_evacuated_roots "$ROOT")" ] ||
  fail "7n: converted application/provider roots must be deleted: $(surviving_evacuated_roots "$ROOT")"
test ! -e modules/flake/_applications || fail "7n: no underscore-renamed applications root may exist"
test ! -e modules/flake/_providers || fail "7n: no underscore-renamed providers root may exist"

# Host-private filesystem artifacts are checked below; workload placement is evaluated.
for f in \
  modules/hosts/oci-melb-1/_disko-single-disk-split.nix \
  modules/hosts/oci-melb-1/facter.json \
  modules/hosts/home-forge/_disko-two-disk.nix; do
  test -e "$f" || fail "7n-1: host-local fragment $f must be retained"
done

# Discovery and selection isolation: force module assertions and inspect the
# synthetic registration contributed by the selected fixture aspect.
PLACEMENT_PROBE='c: {
  drv = c.system.build.toplevel.drvPath;
  monitorUnits = builtins.attrNames (c.services.notify.events or { });
}'

# ClickHouse package selection is checked through the evaluated host outputs.
probe_placement() { # $1 repo root, $2 host -> JSON
  nix eval --json --no-write-lock-file --apply "$PLACEMENT_PROBE" "path:${1}#nixosConfigurations.${2}.config"
}

# 7n-3. Evaluated placement mutations use throwaway repository copies.

# 7n-3e. Discovery alone is inert: a freshly published, unselected aspect does
# not activate anything, and selecting it is the only activation edge.
D="$(make_copy)"
cat >"$D/modules/flake/tamper-aspect.nix" <<'EOF'
{ lib, withSystem, ... }:
{
  flake.modules.nixos.tamper-aspect =
    { pkgs, ... }:
    {
    # The unit is defined here so the fail-closed registration contract is
    # satisfied and only contribution visibility is under test (MON-1/MON-3).
    systemd.services.tamper-unit.serviceConfig.ExecStart = lib.getExe pkgs.coreutils;
    services.notify.events."tamper-unit".failure = { };
    };
}
EOF
json="$(probe_placement "$D" la-admin-1)" || fail "7n-3e: LA must still evaluate with an unselected publication"
python3 - "$json" <<'PYEOF' || fail "7n-3e: an unselected discovered aspect must not activate"
import json, sys
got = json.loads(sys.argv[1])
if "tamper-unit" in got["monitorUnits"]:
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
if "tamper-unit" not in got["monitorUnits"]:
    raise SystemExit(f"selection did not activate the aspect: {got['monitorUnits']!r}")
PYEOF
json="$(probe_placement "$D" oci-melb-1)" || fail "7n-3e: OCI must still evaluate with the tamper contributor present"
python3 - "$json" <<'PYEOF' || fail "7n-3e: a selection on one host must not activate another host"
import json, sys
got = json.loads(sys.argv[1])
if "tamper-unit" in got["monitorUnits"]:
    raise SystemExit(f"unselected host activated the aspect: {got['monitorUnits']!r}")
PYEOF

# --- Host observability -----------------
# The pin move adds two producers fleet-wide: the tailscale aspect publishes a
# `100.100.100.100:80` scrape source that every metrics-selected host realizes,
# and the node-exporter aspect contributes the systemd unit-state collector. The
# collector contribution is additive (mkAfter), which is the point: upstream
# first shipped it as mkDefault, so a consumer list *replaced* it instead of
# extending it, and their own gates passed while missing that composition case.
# These pins therefore read effective values rather than flags — the configured
# collector list, the rendered exporter unit (the systemd flag plus the AF_UNIX
# family the collector needs), the realized scrape job, and the identity labels
# that make the join back to the canonical host IDs hold.

HOST_OBS_PROBE='c: let
  exp = c.systemd.services.prometheus-node-exporter or { };
  exec = exp.serviceConfig.ExecStart or "";
  jobs = c.services.vmagent.prometheusConfig.scrape_configs or [ ];
  pick = n: let j = builtins.filter (x: (x.job_name or "") == n) jobs;
    in if j == [ ] then null else builtins.head j;
  ts = pick "tailscale";
in {
  collectors = c.services.prometheus.exporters.node.enabledCollectors or [ ];
  disabledCollectors = c.services.prometheus.exporters.node.disabledCollectors or [ ];
  families = exp.serviceConfig.RestrictAddressFamilies or [ ];
  systemdFlag = builtins.match ".*--collector[.]systemd.*" exec != null;
  dynamicUser = exp.serviceConfig.DynamicUser or null;
  exporterUser = exp.serviceConfig.User or null;
  scrapeTarget = (c.services.telemetry.scrape.tailscale or { }).target or "";
  scrapePort = (c.services.telemetry.scrape.tailscale or { }).port or 0;
  realizedJobs = map (j: j.job_name or "") jobs;
  realizedStatic = if ts == null then [ ] else (ts.static_configs or [ ]);
  identityHost = (c.services.telemetry.identity or { }).hostName or "";
  identityEnvironment = (c.services.telemetry.identity or { }).environment or null;
  journalHost = (c.services.telemetry.journald or { }).hostName or null;
  journalNormalize = (c.services.telemetry.journald or { }).normalizeTraceContext or null;
}'

probe_host_obs() { # $1 repo root, $2 host -> JSON
  nix eval --json --no-write-lock-file --apply "$HOST_OBS_PROBE" "path:${1}#nixosConfigurations.${2}.config"
}

assert_host_obs() { # $1 host, $2 probe JSON
  python3 - "$1" "$2" <<'PYEOF' || fail "7n-4: $1 host observability contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if got["collectors"] != ["systemd"]:
    errs.append(f"enabledCollectors must be exactly the systemd collector: {got['collectors']!r}")
if got["disabledCollectors"] != []:
    errs.append(f"no collector may be disabled by omission: {got['disabledCollectors']!r}")
if not got["systemdFlag"]:
    errs.append("the rendered exporter unit must carry --collector.systemd")
for fam in ("AF_UNIX", "AF_INET"):
    if fam not in got["families"]:
        errs.append(f"the exporter unit must allow {fam}: {got['families']!r}")
if got["dynamicUser"] is not False:
    errs.append(f"the exporter must not be a DynamicUser: {got['dynamicUser']!r}")
if got["exporterUser"] != "node-exporter":
    errs.append(f"exporter account drifted: {got['exporterUser']!r}")
if (got["scrapeTarget"], got["scrapePort"]) != ("100.100.100.100", 80):
    errs.append(f"tailscale scrape source drifted: {got['scrapeTarget']!r}:{got['scrapePort']!r}")
if "tailscale" not in got["realizedJobs"]:
    errs.append(f"the tailscale scrape job is not realized in vmagent: {got['realizedJobs']!r}")
statics = got["realizedStatic"]
if [s.get("targets") for s in statics] != [["100.100.100.100:80"]]:
    errs.append(f"realized tailscale targets drifted: {statics!r}")
elif [(s.get("labels") or {}).get("host") for s in statics] != [host]:
    errs.append(f"the scrape label must join to the canonical host id: {statics!r}")
if got["identityHost"] != host:
    errs.append(f"identity.hostName must be the canonical host id: {got['identityHost']!r}")
if got["identityEnvironment"] is not None:
    errs.append(f"environment must stay unset for a fleet with no environment concept: {got['identityEnvironment']!r}")
if got["journalHost"] is not None:
    errs.append(f"the journal host label must stay unset so identity supplies it: {got['journalHost']!r}")
if got["journalNormalize"] is not True:
    errs.append(f"journal trace correlation must default on: {got['journalNormalize']!r}")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF
}

for h in oci-melb-1 la-admin-1 home-forge; do
  json="$(probe_host_obs "$ROOT" "$h")" || fail "7n-4: $h host observability probe does not evaluate"
  assert_host_obs "$h" "$json"
done

# 7n-4b. The composition case upstream missed: a consumer that states its own
# collector list must still receive the collector the aspect contributes. An
# enumerating replace would lose the systemd collector and its AF_UNIX allowance
# silently, so the effective value is asserted on a throwaway copy rather than
# trusted to the contribution form.
D="$(make_copy)"
python3 - "$D/modules/hosts/home-forge/_nixos.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "  fleet.foundation = {\n"
assert s.count(anchor) == 1, "forge fragment anchor drifted"
s = s.replace(anchor, '  services.prometheus.exporters.node.enabledCollectors = [ "textfile" ];\n\n' + anchor, 1)
open(p, "w").write(s)
PYEOF
json="$(probe_host_obs "$D" home-forge)" ||
  fail "7n-4b: home-forge must still evaluate with a consumer collector list"
python3 - home-forge "$json" <<'PYEOF' || fail "7n-4b: an explicit consumer collector list must not replace the contributed collector"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
if sorted(got["collectors"]) != ["systemd", "textfile"]:
    print(f"{host}: consumer list replaced the contributed collector: {got['collectors']!r}", file=sys.stderr)
    sys.exit(1)
if not got["systemdFlag"]:
    print(f"{host}: the systemd flag disappeared with the consumer list", file=sys.stderr)
    sys.exit(1)
PYEOF

# --- 7o. Feature-owned notification registration contract (MON-1..MON-4) ---
# (openspec change feature-owned-service-monitoring tasks 2.1-2.3, 3.1, 3.2.)
# Registration is contributed by the capability that owns each unit; the contract
# itself — `services.notify.events.<unit>` plus the native OnFailure= /
# OnSuccess= handler — is declared by the shared nix-fleet notify
# aspect the notify foundation aspect consumes. The observable contract is
# therefore per host: the old local registry and every reverse index are gone,
# only real implementations are registered, the Beets units follow the music
# placement (home-forge yes, OCI no synthetic fragments), and owner-defined
# hooks survive the additive merge.

# Registered units must have an implementation and receive native handlers.
# Feature-owned lifecycle hooks must survive notification composition.
MONITOR_PROBE='c: let
  events = c.services.notify.events or { };
  svc = c.systemd.services or { };
  # A registration is real when the unit has an option-level implementation, or
  # when it is package-provided (systemd.packages ships the unit file) and the
  # registration says so — the rule the shared notify aspect validates.
  isReal = n: let s = svc.${n} or null; in
    (s != null && ((s.serviceConfig.ExecStart or null) != null || ((s.script or "") != "")))
    || (events.${n}.fromPackage or false);
  render = e:
    if builtins.isString e then e
    else if builtins.isPath e then builtins.toString e
    else builtins.toJSON e;
  cmds = v:
    if v == null then [ ]
    else if builtins.isList v then builtins.map render v
    else [ (render v) ];
  isBeets = n: builtins.match "beets-.*" n != null;
  names = builtins.attrNames events;
  beets = builtins.filter isBeets (builtins.attrNames svc);
in {
  drv = c.system.build.toplevel.drvPath;
  daemonUnit = svc ? "notify";
  handlerUnit = svc ? "notify-event@";
  unreal = builtins.filter (n: !(isReal n)) names;
  beetsAttrs = builtins.sort builtins.lessThan beets;
  beetsInboxPresent = svc ? "beets-inbox";
  hooks = builtins.listToAttrs (map (n: {
    name = n;
    value = {
      onFailure = cmds (svc.${n}.onFailure or null);
      onSuccess = cmds (svc.${n}.onSuccess or null);
      execStartPost = cmds (svc.${n}.serviceConfig.ExecStartPost or null);
      registered = {
        failure = events.${n}.failure != null;
        success = events.${n}.success != null;
      };
    };
  }) names);
}'

probe_monitor() { # $1 host -> JSON
  nix eval --json --no-write-lock-file --apply "$MONITOR_PROBE" "path:${ROOT}#nixosConfigurations.${1}.config"
}

monitor_json="$(probe_monitor oci-melb-1)" || fail "7o-2: oci-melb-1 monitor probe does not evaluate"
python3 - oci-melb-1 "$monitor_json" <<'PYEOF' || fail "7o-2: oci-melb-1 notification contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if not got["daemonUnit"]:
    errs.append("the notify unit must exist on a notify-selected host")
if not got["handlerUnit"]:
    errs.append("the notify-event@ handler template must exist when units are registered")
if got["unreal"]:
    errs.append(f"registered units without an implementation: {got['unreal']!r}")
if got["beetsAttrs"]:
    errs.append(f"OCI must evaluate no Beets service fragments: {got['beetsAttrs']!r}")
if got["beetsInboxPresent"]:
    errs.append("OCI must not define a beets-inbox unit")
for name, hooks in got["hooks"].items():
    if not hooks["registered"]["failure"]:
        errs.append(f"{name}: no failure registration")
    if hooks["registered"]["success"]:
        errs.append(f"{name}: unexpected success registration")
    if not any(c.endswith(f"notify-event@{name}.service") for c in hooks["onFailure"]):
        errs.append(f"{name}: native OnFailure handler missing ({hooks['onFailure']!r})")
    if hooks["onSuccess"]:
        errs.append(f"{name}: unexpected OnSuccess handler ({hooks['onSuccess']!r})")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

monitor_json="$(probe_monitor la-admin-1)" || fail "7o-2: la-admin-1 monitor probe does not evaluate"
python3 - la-admin-1 "$monitor_json" <<'PYEOF' || fail "7o-2: la-admin-1 notification contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if not got["daemonUnit"]:
    errs.append("the notify unit must exist on a notify-selected host")
if not got["handlerUnit"]:
    errs.append("the notify-event@ handler template must exist when units are registered")
if got["unreal"]:
    errs.append(f"registered units without an implementation: {got['unreal']!r}")
if got["beetsAttrs"]:
    errs.append(f"la-admin-1 must evaluate no Beets service fragments: {got['beetsAttrs']!r}")
for name, hooks in got["hooks"].items():
    if not hooks["registered"]["failure"]:
        errs.append(f"{name}: no failure registration")
    if not any(c.endswith(f"notify-event@{name}.service") for c in hooks["onFailure"]):
        errs.append(f"{name}: native OnFailure handler missing ({hooks['onFailure']!r})")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

monitor_json="$(probe_monitor home-forge)" || fail "7o-2: home-forge monitor probe does not evaluate"
python3 - home-forge "$monitor_json" <<'PYEOF' || fail "7o-2: home-forge Beets notification contract violated"
import json, sys
host, got = sys.argv[1], json.loads(sys.argv[2])
errs = []
if not got["daemonUnit"]:
    errs.append("the notify unit must exist on a notify-selected host")
if not got["handlerUnit"]:
    errs.append("the notify-event@ handler template must exist when units are registered")
if got["unreal"]:
    errs.append(f"registered units without an implementation: {got['unreal']!r}")
# The interactive quarantine review worker is not an automated runner and must
# stay unregistered (it keeps only its own failure hook).
hooks = got["hooks"]
for unit in ("beets-inbox", "beets-reconcile", "beets-duplicates"):
    h = hooks.get(unit)
    if h is None:
        errs.append(f"{unit}: no notification registration")
        continue
    if not h["registered"]["failure"]:
        errs.append(f"{unit}: no failure registration")
    if h["registered"]["success"]:
        errs.append(f"{unit}: unexpected success registration")
    if not any(c.endswith(f"notify-event@{unit}.service") for c in h["onFailure"]):
        errs.append(f"{unit}: native OnFailure handler missing ({h['onFailure']!r})")
# The long-running OmniRoute container reports a clean stop: the only unit with
# a success registration, and the only one carrying the native OnSuccess handler.
omni = hooks.get("podman-omniroute", {})
if not omni.get("registered", {}).get("success"):
    errs.append(f"podman-omniroute: success registration missing ({omni.get('registered')!r})")
if not any(c.endswith("notify-event@podman-omniroute.service") for c in omni.get("onSuccess", [])):
    errs.append(f"podman-omniroute: native OnSuccess handler missing ({omni.get('onSuccess')!r})")
for name, h in hooks.items():
    if name == "podman-omniroute":
        continue
    if h["registered"]["success"]:
        errs.append(f"{name}: unexpected success registration")
    if h["onSuccess"]:
        errs.append(f"{name}: unexpected OnSuccess handler ({h['onSuccess']!r})")
# Feature-owned Beets hooks (deployed baseline: OnFailure retry timer plus the
# failure notification template) survive the additive merge.
inbox = hooks.get("beets-inbox", {})
if "beets-inbox-retry.timer" not in inbox.get("onFailure", []):
    errs.append(f"beets-inbox: feature-owned retry timer lost ({inbox.get('onFailure')!r})")
if not any("beets-notify-failure" in c for c in inbox.get("onFailure", [])):
    errs.append(f"beets-inbox: feature-owned failure notification lost ({inbox.get('onFailure')!r})")
# Preprocess cleanup ExecStartPost is preserved now that the registration no
# longer injects lifecycle hooks of its own.
post = inbox.get("execStartPost", [])
if not any("rm -f" in c and "inbox-ready" in c for c in post):
    errs.append(f"beets-inbox: feature-owned preprocess cleanup lost ({post!r})")
if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
PYEOF

# 7o-3. Negative: a registration naming a unit with no implementation fails
# closed and names that unit.
D="$(make_copy)"
python3 - "$D/modules/oci/oci.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '        boot.kernelParams = [ "console=ttyAMA0,115200n8" ];\n'
assert anchor in s, "registration anchor drifted"
s = s.replace(anchor, '        services.notify.events."phantom-unit".failure = { };\n' + anchor, 1)
open(p, "w").write(s)
PYEOF
expect_eval_fail "$D" oci-melb-1 "events.phantom-unit is registered but has no systemd service implementation"

# 7o-4. Negative: the stale wrong-host Beets registration is rejected instead of
# silently materialising a handler. OCI owns no Beets unit, so a Beets
# registration there must fail closed (this is the deployed-baseline drift).
D="$(make_copy)"
python3 - "$D/modules/oci/oci.nix" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = '        boot.kernelParams = [ "console=ttyAMA0,115200n8" ];\n'
assert anchor in s, "registration anchor drifted"
s = s.replace(anchor, '        services.notify.events."beets-inbox".failure = { };\n' + anchor, 1)
open(p, "w").write(s)
PYEOF
expect_eval_fail "$D" oci-melb-1 "events.beets-inbox is registered but has no systemd service implementation"

# 7o-5. Negative: a phantom target contributed through a throwaway aspect is
# rejected too, so the fail-closed check is about the implementation and not
# about which file the registration came from.
D="$(make_copy)"
cat >"$D/modules/flake/tamper-monitor-aspect.nix" <<'EOF'
{ ... }:
{
  flake.modules.nixos.tamper-monitor-aspect = {
    services.notify.events."ghost-unit".failure = { };
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
expect_eval_fail "$D" oci-melb-1 "events.ghost-unit is registered but has no systemd service implementation"


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

echo "check-dendritic-scaffold-contract: PASS"
