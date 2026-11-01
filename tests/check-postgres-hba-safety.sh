#!/usr/bin/env bash
# PostgreSQL host-based authentication, as our substrate renders it.
#
# These are format and ordering rules of a file we generate, which no Nix check
# can see and which fail in ways that take the cluster down rather than degrade
# it:
#
#   - a `host` row whose address carries no mask shifts the auth-method column
#     into the netmask field, and postgres refuses the entire pg_hba file rather
#     than the row;
#   - pg_hba is first-match-wins, so an allow row placed after a role's
#     catch-all reject can never match;
#   - a consumer registered with the substrate but granted no row cannot
#     connect, and nothing at evaluation time says so.
#
# Everything else about provisioning is the module's own concern: it evaluates
# or it does not.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

HOSTS=(home-forge oci-melb-1 la-admin-1)

fail() {
  echo "check-postgres-hba-safety: $*" >&2
  exit 1
}

for host in "${HOSTS[@]}"; do
  probe="$(
    nix eval --no-write-lock-file --json --apply 'c:
      let
        consumers =
          if (c.options.services.postgres or null) != null then
            builtins.attrNames (c.config.services.postgres.consumers or { })
          else
            [ ];
      in
      {
        inherit consumers;
        rows =
          if (c.options.services.postgresql or null) != null then
            c.config.services.postgresql.authentication
          else
            [ ];
        cluster = (c.options.services.postgres or null) != null;
      }' "path:.#nixosConfigurations.${host}.config"
  )" || fail "${host}: pg_hba does not evaluate"

  printf '%s' "$probe" | python3 -c '
import json, sys

host = sys.argv[1]
got = json.load(sys.stdin)
rows = [r.strip() for r in got["rows"] if r.strip() and not r.lstrip().startswith("#")]
errs = []

host_rows = []
for row in rows:
    fields = row.split()
    if not fields or fields[0] != "host":
        continue
    host_rows.append(fields)
    if len(fields) != 5:
        errs.append(f"row {row!r} must be: host <db> <role> <cidr> <method>")
        continue
    address = fields[3]
    if address not in ("all", "samehost", "samenet") and "/" not in address:
        errs.append(f"row {row!r} needs a masked address; postgres rejects the whole file")

# First match wins, so nothing a role may reach can follow its catch-all reject.
reject_at = {}
for index, fields in enumerate(host_rows):
    if len(fields) == 5 and fields[1] == "all" and fields[4] == "reject":
        reject_at.setdefault(fields[3], index)
for index, fields in enumerate(host_rows):
    if len(fields) == 5 and fields[1] != "all" and fields[3] in reject_at:
        if index > reject_at[fields[3]]:
            errs.append(f"row {fields!r} follows the catch-all reject for {fields[3]!r} and can never match")

# A registered consumer that was never granted a row is unreachable, silently.
granted = {fields[2] for fields in host_rows if len(fields) == 5 and fields[2] != "all"}
for consumer in got["consumers"]:
    if consumer not in granted:
        errs.append(f"consumer {consumer!r} is registered with the substrate but has no pg_hba row")

if errs:
    print(f"{host}: " + "; ".join(errs), file=sys.stderr)
    sys.exit(1)
' "$host" || fail "${host}: pg_hba safety violated"
done

echo "check-postgres-hba-safety: PASS (${HOSTS[*]})"
