# Homarr v2 Runbook

Homarr is the user-facing dashboard on `oci-melb-1`, separate from the operator Homepage on `la-admin-1`. Its boards, service tiles, users, groups, and per-user home boards are edited in Homarr; they are not generated from web policy. The public route is `https://home.shrublab.xyz`, but it remains withheld until private OIDC acceptance is complete. Cloudflare Access is off; Homarr's own Kanidm OIDC is the browser gate.

## Status (2026-10-19)

- The module, route, Kanidm client and contract test are in the repository.
- `secrets/services/homarr.yaml` exists.
- **Selected on `oci-melb-1`** with `credentialsBootstrap = true`, pending deploy. Nothing runs yet.
- The route's `publish` posture is `false`; the edge serves no site for it.

The selection and the systemd secret-activation policy (D-097) land in the same deploy, so the installer unit the container orders after exists on the host.

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
  credentialsBootstrap = true;
  secretFiles = {
    host = ../../../secrets/services/homarr.yaml;
    oidc = ../../../secrets/hosts/oci-melb-1/oidc.yaml;
  };
};
```

`credentialsBootstrap = true` is the private bootstrap window; it comes off in the same change that releases the route (step 6 of [section 2](#2-private-first-admin-and-oidc-setup)). Run `just checks all` before deploying; `tests/check-homarr-contract.sh` pins the route, the client and the secret bindings.

## 2. Private first-admin and OIDC setup

The Kanidm client accepts two exact redirect URIs:

- Public: `https://home.shrublab.xyz/api/auth/callback/oidc`
- Private: `https://oci-melb-1.tail0fe19b.ts.net:7575/api/auth/callback/oidc`

The private URI uses the host and port from Homarr's provider endpoint, with `https` because Tailscale Serve terminates TLS.

**Use the full tailnet name, not the short one.** Tailscale Serve terminates TLS with a certificate issued for the node's tailnet FQDN only (`/var/lib/tailscale/certs/oci-melb-1.tail0fe19b.ts.net.crt` on the host), so `https://oci-melb-1:7575/` fails the handshake — the browser reports "Secure connection failed" and curl reports `error:0A000438:SSL routines::tlsv1 alert internal error`. That is the certificate refusing an SNI it does not cover, not a broken proxy; the FQDN with the same port answers. `tailscale serve status` on the host lists the only reachable form. To obtain the current name from the resolved catalog:

```sh
nix eval --raw .#nixosConfigurations.la-admin-1.config.repo.web.catalog.homarr.endpoint.host
```

Homarr's `BASE_URL` depends on `services.homarr.credentialsBootstrap`:

| `credentialsBootstrap` | `BASE_URL` | `AUTH_PROVIDERS` | Use |
| --- | --- | --- | --- |
| `true` | the private Tailscale Serve origin | `credentials,oidc` | private first administrator and OIDC acceptance |
| `false` | the public URL (`home.shrublab.xyz`) | `oidc` | after release |

**The private OIDC login works only while `credentialsBootstrap = true`.** With it `false`, Homarr redirects to the public URL, which the edge withholds. `NEXTAUTH_URL` is intentionally unset so the callback follows the forwarded request host and can use either registered URI.

1. The host record already sets `credentialsBootstrap = true`. Deploy `oci-melb-1` and confirm the route's `publish` is still `false`.
2. From a tailnet-connected browser, open `https://oci-melb-1.tail0fe19b.ts.net:7575/` and create Homarr's first local credentials administrator. This local account is the verified route to administrator; OIDC alone does not grant it.
3. Sign out and sign in with the Kanidm account. Homarr creates a separate OIDC user on first login. From the local administrator, promote that user to administrator in Homarr.
4. Verify a second Kanidm identity creates a separate account and cannot see another user's private board or home-board selection.
5. Remove the temporary local credentials account.
6. Release the route in the same change that sets `credentialsBootstrap = false`:
   - `services.homarr.credentialsBootstrap = false;` in the OCI host composition.
   - `publish = true;` on the `homarr` route in `policy/web-services.nix`. The edge serves a route whose policy `publish` is true (the default), and no aspect has a host-side release switch, so that field is the whole change.
   - Do not leave a public route with credentials enabled.
7. Deploy. Confirm anonymous requests cannot read dashboard content and Kanidm sign-in still works through the public callback. Keep Cloudflare Access disabled; it would interfere with the app's own OIDC flow.

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

Before release, the operator verifies private callback login, two distinct Kanidm users, per-user board separation, and that the temporary credentials provider is removed. After release, verify the public callback and anonymous denial. The code contract proves routing, secret references, environment composition, and the SQLite export command; it does not substitute for live Homarr login or a restic restore.
