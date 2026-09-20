# Moving a PostgreSQL consumer between clusters

The substrate is composed from a mechanism, per-host clusters, and consumer
registrations (D-058). A consumer is registered next to the service that uses
it, and it resolves its endpoint from the host's own cluster when one is
declared, otherwise from the internal transport contract. Moving a database
therefore means moving a registration and, for a cross-host move, the endpoint
source — never the service's connection code.

Two moves are possible, and they differ only in where the registration lives.

## Same-host move (the normal case)

The service and its database share a host.

1. Declare the cluster on the target host if it does not have one:

   ```nix
   services.postgres.instances.<name> = { port = 5432; dataDir = "/srv/data/postgres"; };
   ```

   …and select the `postgres` aspect in that host's record.

2. Move the registration to the service's own module (or the host file if the
   service is a leaf without a registration yet):

   ```nix
   services.postgres.consumers.<consumer> = {
     database = "<database>";
     auth = "scram";
     password = { file = <consumer-owned secret file>; key = "<key>"; };
     allowedCIDRs = [ "<source range>" ];   # a container bridge, not the tailnet
   };
   ```

3. Remove the registration from the previous provider host. If no consumer
   there needs a password any more, its provider-side secret file is no longer
   read at all.

4. Migrate the data (below), then deploy.

The service needs no edit: `services.postgres.localEndpoint` is how a
co-located consumer discovers the cluster it should use, and the consumer's
`extensions`/`setupSQL` follow the registration.

## Cross-host move (the exception)

The service runs on one host and the database on another.

1. Register the consumer on the **provider** host — that is the only host that
   can create the role and read its credential — and point `password.file` at
   the consumer's secret file, which means the provider host gains read access
   to it. Treat that as an explicit blast-radius widening in `.sops.yaml`.
2. The consumer host reads the endpoint from the contract
   (`config.repo.internal.postgres.<instance>`); the contract's provider and
   port must agree with the cluster that actually serves it, or evaluation fails
   with a named `internal-contracts:` error.

## Migrating the data

The mechanism provisions databases and roles; it does not copy rows. Move them
by hand, in this order:

```sh
# 1. On the old provider: dump the single database (custom format, compresses).
ssh dev@<old-provider> 'sudo -u postgres pg_dump -Fc <database>' > /tmp/<database>.dump

# 2. Note any extensions the source database relies on; the target cluster must
#    declare the packages, and the registration must create them.
ssh dev@<old-provider> 'sudo -u postgres psql -d <database> -Atc \
  "SELECT extname FROM pg_extension ORDER BY 1"'

# 3. Deploy the new configuration first, so the target cluster, database, role,
#    and extensions exist.

# 4. Copy the dump to the new provider and restore it as the database owner.
scp /tmp/<database>.dump dev@<new-provider>:/tmp/
ssh dev@<new-provider> 'sudo -u postgres pg_restore --clean --if-exists \
  --no-owner -d <database> /tmp/<database>.dump'

# 5. Verify before retiring anything: row counts, then the service's own health
#    endpoint, then one full backup run on the new host.
ssh dev@<new-provider> 'sudo -u postgres psql -d <database> -c "\dt"'
ssh dev@<new-provider> 'systemctl start restic-backups-state.service && journalctl -u restic-backups-state -n 20'
```

Only after the service is healthy on the new cluster should the old database,
role, and provider-side credential be removed — and removing a credential is an
operator action in `.sops.yaml`, never an automatic one.

## What backup coverage looks like afterwards

A host that registers at least one consumer gets the export-first chain
automatically: `postgresqlBackup` runs `pg_dumpall` into
`/srv/data/state-backups/postgres`, the restic job requires and runs after it,
and the staging path is registered as an export for the host's own bucket. A
cluster with no consumers registers no backup job at all.

## Reference move: AudioMuse from oci-melb-1 to home-forge

The concrete values for the move that motivated this runbook. Source:
`oci-melb-1` (database and role `audiomuse`, credential at
`roles/audiomuse/password` in `secrets/services/postgres-shared.yaml`). Target:
`home-forge` (`instances.forge`, port 5432, `/srv/data/postgres`), where the
registration takes its credential from `secrets/applications/music.yaml` at
`audiomuse/postgres_password` — the same value the container already uses, so no
rotation is involved in either direction. Restoring is preferred over letting
AudioMuse rebuild its analysis, which costs hours of runner time.

The `ssh … psql <<'SQL'` blocks below are **shell** commands to run from the
workstation. When you are already sitting in a psql prompt, use the plain SQL
inside those blocks (drop the `ssh …`, the heredoc markers, and the `#` note
lines) — the copy-paste form for the source capture is:

```sql
show server_version;
select pg_size_pretty(pg_database_size(current_database()));
select extname from pg_extension order by 1;
select count(*) from information_schema.tables where table_schema = 'public';
-- Exact counts: `n_live_tup` above is an estimate, and a freshly restored
-- database reports 0/-1 for every table until ANALYZE runs, which reads like a
-- failed restore. Compare these numbers instead (or run `analyze;` first).
select relname, (xpath('/row/c/text()',
  query_to_xml(format('select count(*) as c from %I', relname), false, true, '')))[1]::text::int as rows
from pg_stat_user_tables order by rows desc;
```

Both clusters run the same server (17.10, `psqlSchema` 17), so a dump restores
without a version step. Writers: `podman-audiomuse-web`,
`podman-audiomuse-worker` (web on port 8000). Everything streams between hosts;
nothing is staged on a workstation.

```sh
# 1. Capture the source (still live on oci-melb-1) so the restore can be
#    compared against it, and check for extensions the target must provide.
ssh oci-melb-1 'sudo -u postgres psql -d audiomuse' <<'SQL'
show server_version;
select pg_size_pretty(pg_database_size(current_database()));
select extname from pg_extension order by 1;
select count(*) from information_schema.tables where table_schema = 'public';
-- Exact counts: `n_live_tup` above is an estimate, and a freshly restored
-- database reports 0/-1 for every table until ANALYZE runs, which reads like a
-- failed restore. Compare these numbers instead (or run `analyze;` first).
select relname, (xpath('/row/c/text()',
  query_to_xml(format('select count(*) as c from %I', relname), false, true, '')))[1]::text::int as rows
from pg_stat_user_tables order by rows desc;
SQL

# 2. Quiesce the consumer (it still points at oci-melb-1 at this moment) so the
#    dump is consistent.
ssh home-forge 'sudo systemctl stop podman-audiomuse-web podman-audiomuse-worker'

# 3. Stream the dump straight across.
ssh oci-melb-1 'sudo -u postgres pg_dump -Fc -d audiomuse' | ssh home-forge 'cat > /tmp/audiomuse.dump'

# 4. Deploy the target: the mechanism creates the cluster, role, database, and
#    pg_hba rule. The units may start against the empty database here; the
#    restore below replaces whatever they initialise.
just deploy home-forge
ssh home-forge 'sudo -u postgres psql -Atc "select datname from pg_database where datname = '"'"'audiomuse'"'"'"'

# 5. Stop them again and restore as the role, so object ownership matches the
#    consumer. --clean replaces the app-initialised schema.
ssh home-forge 'sudo systemctl stop podman-audiomuse-web podman-audiomuse-worker'
ssh home-forge 'sudo -u postgres pg_restore --clean --if-exists --role=audiomuse -d audiomuse /tmp/audiomuse.dump'

# 6. Compare against step 1, then start the consumer and watch it authenticate.
ssh home-forge 'sudo -u postgres psql -d audiomuse' <<'SQL'
select count(*) from information_schema.tables where table_schema = 'public';
select extname from pg_extension order by 1;
-- Exact counts: `n_live_tup` above is an estimate, and a freshly restored
-- database reports 0/-1 for every table until ANALYZE runs, which reads like a
-- failed restore. Compare these numbers instead (or run `analyze;` first).
select relname, (xpath('/row/c/text()',
  query_to_xml(format('select count(*) as c from %I', relname), false, true, '')))[1]::text::int as rows
from pg_stat_user_tables order by rows desc;
SQL
ssh home-forge 'sudo systemctl start podman-audiomuse-redis podman-audiomuse-worker podman-audiomuse-web'
ssh home-forge 'sudo journalctl -u postgresql -n 40 --no-pager | grep -i audiomuse'
ssh home-forge 'sudo journalctl -u podman-audiomuse-web -n 50 --no-pager | tail -n 20'
ssh home-forge 'curl -fsS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/'

# 7. Prove the new backup path before retiring anything.
ssh home-forge 'sudo systemctl start restic-backups-state.service'
ssh home-forge 'sudo ls -lh /srv/data/state-backups/postgres/'

# 8. Only after the new cluster has soaked: deploy oci-melb-1 without the
#    registration, then drop the leftovers by hand (nothing drops them for you).
just deploy oci-melb-1
ssh oci-melb-1 'sudo -u postgres psql' <<'SQL'
drop database if exists audiomuse;
drop role if exists audiomuse;
SQL
```

The one step that can bite: an extension in step 1 that the target server does
not ship makes `pg_restore` fail on `CREATE EXTENSION`. Contrib extensions
(`pg_trgm`, `unaccent`, `btree_gin`, …) travel with the PostgreSQL derivation
itself — the same package runs on both hosts, so they need nothing declared.
Only third-party extensions (`vector`, `postgis`, …) require a registration
change, and the query above is how you find out which kind you have. Declare it on the registration in
`modules/services/music/audiomuse.nix` and redeploy home-forge first:

```nix
extensions = ps: [ ps.pgvector ];          # server package, version-matched
setupSQL = "CREATE EXTENSION IF NOT EXISTS vector;";
```

The password file can be retired in step 8: after this move nothing reads
`secrets/services/postgres-shared.yaml`, so deleting it and its `.sops.yaml`
rule is an operator action with no runtime effect.

Rollback, valid until step 8: the source database was never modified, so
pointing the consumer back (`applications.music.audiomuse.postgresHost =
"oci-melb-1"` in forge's `_nixos.nix`) and redeploying home-forge returns it to
the working pre-move state. The credential value is unchanged, so both endpoints
accept the same password.
