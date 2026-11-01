# GeoPulse

GeoPulse records location history (track ingest from OwnTracks/GPSLogger-style
sources, PostGIS-backed tracks, OIDC login) and is placed on `oci-melb-1` by the
`geopulse` aspect in `modules/apps/geopulse.nix`. This runbook covers the
database seam, the operator-owned secrets and the two containers the aspect
delivers. The route is served; the policy's `posture` field is the only thing that withholds it
(see [Publication gate](#publication-gate)).

## Current state (2026-10-27)

| Item | State |
| --- | --- |
| Aspect | selected on `oci-melb-1` (`modules/hosts/oci-melb-1/default.nix`) |
| Secret file | `secrets/services/geopulse.yaml` exists (created 2026-10-14); its values are operator-owned |
| Runtime | two digest-pinned containers: `geopulse-backend` (`-native`) and `geopulse-ui` |
| Publication | the route is served; `posture` withholds it |
| Live login | not verified |

## Operator secret preparation

The file already exists and is populated. Use the steps below only for first
creation, for rotation, or when a value is found empty. Re-bootstrapping a populated
file rotates its values, including the database password, so do not run it on the
live file.

Only the operator creates or fills encrypted secrets; no agent generates,
decrypts or inspects key material. Everything GeoPulse needs lives in one
service-scope file, `secrets/services/geopulse.yaml`, readable by the owner and
by `oci-melb-1`.

1. Bootstrap it. The database password is generated; the three keys render
   empty:

   ```sh
   just secrets bootstrap secrets/services/geopulse.yaml
   sops updatekeys secrets/services/geopulse.yaml
   ```

2. Generate the two values once, on the operator's workstation, in a mode-0700
   temporary directory that is tmpfs or encrypted at rest — never on a host and
   never inside the repository:

   ```sh
   umask 077
   KEYDIR=$(mktemp -d "${XDG_RUNTIME_DIR:?}/geopulse-keys.XXXXXX")
   openssl rand -base64 32 > "$KEYDIR/ai-encryption-key.txt"
   base64 -d "$KEYDIR/ai-encryption-key.txt" | wc -c   # 32
   ```

   GeoPulse 2.x keeps sessions in PostgreSQL and no longer signs JWTs, so there is
   no keypair to generate. A file created for 1.x still carries `jwt/private_key`
   and `jwt/public_key`; they are ignored and can be dropped at the next rotation.
   The AI key must stay: it is base64 of exactly 16, 24 or 32 bytes (`KeyCipher`
   decodes it with `Base64.getDecoder()`) and encrypts provider secrets at rest.

3. Fill the file with the SOPS editor, pasting each PEM as a literal block
   scalar:

   ```sh
   sops edit secrets/services/geopulse.yaml
   ```

   Keep the shell in the repository when opening the encrypted file. Never fill
   a value through `sops set` arguments, `export`, or any other command whose
   argument list or history would carry key material. After saving and checking
   the encrypted file, delete the temporary key directory:

   ```sh
   rm -rf -- "$KEYDIR"
   unset KEYDIR
   ```

4. Track the file and refresh the Git index (`git add -A`) before anything
   evaluates `.#`.

An empty value is not a working default: the AI key decodes to 0 bytes and every
provider secret encrypted with it becomes unreadable. The start wrapper checks the
delivered files are non-empty before starting the JVM, so that failure is legible
rather than buried in a stack trace.

## Secret delivery contract

The values reach the service as **owner-scoped files under the sops secrets
mount**. The aspect declares one `sops.secrets` entry per value, read from the
file the host binds as `services.geopulse.secretFiles.host`:

| Value | Key in `secrets/services/geopulse.yaml` | Delivered path |
| --- | --- | --- |
| Database password | `roles/geopulse/password` | `/run/secrets/geopulse/postgres-password` |
| AI / provider-secret key | `ai/encryption_key` | `/run/secrets/geopulse/ai-encryption-key.txt` |

Each file is `0400` owned by the `geopulse` account. This delivery does not use
the rendered-template subdirectory: a sops *template* is written under
`/run/secrets.d/<n>/rendered`, whose parent is `0750 root:root`, so a non-root
service cannot traverse into it — the failure the Memos placement hit. The
secrets mount is the opposite: a tmpfs mounted `mode=0751` (sops-nix
`pkgs/sops-install-secrets/linux.go`) whose subdirectories are created
world-traversable, so the account opens its own files by name and cannot list
the directory.

The runtime consumes them: the backend container reads the key by mount and the
password from a rendered environment file, and restarts when one rotates (see
`## Runtime

Two containers on a dedicated `geopulse` Podman network, created by
`podman-network-geopulse.service`:

| Container | Image | Listeners | What it runs |
| --- | --- | --- | --- |
| `geopulse-backend` | `repo.ociImages.geopulseBackend` (`-native`) | `0.0.0.0:8080` on the bridge, unpublished | the GraalVM native backend |
| `geopulse-ui` | `repo.ociImages.geopulseUi` | `127.0.0.1:<route port>` → `:80` | nginx, the SPA and the proxy mappings |

- The UI image carries the front end the aspect used to run itself: it renders
  `config.js`, proxies `/api` and `/mcp` to `http://geopulse-backend:8080`, proxies
  `/osm/tiles/*` to OpenStreetMap with a 30-day cache, serves content-hashed assets
  and falls back to the app shell — which is how `/oidc/callback` resolves. Three
  env vars configure it: `GEOPULSE_BACKEND_URL`, `CLIENT_MAX_BODY_SIZE=200M`, and
  `OSM_RESOLVER`, left to the image's own detection.
- Only the loopback publish is deliberate: the edge dials it, and the backend port
  stays on the bridge with no published socket.
- The backend runs as root inside its container so the 0400 root-owned AI key mount
  is readable; that is the only reason for the override.
- The database is dialled on the service address (`host.services.internal`), not
  loopback: a bridged container cannot reach the host's `127.0.0.1`. The consumer's
  ACL therefore admits the container supernet (`10.89.0.0/16`) as well as loopback.
  PostgreSQL stays the host's own cluster.
- Mutable state is on the data mount and bound into the backend: `backups/` (with
  `.work/`) and `import/` (with `tmp/` and `chunks/`, so a multi-gigabyte upload
  never lands on the root filesystem). Directories are `0700 root:root`.
- The database password arrives through a rendered environment file, never a
  declared environment value, and both it and the OIDC client secret restart
  `podman-geopulse-backend.service` when they change.
- AI and MQTT stay off. MQTT is switched off explicitly; AI has no server-side
  switch upstream, so it is off because no user enables it.
- `GEOPULSE_PUBLIC_BASE_URL` is set from the route's identity, because the OIDC
  callback is built from it. CORS stays disabled: the front end proxies `/api` on
  the same origin.
- The backend image bundles PostgreSQL 17 and 18 clients and picks the matching
  major for the server, so its own backup feature needs no host binary path.

## Database seam

The substrate is a mechanism plus per-host clusters and consumer registrations
(D-058); moving a consumer between clusters is
[moving a PostgreSQL consumer](postgres-consumer-migration.md) and is not
repeated here.

- `oci-melb-1` runs the `postgres` instance on port 5432 (`/srv/data/postgres`),
  PostgreSQL **17.11**. Extension packages come from that instance's own
  extension set, so a package always matches the server version; the set
  provides PostgreSQL 17.11's **PostGIS 3.6.4**.
- `modules/apps/geopulse.nix` registers `services.postgres.consumers.geopulse`:
  database and role `geopulse`, `auth = "scram"`, `allowedCIDRs =
  [ "127.0.0.1/32" ]`. The backend is a native service on the same host and dials
  loopback, so no other source range is allowed; the mechanism appends the role's
  catch-all `reject` row, and nothing else reaches the role.
- The credential belongs to the consumer: `password = { file =
  <secretFiles.host>; key = "roles/geopulse/password"; }`. The substrate reads
  that same file and key to provision the role, so the password has one
  authoritative source rather than a copy that can drift.
- The encrypted file and the host binding that supplies its path belong to the
  secrets task. The binding is unconditional: the path must resolve at
  evaluation, so the operator encrypts the credential before deploying.
- Extensions are administrator-owned. The registration contributes
  `extensions = ps: [ ps.postgis ]` and `setupSQL` creating `postgis` and
  `postgis_topology`. The mechanism runs that SQL in the consumer's database as
  the `postgres` superuser on every cluster start, which is before the
  application starts and therefore before Flyway. This is a prerequisite, not a
  convenience: the application role must not be a superuser, and a non-superuser
  cannot install PostGIS at all (see the scratch run below).

## Migrations

- Flyway runs inside the application at start (`migrate-at-start=true`,
  `baseline-on-migrate=true`, `out-of-order=true`), so deploying a backend *is*
  the schema migration; there is no separate migration step to schedule. Any
  start of a backend whose migrations have not run against this database applies
  them.
- A database that ran the retired source build carries an extra column and its
  `flyway_schema_history` row: `oidc_session_states.code_verifier`, installed by the repeatable
  migration that build shipped. Upstream does not send PKCE, so nothing reads the column and the
  image no longer ships the file. The container sets
  `QUARKUS_FLYWAY_IGNORE_MIGRATION_PATTERNS=repeatable:missing` so start-time validation does not
  fail on it; the column is inert. To leave no trace, run before the first container start:

  ```sql
  DELETE FROM flyway_schema_history WHERE description = 'Add_oidc_session_code_verifier';
  ```

  The flag stays harmless afterwards — it only ignores applied repeatables that no longer exist.
- A migration run needs the cluster's own server and extension versions (the
  substrate never upgrades a cluster to match an application), the role's
  credential in the file the host binds, and the PostGIS extensions already
  installed by the administrator.
- Take a verified export before deploying a backend whose migrations have not run
  against this database: run the cluster's `postgresqlBackup` export unit (the
  mechanism disables its timer, and the restic job requires and runs after it),
  then let the restic job upload. A Nix generation rollback cannot undo
  migrations, so recovering from a bad upgrade means restoring the matching
  export together with the previous generation.

## OIDC client secret and the provider row

GeoPulse cannot be told about its identity provider from the environment: the
provider is a row in `oidc_providers`, created once through the admin API or UI,
and its client secret is stored in the database encrypted with the AI key.
Nothing in Nix declares that row, and no variable overrides a saved one.

- The canonical input is the client secret in the host OIDC file
  (`secrets/hosts/oci-melb-1/oidc.yaml`, key `geopulse/client_secret`). The operator enters *that same
  value* into the provider row — no second value is invented, and the file stays
  the source of truth for rotation.
- Because the provider secret is ciphertext in the database, the AI key and the
  database export form one recovery unit (design GP-6).
- Losing or rotating the AI key makes already-encrypted values unreadable,
  including any admin-entered geocoding, weather or backup credentials. A
  rotation is complete only once those values are re-entered with the new key.

### OIDC client

The client is declared once in `policy/identity.nix` and both sides read it from
there: the identity provider provisions it, and GeoPulse receives it as
`GEOPULSE_OIDC_PROVIDER_AUTHENTIK_*` from a sops-rendered environment file.

| Field | Value |
| --- | --- |
| client id | `geopulse` |
| callback | `https://geo.shrublab.xyz/oidc/callback` (derived from the route) |
| scopes | `openid profile email`, for the `users` group |
| signature algorithm | RS256, the provider's default |
| PKCE | off: the backend sends no code challenge |

The operator supplies the client secret. Add `geopulse/client_secret` to
`secrets/hosts/oci-melb-1/oidc.yaml` and re-encrypt it (`just secrets …`, which
runs `sops updatekeys`). The provider host reads that same key when it provisions
the client; the backend reads it from its own rendered file
(`config.sops.secrets."geopulse/oidc-client-secret"`), never from the unit
environment.

### Provider row

One row in `oidc_providers`, created once through the admin API or UI while the
service is private, and owned by the database afterwards:

| Field | Value |
| --- | --- |
| name | `geopulse` (lower-case letters, digits and dashes, 2–50 characters) |
| display name | what the sign-in button shows, for example `Shrublab` |
| client id | `geopulse` |
| client secret | the value of `geopulse/client_secret` |
| discovery URL | `https://auth.shrublab.xyz/application/o/geopulse/.well-known/openid-configuration` |
| scopes | `openid profile email` |
| enabled | on |

Discovery metadata is fetched and cached when the row is created or tested, so a
row whose test fails authenticates nobody: fix it before relying on the login.

### Account linking and the primary email

Automatic linking stays off (upstream default). An identity whose email matches an
existing GeoPulse account is therefore not attached to it silently: the callback
reports that linking is required, and the operator completes it through the
password path. Later logins map by provider and subject.

The provider returns the account's email claim, and the backend rejects an ID token
without a non-empty one. Every enrolled account has one — the fleet's login policy
requires a verified address — so an account that cannot log in here has a missing or
unverified address upstream.

### Registration precedence

Registration is open by default: `auth.registration.enabled`,
`auth.password-registration.enabled` and `auth.oidc.registration.enabled` are each
true, and a value saved in the database outranks both the environment variable and
the built-in default. Two consequences:

- Registration is checked before a user is created, so closing it before the
  owner's account exists locks the operator out. Create and verify the owner
  first, then close password and OIDC registration.
- Once an admin saves one of these in the UI, a later environment change is
  ignored: the database is the authority. Verify the effective setting instead of
  assuming the deployment decided it.

The first account created while no admin exists becomes an admin
(`GEOPULSE_FIRST_USER_ADMIN` defaults to true, and this deployment leaves it
alone), which is how the owner gets in without configuring an admin email.

## Publication gate

The route declares its public identity — `geo.shrublab.xyz`, Access-free,
application OIDC on — and its publication posture separately.

| Route `posture` in policy | Route identity | Edge site |
| --- | --- | --- |
| `private` | unchanged | withheld |
| absent (defaults `public`) | unchanged | served |

- Publication is the policy's own field, and the route is currently served. Withholding it again
  is one line in `policy/web-services.nix` plus a deploy: `posture = "private";` on the `geopulse`
  route (D-124). There is no host-side switch, so the policy is the only place that answers
  whether the site is live.
- Flip it only after the owner's login is verified and password and OIDC
  registration are closed. Registration is checked before a user is created, so a
  published site with open registration admits strangers.
- DNS and the Access-free hostname are already resolved in the exported policy
  while the gate is closed: the gate withholds the served site, not the identity.
  The flip therefore needs no re-export. A host that has not flipped the fact
  answers that hostname with the edge's default for an unmatched host — a bodyless
  `200` carrying no application content and no route to the listener.
- The app's own origin is the route's public identity, because the OIDC callback is
  built from it and the aspect requires one. CORS stays disabled because the front end
  proxies `/api` on the same origin.

## Public surface denials

GeoPulse marks several endpoints as public (`quarkus.http.auth.permission.public`),
which is why its own front end can read them without a session. This deployment
needs only some of them, so the published route refuses the rest at the edge,
before the request reaches the listener. The list lives on the route
(`policy/web-services.nix`, `deniedPaths`) and is rendered by the ingress as an
ordered route-scoped guard; the shared pipeline is untouched.

| Denied | Why |
| --- | --- |
| `/api/prometheus/metrics` | operational metrics, public in the permit list |
| `/api/health`, `/api/maintenance/status` | operational diagnostics |
| `/api/version`, `/api/version/status` | version diagnostics |
| `/api/home/content` | unauthenticated home copy |
| `/api/shared/*` | public share links, a deployment non-goal |
| `/api/overland`, `/api/traccar`, `/api/colota`, `/api/homeassistant`, `/api/homeassistant/*`, `/api/dawarich/*` | ingest sources this deployment does not enable |
| `/api/ai`, `/api/ai/*` | AI is a non-goal; closed publicly even though it needs a session |
| `/mcp`, `/mcp/*` | the MCP tool surface |

The list is entered as the permit-list pattern for each path, so `/api/shared/*`
is denied while the authenticated management APIs beside it keep working. The edge
is what keeps `/mcp` off the public host: the listener still mirrors `/mcp` on
loopback, so an operator on the host can use it.

Kept open deliberately:

- `/api/owntracks` and `/api/gpslogger` — the first acceptance sources; both
authenticate with Basic credentials.
- `/api/geocoding/*` — the app has geocoding features and a geocoding store, so it
is not closed on a guess.
- `/api/mobile/session/exchange` — no web front end calls it; it belongs to the
mobile client, which is not deployed. Close it here if that stays true.
- `/api/users/register` and `/api/users/sign-up/status` — registration is closed by
its own database setting, which GP-4 requires before the gate opens.

Denying the version and home-content reads costs the landing page's version banner
and welcome copy: the front end fetches both from `Home.vue` and falls back to
`Unknown` and a default release link when a fetch fails. The admin status page's
metric panel degrades the same way.

## Logging in

The route is served, so the browser login goes through `https://geo.shrublab.xyz/` directly; there
is no second origin to reach and no private-bootstrap procedure to run.

## Key recovery

- **2.x sessions** live in the database, so a lost session is a re-login and nothing more.
  A 1.x-era JWT pair has no reader any more:
  regenerate the pair, fill the file, redeploy, and users sign in again. The
  database holds no key material for these.
- **AI key** — the opposite. Existing ciphertext (the provider client secret and
  any admin-entered API keys) becomes unreadable, so the provider secret must be
  re-entered. When restoring a database export, restore it together with the
  version of `secrets/services/geopulse.yaml` that produced the export; the
  file's Git history is that record.
- Device credentials are neither: the operator enters them in the UI and they
  live in the database.

## Scratch verification of the seam

The registration was evaluated in isolation, then the seam was exercised on a
disposable cluster that matches the host's versions — the same server package the
mechanism composes for this consumer
(`postgresql-and-plugins-17.11`: PostgreSQL 17.11 with PostGIS 3.6.4) — against
the packaged backend of that date, whose migrations included `V36.53.0`.

What the isolation proves is the registration the mechanism acts on: the
consumer's database, role, credential file and key, the loopback-only
`allowedCIDRs`, `postgis` composed out of the instance's own extension set, and
the provisioning script the substrate renders for it — `CREATE ROLE "geopulse"`,
`ALTER ROLE "geopulse" LOGIN`, `CREATE DATABASE "geopulse"`, `ALTER DATABASE
"geopulse" OWNER TO "geopulse"`, the password applied from
`/run/secrets/postgres/geopulse.password`, and the extension SQL run through
`psql --dbname geopulse --command …` by a unit that runs as `postgres`. The
script contains no `SUPERUSER`, `CREATEDB`, `CREATEROLE` or `BYPASSRLS` clause.

Observed on a scratch cluster (x86_64, deleted afterwards; the target host and
its database were never touched):

| Observation | Result |
| --- | --- |
| Setup as the administrator, mirroring the rendered script | role, `LOGIN`, database, ownership, password, then `CREATE EXTENSION IF NOT EXISTS postgis` / `postgis_topology` |
| Extensions afterwards | `postgis 3.6.4`, `postgis_topology 3.6.4`, both owned by `postgres` |
| Application role | `rolsuper f`, `rolcreatedb f`, `rolcreaterole f`, `rolbypassrls f`, `rolcanlogin t` |
| Migrations applied by the packaged backend as that role | 109 applied, `36.53.0 Add oidc session code verifier` succeeded, schema at `v36.53.0` |
| PKCE schema change | `oidc_session_states.code_verifier`, `character varying` |
| Control — the application role installing PostGIS itself | `ERROR: permission denied to create extension "postgis"`, nothing installed |
| Control — connecting to an unallowed database | the role's catch-all `reject` row refused a connection to another database |

The queries, for repeating the check against the real cluster:

```sql
SELECT extname, extversion, pg_get_userbyid(extowner) AS owner
FROM pg_extension WHERE extname LIKE 'postgis%' ORDER BY extname;

SELECT rolname, rolsuper, rolcreatedb, rolcreaterole, rolbypassrls, rolcanlogin
FROM pg_roles WHERE rolname = 'geopulse';

SELECT version, description, success
FROM flyway_schema_history WHERE version = '36.53.0';

SELECT table_name, column_name, data_type
FROM information_schema.columns WHERE column_name = 'code_verifier';
```

### Secret delivery geometry

The declared delivery was evaluated in isolation, then the two geometries were
probed with a foreign uid so the contract is not taken on trust (non-secret
fixture strings only, rootless container, deleted afterwards):

| Observation | Result |
| --- | --- |
| Isolated evaluation of the aspect with a fixture file bound | two `sops.secrets` entries, all `0400`, owner and group `geopulse`, keys `roles/geopulse/password`, `jwt/private_key`, `jwt/public_key`, `ai/encryption_key` |
| Their delivered paths | `/run/secrets/geopulse/{postgres-password,ai-encryption-key.txt}`; no entry under `/run/secrets.d` |
| The substrate's own copy of the same password | `/run/secrets/postgres/geopulse.password`, key `roles/geopulse/password` — one source, two owner-scoped deliveries on the same host |
| Service account reading a delivered file (`0751` mount, `0400` owned by it) | readable; the mount itself is not listable |
| Service account reading a template-style path (`0750 root:root` parent) | `Permission denied` |
| The delivered file under `PrivateUsers`, `ProtectSystem=strict` and `ProtectHome` | read intact; `PrivateTmp` alone hides a `/tmp` path, so the value cannot live under a home directory or the temporary directory |

## Backup, upgrade and restore

Recovery has two halves, and neither one alone restores GeoPulse:

- **Database** — the substrate's `pg_dumpall` export (`services.state-backups.services.postgres`)
  is the only copy of the database. The live PostgreSQL directory is never captured raw.
- **Mutable files** — `services.state-backups.services.geopulse` captures `backups/`
  and `import/` through the restic job, excluding the disposable `backups/.work`,
  `import/tmp` and `import/chunks`.
- **Keys** — the SOPS-held `secrets/services/geopulse.yaml` is not in either payload. It
  must be recoverable from its Git history together with the matching export.

### Before every upgrade

Take a verified export before deploying a backend whose Flyway migrations have not
run against this database. Run the cluster's `postgresqlBackup` unit by hand, confirm the
dump file is complete, and let the restic job upload it. Flyway runs at backend
start and a Nix generation rollback cannot undo migrations, so the export is the
only rollback path.

### Restore

1. Restore the matching `secrets/services/geopulse.yaml` version. The AI key
   encrypts the provider client secret and any entered API keys; without the key
   that produced the export, those values are unreadable and must be re-entered.
   2.x keeps sessions in the database, so there is no signing key to regenerate.
2. Stop `podman-geopulse-backend.service` and `podman-geopulse-ui.service`. Restore the
   database from the pre-upgrade export into a cluster on the same PostgreSQL and PostGIS
   versions, and confirm `flyway_schema_history` matches the export's schema version.
3. Stage the mutable files from the restic snapshot with
   `state-restore-stage <snapshot> <include-path>` (its usage line lists both
   arguments), then copy `backups/` and `import/` into `/srv/data/geopulse`,
   owned by `root:root` with mode `0700`.
4. Start both containers.

Scratch evidence (PostgreSQL 17.11 with PostGIS 3.6.4, disposable clusters,
synthetic data): a `pg_dumpall` export of a cluster holding 500 PostGIS track
points, one user, a pgcrypto-encrypted provider secret and a Flyway history ending
at `36.53.0` was restored into a fresh cluster. Every row, the geography values,
the PostGIS version, the Flyway history and the database owner survived, and the
provider secret decrypted only with the original key. The one restore error was
the expected `role "postgres" already exists`. Not exercised: the restic payload
and `state-restore-stage`, the real encryption key, the substrate's own
provisioning on a host, and any real export.

## Resolved: backup maintenance database

The backend used to crash-loop at startup. Its backup maintenance service
opens a JDBC connection to the `postgres` database by default, and the `geopulse`
role is allowed only its own database, so `pg_hba` rejected every attempt
(`FATAL: pg_hba.conf rejects connection for host "127.0.0.1", user "geopulse",
database "postgres"`).

The aspect now sets `GEOPULSE_BACKUP_MAINTENANCE_DATABASE=geopulse`. That is safe
because the maintenance connection takes only a cluster-wide advisory lock
(`pg_try_advisory_lock_shared`) for backup coordination, and an advisory lock does
not depend on which database it is taken in; the role stays inside its own
database. Granting the role `postgres` access would widen the substrate contract
for no benefit.

Verified on `oci-melb-1` after the 2026-10-19 deploy: the unit is `active`,
`Result=success`, `NRestarts=0`, no `pg_hba.conf rejects` lines since it started,
and `/api/health` answers `200`. The earlier 1819 rejections in the boot journal
all predate the fix.

Both GeoPulse units also carry `StartLimitIntervalSec=300` with
`StartLimitBurst=5` and a `services.notify.events` registration. The previous
configuration (the systemd default limit of five starts in ten seconds, against a
26-second restart cycle) never tripped, so the unit rested in `auto-restart` and
never entered `failed` — which is what kept the loop invisible to activation and
to the notifier.

## Still open

- Live provider login: the operator fills `geopulse/client_secret` in
  `secrets/hosts/oci-melb-1/oidc.yaml`, enters the same value into the provider row, and logs in at
  `https://geo.shrublab.xyz/`.
- Owner account creation with registration closed, verified against the live instance.
- Device ingest and the tile proxy (no tile has been fetched yet) are unmeasured. The
  former JVM heap bound is now the container's memory limit.
- A real export and restore have not been exercised; the scratch evidence above
  covers the database seam only.

### Runtime verification

`tests/check-geopulse-contract.sh` (registered in `just checks all`) evaluates the
`oci-melb-1` configuration and pins what can drift apart: both images against their
`repo.ociImages` entry and their digest, the UI's published port against the route's
upstream port, the dedicated network and its ordering before both containers, the
backend's dial against the service address and the cluster's port, the consumer ACL
admitting the container supernet as well as loopback, the password arriving through an
environment file rather than a declared value, the AI key mounted read-only at the path
the environment names, the state mounts and their backup registration, the failure
notifications, and that the retired native units are gone. Two mutations — dropping the
container CIDR and dialling loopback — make it fail, so those assertions are not vacuous.
