#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-internal-contracts: $*" >&2
  exit 1
}
note() { echo "  - $*"; }

ne() { nix eval --impure --no-write-lock-file "$@"; }

# Throwaway repo copies for the negative mutation checks (stage 8 task 4.3).
# Same excludes as tests/check-dendritic-scaffold-contract.sh so a copy
# evaluates exactly like the checkout.
MUT_LIST="$(mktemp /tmp/internal-contracts-mut-list.XXXXXX)"
cleanup_muts() {
  xargs -r rm -rf <"$MUT_LIST"
  rm -f "$MUT_LIST"
}
trap cleanup_muts EXIT
make_copy() { # prints path to a fresh repo copy
  local d
  d="$(mktemp -d /tmp/internal-contracts-mut.XXXXXX)"
  printf '%s\n' "$d" >>"$MUT_LIST"
  tar -C "$ROOT" \
    --exclude=.git --exclude=.jj --exclude=./opentofu --exclude=./opentofu/* \
    --exclude=.hp-forge-esp-backup --exclude=.qmd --exclude=.direnv \
    --exclude=.cortexkit --exclude=.tmp --exclude=.ruff_cache \
    --exclude=.pi --exclude=.firecrawl --exclude=.opencode \
    -cf - . | tar -C "$d" -xf -
  printf '%s' "$d"
}

# --- 1. The contract surface is exactly the two demonstrated transports -------
#
# HIC-4 names two and only two cross-host transports: shared PostgreSQL and the
# private Niks3 write API. Identity (Kanidm) and ntfy deliberately stay
# web-catalog contracts (repo.web.catalog), so a third internal endpoint is
# drift, not an extension. This exact key set is what makes "accidental
# identity/ntfy duplication" fail loudly: adding a contract to
# modules/fleet/internal-contracts.nix declarations changes this set.
contracts="$(ne --raw --apply 'v: builtins.toJSON v' 'path:.#internalContracts')" ||
  fail "flake.internalContracts must evaluate"

python3 - "$contracts" <<'PYEOF'
import json
import sys

got = json.loads(sys.argv[1])
want = ["niks3Write", "postgres"]
errs = []
if sorted(got) != want:
    errs.append(
        f"flake.internalContracts must expose exactly {want} (HIC-4), got {sorted(got)}; "
        "a third transport (for example identity or ntfy) must not gain an internal contract"
    )

# A family contract resolves one endpoint per instance: `postgres` is keyed by
# instance name (modular-postgres-instances), while `niks3Write` is a single
# endpoint. Flatten both shapes to (label, endpoint) before checking fields.
flattened = {}
for name, value in sorted(got.items()):
    if "fqdn" in value:
        flattened[name] = value
        continue
    if not value:
        errs.append(
            f"{name}: a contract family must resolve at least one instance endpoint; "
            "an empty family would make every per-member assertion below vacuous"
        )
        continue
    for instance, endpoint in sorted(value.items()):
        flattened[f"{name}.{instance}"] = endpoint

for name, endpoint in sorted(flattened.items()):
    for field in ("provider", "port", "scheme", "host", "fqdn", "url"):
        if field not in endpoint:
            errs.append(f"{name}: missing resolved field {field!r}")
    if endpoint.get("host") != endpoint.get("provider"):
        errs.append(
            f"{name}: resolved host {endpoint.get('host')!r} must derive from the provider "
            f"record {endpoint.get('provider')!r}"
        )
    fqdn, host, scheme, port = (
        endpoint.get("fqdn"),
        endpoint.get("host"),
        endpoint.get("scheme"),
        endpoint.get("port"),
    )
    if not (isinstance(fqdn, str) and isinstance(host, str) and fqdn.startswith(f"{host}.")):
        errs.append(f"{name}: resolved fqdn {fqdn!r} must extend the provider host {host!r}")
    if endpoint.get("url") != f"{scheme}://{fqdn}:{port}":
        errs.append(f"{name}: resolved url {endpoint.get('url')!r} must compose scheme/host/port")
if errs:
    raise SystemExit("; ".join(errs))
PYEOF
note "surface: exactly postgres + niks3Write, each identity-derived (host/fqdn/url); postgres resolves per instance"

# --- 2. No second internal authority for identity or ntfy --------------------
#
# Every read of the repo.internal.<key> namespace in production modules must
# name one of the two contracts. A new `repo.internal.identity` or
# `repo.internal.ntfy` read anywhere under modules/ fails here, which is the
# "accidental duplication" side of HIC-4 (identity and ntfy stay web-catalog).
python3 - <<'PYEOF' || fail "repo.internal namespace drifted (see message above)"
import os
import re
import sys

allowed = {"postgres", "niks3Write"}
pattern = re.compile(r"repo\.internal\.([A-Za-z0-9_-]+)")
offenders = []
for base, _dirs, files in os.walk("modules"):
    for name in files:
        if not name.endswith(".nix"):
            continue
        path = os.path.join(base, name)
        for lineno, line in enumerate(open(path, encoding="utf-8"), start=1):
            for key in pattern.findall(line):
                if key not in allowed:
                    offenders.append(f"{path}:{lineno}: repo.internal.{key}")
if offenders:
    print(
        "repo.internal must only carry the HIC-4 contracts "
        f"{sorted(allowed)}; found: {'; '.join(offenders)}",
        file=sys.stderr,
    )
    sys.exit(1)
PYEOF
note "namespace: repo.internal.* reads in modules/ are limited to postgres + niks3Write"

# --- 3. identity and ntfy keep their web-catalog authority -------------------
#
# The other half of the same boundary: the catalog remains the authority for
# the identity provider and ntfy endpoints, so removing them from it (for
# example while migrating them to an internal contract) fails here.
nix eval --impure --no-write-lock-file --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    policy = import ./policy/web-services.nix;
    policyLib = import ./lib/policy.nix { inherit lib; };
    catalog = policyLib.serviceCatalog policy;
  in
  assert catalog ? "kanidm-admin";
  assert catalog ? "ntfy-admin";
  assert catalog."kanidm-admin".publicUrl == "https://id.shrublab.xyz";
  true
' >/dev/null || fail "identity (kanidm-admin) and ntfy-admin must stay web-catalog contracts"
note "authority: kanidm-admin + ntfy-admin still resolve from the web catalog"

# --- 4. Stale placement: the provider stops enabling the capability ----------
#
# The strongest stale-placement model: oci-melb-1 keeps selecting/carrying the
# postgres aspect wiring but stops enabling the substrate the contract
# requires, so the contract must fail with the named capability error rather
# than serve a dead endpoint.
D="$(make_copy)"
python3 - "$D/modules/database/postgres.nix" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
anchor = "services.postgres.enable = true;"
assert s.count(anchor) == 1, "postgres capability anchor drifted"
s = s.replace(anchor, "services.postgres.enable = false;", 1)
open(p, "w").write(s)
PYEOF
set +e
stale_out="$(ne --raw "path:${D}#internalContracts" 2>&1)"
stale_rc=$?
set -e
[ "$stale_rc" -ne 0 ] || fail "4.3: a provider that stops enabling its capability must fail closed"
case "$stale_out" in
*"internal-contracts: provider host 'oci-melb-1' does not enable 'services.postgres.enable' required by contract 'postgres'; the provider host must select the aspect that enables it"*) ;;
*) fail "4.3: expected the named provider-capability error, got: $(printf '%s' "$stale_out" | tail -n 3)" ;;
esac
note "stale placement: $(printf '%s' "$stale_out" | grep -m1 -o 'internal-contracts: .*' | cut -c1-170)"

# --- 5. Unknown host reference in a contract ---------------------------------
#
# 3.1 covers unknown references in deploy metadata and 3.2 covers them in web
# routing; the internal contracts need their own guard because they resolve a
# provider host ID directly.
D="$(make_copy)"
python3 - "$D/modules/fleet/internal-contracts.nix" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
anchor = '    postgres = {\n      provider = "oci-melb-1";'
assert s.count(anchor) == 1, "postgres provider anchor drifted"
s = s.replace(anchor, '    postgres = {\n      provider = "ghost-provider";', 1)
open(p, "w").write(s)
PYEOF
set +e
ghost_out="$(ne --raw "path:${D}#internalContracts" 2>&1)"
ghost_rc=$?
set -e
[ "$ghost_rc" -ne 0 ] || fail "4.3: an undeclared provider host ID must fail closed"
case "$ghost_out" in
*"internal-contracts: contract 'postgres' names unknown provider 'ghost-provider', which is not a declared canonical host ID"*) ;;
*) fail "4.3: expected the named unknown-provider error, got: $(printf '%s' "$ghost_out" | tail -n 3)" ;;
esac
note "unknown reference: $(printf '%s' "$ghost_out" | grep -m1 -o 'internal-contracts: .*' | cut -c1-170)"

# --- 6. A third contract cannot join silently --------------------------------
#
# Duplication cannot arrive by adding a working identity/ntfy contract either:
# the declaration shape is validated for every entry, so an injected
# identity declaration is resolved and rejected through the same named errors
# (and check 1 fails the exact key set if one is ever added deliberately).
D="$(make_copy)"
python3 - "$D/modules/fleet/internal-contracts.nix" <<'PYEOF'
import sys

p = sys.argv[1]
s = open(p).read()
anchor = "  declarations = {\n    postgres = {"
assert s.count(anchor) == 1, "declarations anchor drifted"
injected = (
    "  declarations = {\n"
    "    identity = {\n"
    '      provider = "ghost-identity-provider";\n'
    "      port = 443;\n"
    '      scheme = "https";\n'
    "      capabilityPath = [\n"
    '        "services"\n'
    '        "kanidm"\n'
    '        "enable"\n'
    "      ];\n"
    "      listen = {\n"
    "        path = [\n"
    '          "services"\n'
    '          "kanidm"\n'
    '          "settings"\n'
    '          "port"\n'
    "        ];\n"
    '        kind = "port";\n'
    "      };\n"
    "    };\n"
    "    postgres = {"
)
s = s.replace(anchor, injected, 1)
open(p, "w").write(s)
PYEOF
set +e
dup_out="$(ne --raw "path:${D}#internalContracts" 2>&1)"
dup_rc=$?
set -e
[ "$dup_rc" -ne 0 ] || fail "4.3: an injected third (identity) contract must not pass validation"
case "$dup_out" in
*"internal-contracts: contract 'identity' names unknown provider 'ghost-identity-provider', which is not a declared canonical host ID"*) ;;
*) fail "4.3: expected the named error for the injected identity contract, got: $(printf '%s' "$dup_out" | tail -n 3)" ;;
esac
note "duplication: $(printf '%s' "$dup_out" | grep -m1 -o 'internal-contracts: .*' | cut -c1-170)"

echo "check-internal-contracts: PASS"
