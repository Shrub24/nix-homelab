# Homarr v2 Runbook

Homarr is the user-facing dashboard on `oci-melb-1`, separate from the operator Homepage on `la-admin-1`. Its boards, service tiles, users, groups, and per-user home boards are edited in Homarr; they are not generated from web policy. The public route is `https://home.shrublab.xyz`, but it remains withheld until private OIDC acceptance is complete. Cloudflare Access is off; Homarr's own OIDC login is the browser gate.

## Status (2026-10-20)

- Installed on `oci-melb-1` and reachable on the tailnet at
  `https://oci-melb-1.tail0fe19b.ts.net:7575/`.
- The route is published: the edge serves `https://home.shrublab.xyz`, Cloudflare Access is off,
  and Homarr's own OIDC login is the browser gate.
- Group membership follows the provider's `groups` claim (D-103), so administration is granted by
  putting a person in `service-admins` in the identity provider — not by promoting them in Homarr.
- There is no bootstrap switch. Whether the instance runs private or public is the route's
  `posture` in `policy/web-services.nix`, and nothing else (D-104, D-124).

## 1. Prepare secrets

The service template generates two independent 64-character hexadecimal values with `secrets/.templates/services/homarr.yaml.j2`:

- `auth_secret` — persistent Auth.js session secret. Changing it invalidates existing sessions.
- `secret_encryption_key` — persistent key for integration secrets stored in Homarr's database. A mismatch makes those values unusable.

The file already exists. Bootstrap only if it is ever recreated, and update recipients only when they change:

```sh
just secrets bootstrap secrets/services/homarr.yaml   # first creation only
sops updatekeys secrets/services/homarr.yaml          # when recipients change
```

The OCI host's OIDC file must contain `homarr/client_secret`. Confirm the key is present, then add it if it is missing. Add it to the existing encrypted file rather than re-bootstrapping it, because a re-bootstrap rotates the other client secrets:

```sh
sops edit secrets/hosts/oci-melb-1/oidc.yaml
sops updatekeys secrets/hosts/oci-melb-1/oidc.yaml
```

Do not decrypt either file manually, put values on a command line, or regenerate either Homarr service key after the instance has stored data. The runbook and module use only the encrypted paths.

### Selection on oci-melb-1 (already applied)

The host record selects `aspects.homarr` beside the other user-facing applications, and `_nixos.nix` binds both secret files inside the `services` block:

```nix
homarr = {
  secretFiles = {
    host = ../../../secrets/services/homarr.yaml;
    oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
  };
};
```

The aspect owns the container, the OIDC wiring and the backup contract; the host supplies only
the two secret files. `tests/check-homarr-contract.sh` pins the route, the client and the secret
bindings.

## 2. Private first-admin and OIDC setup

The OIDC client accepts two exact redirect URIs:

- Public: `https://home.shrublab.xyz/api/auth/callback/oidc`
- Private: `https://oci-melb-1.tail0fe19b.ts.net:7575/api/auth/callback/oidc`

The private URI uses the host and port from Homarr's provider endpoint, with `https` because Tailscale Serve terminates TLS.

**Use the full tailnet name, not the short one.** Tailscale Serve terminates TLS with a certificate issued for the node's tailnet FQDN only (`/var/lib/tailscale/certs/oci-melb-1.tail0fe19b.ts.net.crt` on the host), so `https://oci-melb-1:7575/` fails the handshake — the browser reports "Secure connection failed" and curl reports `error:0A000438:SSL routines::tlsv1 alert internal error`. That is the certificate refusing an SNI it does not cover, not a broken proxy; the FQDN with the same port answers. `tailscale serve status` on the host lists the only reachable form. To obtain the current name from the resolved catalog:

```sh
nix eval --raw .#nixosConfigurations.la-admin-1.config.repo.web.catalog.homarr.endpoint.host
```

`NEXTAUTH_URL` is intentionally unset so the callback follows the forwarded request host and can
use either registered URI.

### Posture: one field, no state

`AUTH_PROVIDERS` and `BASE_URL` are derived from the route's `posture`, so there is no second
switch and nothing to remember between deploys:

| route `posture` | `BASE_URL` | `AUTH_PROVIDERS` | Use |
| --- | --- | --- | --- |
| absent or `public` | the public URL (`home.shrublab.xyz`) | `oidc` | the deployed state |
| `private` | the private Tailscale Serve origin | `credentials,oidc` | first administrator, and recovery |

A withheld route is a private instance, so it keeps the private origin and the credentials
provider. Publishing a route therefore also disables local credentials — which is the point:
the two cannot drift apart, and a public route can never keep a password login alive.

**Recovery is the same field.** If identity breaks and no administrator can sign in, set
`posture = "private"` on the `homarr` route and deploy; the instance returns to the private origin
with the credentials provider, and the local administrator account — which group sync never
touches, because it is not an OIDC user — is reachable again. The provider keeps rendering the
tailnet front for a private route, so the private origin still answers.

**Deploy order matters.** Homarr and the identity provider now share `oci-melb-1`, so one deploy
carries both; the client's scopes come from the policy the provider provisions from
(`policy/identity.nix`).

### First bring-up on a new host

1. Leave the route's posture `private` and deploy the host that runs Homarr.
2. Open the private origin on the tailnet, and create the first credentials administrator.
3. Sign in through the identity provider; that OIDC user gets its groups from the claim automatically.
4. Create the Homarr group that matches the provider's admin group (`service-admins`) and give it the
   Administrator preset, then confirm the OIDC account is an administrator.
5. Set the route's posture back to `public` and deploy. Local credentials are disabled by the same
   change; keep the local account until you have confirmed provider administration works.

### Verifying the deployed state

- Anonymous requests to `https://home.shrublab.xyz` must not read dashboard content.
- The provider's sign-in must complete through the public callback.
- An account in the provider's `service-admins` group must see the administration surface; an
  account only in `users` must not.

### Group membership

Homarr does not decide group membership: the `groups` claim is authoritative
(`AUTH_OIDC_GROUPS_LOCAL_MANAGEMENT=false`), and the client requests it through the policy in
`policy/identity.nix`.

- **Automatic:** adding a person to `service-admins` in the provider grants whatever that group
  holds in Homarr, at their next login.
- **Manual, once:** create the Homarr group with the *same name* and give it the Administrator
  preset. Homarr joins groups by name and never creates them.

Sync is authoritative: an OIDC user is removed from every Homarr group the claim does not name,
except `Everyone`, so a group they must keep has to exist in the provider too. The credentials
administrator is not an OIDC user, so sync never touches it.

Homarr's board and catalogue configuration is imperative. Add only user-facing destinations; a route or hostname change in Nix policy may need a corresponding manual edit in Homarr.

## 3. Backups, restore, and upgrades

The backup contract captures `/srv/data/homarr` except for its live SQLite database directory. Before restic runs, it uses SQLite's backup API to export `/srv/data/homarr/db/db.sqlite` to `/srv/data/state-backups/homarr/db.sqlite`; this avoids copying a live database or WAL sidecars as the database backup. The Homarr aspect also provides that SQLite CLI on the target host for staged-restore integrity checks.

Before an upgrade, confirm a recent successful backup:

```sh
just backups status oci-melb-1
just backups logs oci-melb-1
```

Homarr may migrate its database on startup. Keep the pre-upgrade image reference, the matching encrypted service secret file (especially `secret_encryption_key`), and a verified snapshot. Stage the raw appdata and database export separately from the operator workstation; `restore-stage` extracts them on the target host and prints target-host paths:

```sh
just backups restore-stage oci-melb-1 <snapshot> /srv/data/homarr
just backups restore-stage oci-melb-1 <snapshot> /srv/data/state-backups/homarr
```

On `oci-melb-1`, stop Homarr and the backup job, preserve the live directory, then apply the staged raw files and the SQLite export. Replace each `restore.<id>` with the path printed by the corresponding staging command:

```sh
sudo systemctl stop podman-homarr.service restic-backups-state.service restic-backups-state.timer
raw=/var/tmp/state-restore/restore.<raw-id>
exported=/var/tmp/state-restore/restore.<export-id>

sqlite3 "$exported/srv/data/state-backups/homarr/db.sqlite" "PRAGMA integrity_check;"  # expect: ok
sudo mv /srv/data/homarr /srv/data/homarr.pre-restore-$(date +%s)
sudo install -d -o 1001 -g 1001 -m 0750 /srv/data/homarr
sudo cp -a "$raw/srv/data/homarr/." /srv/data/homarr/
sudo install -d -o 1001 -g 1001 -m 0750 /srv/data/homarr/db
sudo install -o 1001 -g 1001 -m 0600 \
  "$exported/srv/data/state-backups/homarr/db.sqlite" \
  /srv/data/homarr/db/db.sqlite
sudo systemctl start podman-homarr.service
```

Validate startup, an OIDC login, the restored boards, and an integration secret. Then restart the timer and run a fresh backup:

```sh
sudo systemctl start restic-backups-state.timer
sudo systemctl start restic-backups-state.service
```

Verify the run with `just backups status oci-melb-1` and `just backups logs oci-melb-1`; only then remove the preserved directory or staged copy. The encrypted service file is outside the restic payload: restore the matching SOPS-managed keys through the normal operator workflow, never by reading them manually. Restore the database before rolling back to an older image; changing only the image tag may not reverse a schema migration.

## 4. Acceptance boundary

Before release, the operator verifies private callback login, two distinct provider accounts, per-user board separation, and that the temporary credentials provider is removed. After release, verify the public callback and anonymous denial. The code contract proves routing, secret references, environment composition, and the SQLite export command; it does not substitute for live Homarr login or a restic restore.

## App bookmarks are synced from the web policy

`modules/apps/homarr-apps.nix` keeps Homarr's app inventory in step with
`policy/web-services.nix`. Apps are the tedious part — a name, a URL and an icon
that go stale whenever a route is renamed or a service moves — so they are
derived. Boards are taste: build them in the UI out of the synced apps.

Two policy fields decide what becomes an app:

- `category` — `app` and `admin` routes become apps; `infra` routes are machine
  endpoints (a metrics store, an ingest listener, the cache's write API) and earn
  none.
- `publish` — a withheld route is not served by the edge, so it would be a dead
  app until release.

The `homarr-apps` oneshot converges the instance through the API: apps are
matched by URL, created when missing, and patched when the name or icon drifts.
Nothing is deleted — an app that already existed is your own, and an app whose
route retired may still sit on a board you arranged.

### Minting the API key (once)

The sync authenticates as an administrator, so the key is minted by a person:

1. Sign in to Homarr as the administrator.
2. Open **Authentication → API keys** and create a key. The value has the form
   `<id>.<token>` and is shown once.
3. Add it to the service secret file under the key `api_key`:

       sops secrets/services/homarr.yaml      # add: api_key: <id>.<token>

4. Deploy, or restart the unit on the host:

       systemctl restart homarr-apps
       journalctl -u homarr-apps -n 20

Until `api_key` exists the unit logs that it has nothing to sync and exits
successfully; that is a prepared state, not a failure. A missing key still fails
secret installation, so add it before deploying this host.

An app's icon comes from the dashboard-icons CDN, chosen by service id; where a
project renamed itself, or a route is named for its role (`gatus-admin`), the
slug is listed in `iconSlugs` in the module.
