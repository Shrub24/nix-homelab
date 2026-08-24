# State Restore Runbook

Canonical restore path for host state backed up by `services.state-backups` (restic) on `la-admin-1` and `oci-melb-1`. All restores are staged first; restic output is never written directly into `/`.

## 1. Hard safety rules

- never restore restic output directly into `/` — always stage first with `just backups restore-stage <host> <snapshot> <absolute-include-path>`
- record before starting: source host/repository, snapshot ID and time, included path, artifact version
- stop the service's writers and the backup timer before applying; preserve current state by rename or copy, never by immediate delete
- never read or decrypt secrets manually; sops + NixOS re-materialize them at activation/service start
- keep the staged copy and the snapshot until the restored state has soaked and a fresh verified backup exists

## 2. Choose a snapshot and stage it

Backup failures surface through the fleet notification pipeline. Confirm the last good run before trusting a snapshot:

```sh
# operator workstation
just backups status <host>      # treats a completed successful run as healthy
just backups logs <host>
```

List snapshots on the target host. The deployed `restic-state` wrapper carries the repository, credential file, and password file from the backup unit, so no manual credential handling is needed:

```sh
# target host
restic-state snapshots
restic-state ls <snapshot>
```

Stage exactly one included path. The recipe runs on the operator workstation and executes the restore on the target host; the path it prints exists **on the target host**:

```sh
# operator workstation
just backups restore-stage <host> <snapshot> <absolute-include-path>
# → prints: state-restore-stage: restored to /var/tmp/state-restore/restore.ab12cd
```

Then SSH to the target host and set the staged path there. Every apply step in this runbook runs in that target-host shell:

```sh
# target host
just ops ssh <host>                            # interactive SSH as dev
stage=/var/tmp/state-restore/restore.ab12cd    # the path the recipe printed on this host
```

The recipe never writes live state; applying staged files to live paths is always the separate, per-service step below. Each service section shows its stage command (operator workstation) followed by the apply block (target host), which starts by setting `stage` (or `raw`/`exp`) to the path the recipe printed for that stage.

## 3. Common apply sequence

1. Quiesce — stop the service's writers plus `restic-backups-state.service` and `restic-backups-state.timer`; verify each is inactive before continuing.
2. Stage — run `just backups restore-stage` on the workstation, note the printed path, and set `stage=` on the target host (section 2).
3. Verify the artifact — `gzip -t`, `PRAGMA integrity_check`, or checksum as listed per service.
4. Preserve current state — move the live directory aside; never delete it first.
5. Apply with the service's ownership.
6. Start in dependency order (identity → data → consumers).
7. Validate the service and its data.
8. Keep the fallback (preserved dir, staging dir, snapshot) until soak is complete.

## 4. Kanidm (la-admin-1)

Artifact: portable export `backup-*.json.gz` from `/var/lib/kanidm/backups`. Export-only contract: the live DB (`/var/lib/kanidm/kanidm.db`) is not restic-covered.

Stage (operator workstation):

```sh
just backups restore-stage la-admin-1 <snapshot> /var/lib/kanidm/backups
```

Quiesce and apply (target host):

```sh
sudo systemctl stop kanidm.service restic-backups-state.service restic-backups-state.timer
stage=/var/tmp/state-restore/restore.<id>                    # path the recipe printed on this host
backup=$(ls -1t "$stage/var/lib/kanidm/backups"/backup-*.json.gz | head -n1)
sudo systemctl start "$(systemd-escape --path --template=kanidm-restore@.service "$backup")"
```

- The helper restores the artifact, runs the offline verifier fail-closed, and fixes ownership. It refuses to run while `kanidm.service` is active and never starts it.
- Every nonzero verifier result is fatal — never parse, "repair", or accept a verifier failure; the helper exits nonzero before any ownership repair or service start.
- Only after the helper reports done: `sudo systemctl start kanidm.service`
- Validate: admin login, one OIDC client login, provider discovery URL resolves.

## 5. PostgreSQL shared cluster (oci-melb-1)

Artifact: logical cluster export `all.sql.gz` at `/srv/data/state-backups/postgres` produced by NixOS `services.postgresqlBackup` (a previous-good copy is retained locally as `all.prev.sql.gz`). The raw `/srv/data/postgres` directory is NOT portable backup coverage.

DB consumers on OCI: `niks3.service`, `paperless-*.service`, `podman-audiomuse-*.service`; litellm is an off-host consumer — pause its writers manually.

Stage (operator workstation):

```sh
just backups restore-stage oci-melb-1 <snapshot> /srv/data/state-backups/postgres
```

Quiesce, verify, and apply (target host):

```sh
stage=/var/tmp/state-restore/restore.<id>                    # path the recipe printed on this host

# 1. quiesce consumers before PostgreSQL
sudo systemctl stop niks3.service 'paperless-*.service' 'podman-audiomuse-*.service'
sudo systemctl stop postgresql.service restic-backups-state.service restic-backups-state.timer

# 2. verify the staged artifact
gzip -t "$stage/srv/data/state-backups/postgres/all.sql.gz"

# 3. preserve current state, then initialize an empty cluster of the configured
#    (same-or-newer) major version. The module preStart runs initdb when the
#    data directory is absent; do not start postgresql.target yet, so its setup
#    service does not pre-create roles/databases that collide with the dump.
sudo mv /srv/data/postgres /srv/data/postgres.pre-restore-$(date +%s)
sudo systemctl start postgresql.service

# 4. load the logical cluster export as postgres. pg_dumpall recreates roles and
#    databases itself; do NOT add --single-transaction — cluster roles and
#    per-database ownership restore object-by-object.
sudo sh -c "gzip -dc '$stage/srv/data/state-backups/postgres/all.sql.gz' | sudo -u postgres psql -X -d postgres"

# 5. restart so the module postStart re-applies the SOPS-managed role passwords
#    (audiomuse, litellm), then start consumers in dependency order
sudo systemctl restart postgresql.service
sudo systemctl start niks3.service 'paperless-*.service' 'podman-audiomuse-*.service'
```

Validate (target host):

```sh
sudo -u postgres psql -tAc "SELECT datname FROM pg_database ORDER BY 1"
sudo systemctl --no-pager --full status postgresql.service
```

plus service-level checks: paperless UI login, AudioMuse setup state intact, niks3 push/read. Note: per-database snapshots in a logical cluster export are internally consistent but not synchronized across databases; the fleet has no cross-database transactions, so this is acceptable.

## 6. Vaultwarden (la-admin-1)

Artifact: raw service path `/srv/data/vaultwarden` plus a consistent SQLite export at `/srv/data/state-backups/vaultwarden/db.sqlite3`. Prefer the export for the database.

Stage both paths (operator workstation):

```sh
just backups restore-stage la-admin-1 <snapshot> /srv/data/vaultwarden
just backups restore-stage la-admin-1 <snapshot> /srv/data/state-backups/vaultwarden
```

Quiesce, verify, and apply (target host):

```sh
sudo systemctl stop vaultwarden.service restic-backups-state.service restic-backups-state.timer
raw=/var/tmp/state-restore/restore.<id1>                    # paths the recipe printed on this host
exp=/var/tmp/state-restore/restore.<id2>

# verify the export
sqlite3 "$exp/srv/data/state-backups/vaultwarden/db.sqlite3" "PRAGMA integrity_check;"   # expect: ok

# preserve current state
sudo mv /srv/data/vaultwarden /srv/data/vaultwarden.pre-restore-$(date +%s)
sudo install -d -o vaultwarden -g vaultwarden -m 0750 /srv/data/vaultwarden

# apply: raw files (attachments, rsa keys, config) first, then the consistent export DB on top
sudo cp -a "$raw/srv/data/vaultwarden/." /srv/data/vaultwarden/
sudo cp "$exp/srv/data/state-backups/vaultwarden/db.sqlite3" /srv/data/vaultwarden/db.sqlite3
sudo chown -R vaultwarden:vaultwarden /srv/data/vaultwarden

sudo systemctl start vaultwarden.service
```

Validate: log in with an existing account, read an attachment, check the admin panel.

## 7. Beszel hub (la-admin-1)

Artifact: the real DynamicUser path `/var/lib/private/beszel-hub` (never the compatibility symlink `/var/lib/beszel-hub`).

Stage (operator workstation):

```sh
just backups restore-stage la-admin-1 <snapshot> /var/lib/private/beszel-hub
```

Quiesce and apply (target host):

```sh
sudo systemctl stop beszel-hub.service restic-backups-state.service restic-backups-state.timer
stage=/var/tmp/state-restore/restore.<id>                    # path the recipe printed on this host

sudo mv /var/lib/private/beszel-hub /var/lib/private/beszel-hub.pre-restore-$(date +%s)
sudo cp -a "$stage/var/lib/private/beszel-hub" /var/lib/private/beszel-hub
sudo chown -R nobody:nogroup /var/lib/private/beszel-hub   # DynamicUser posture outside the unit namespace; systemd re-owns the StateDirectory at start

sudo systemctl start beszel-hub.service
```

If the module's ownership behavior differs from the `nobody:nogroup` posture, follow the module-declared ownership instead. Validate: the hub presents the configured admin/OIDC settings (not first-run defaults) and existing agents reconnect.

## 8. ntfy (la-admin-1)

No restic restore. Auth users/tokens are declarative SOPS input and `auth.db` is recreated from them; cache/history/attachments are accepted ephemeral state (there are no attachments today). If attachments become authoritative, add their real path to restic before enabling them.

Recreate auth (target host):

```sh
sudo systemctl stop ntfy-sh.service restic-backups-state.service restic-backups-state.timer
sudo rm -f /srv/data/ntfy/auth.db   # stale auth.db breaks declarative reprovisioning (UNIQUE-token failure); recreate, never merge
sudo systemctl start ntfy-sh.service
```

Validate: each host's notification publish succeeds (e.g. an OCI `notify` call reaches LA ntfy) and the public route still works.

## 9. File-state services

Restore by staging the path (operator workstation), then on the target host preserving the live copy, applying with the listed ownership, and starting the listed writers. Validate each service after start.

| Path (restic include) | Writer units to stop | Apply / ownership | Validate |
|---|---|---|---|
| `/srv/data/termix` | `podman-termix.service`, `podman-guacd.service` | `chown -R root:root`, mode 0750 | Termix UI over Tailscale; guacd healthy |
| `/var/lib/cockpit-loopback-tls` | `cockpit.socket`, `cockpit.service` (material service regenerates only if files are absent) | `chown -R root:root`, mode 0700 | Cockpit over https still trusts the loopback CA; Caddy reads `/etc/cockpit/loopback-ca.crt` |
| `/srv/data/syncthing` | `syncthing.service` | `chown -R syncthing:syncthing` | folder state Healthy |
| `/srv/data/navidrome` | `navidrome.service`, `navidrome-scan.service` | `chown -R navidrome:navidrome` | library/quarantine present; scan completes |
| `/srv/data/beets` | `beets-*.service`, `beets-*.timer`, `beets-*.path` | `chown -R beets:beets` | `beet info` resolves; runners start clean |
| `/srv/media/library`, `/srv/media/quarantine` (excl. `.versions`) | `syncthing.service`, `navidrome.service`, `podman-tagr.service`, `slskd.service`, `beets-*` units, `ffmpeg-preprocess.service` + inbox path units; `traktor-m3u-sync-*` when enabled | keep group/ACL layout from the snapshot, then `sudo systemctl start media-permission-reconcile.service` to re-apply module ACLs | syncthing folder Healthy; navidrome reflects files |
| `/srv/data/paperless`, `/srv/data/paperless/media`, `/srv/data/paperless/consume` | `paperless-*.service` | `chown -R paperless:paperless` | UI login; document count matches pre-restore |
| `/srv/data/paperless-gpt-llm` (+ docling dir when enabled) | `podman-paperless-gpt-*.service` | `chown -R root:root`, mode 0750 | paperless-gpt API/status responds; tags route |
| `/srv/data/karakeep` | `podman-karakeep-web.service`, `podman-karakeep-meilisearch.service`, `podman-karakeep-chrome.service`, `podman-network-karakeep-net.service` | `chown -R root:root`, mode 0750 | login works; meilisearch reindexes from the app DB |
| `/srv/data/bifrost/app` (logs/cache/vector excluded) | `podman-bifrost.service`, `bifrost-config.service` | `chown -R 1000:1000` | `/v1/models` responds |
| `/srv/data/phoenix` | `podman-phoenix.service`, `phoenix-prune.service`, `phoenix-prune.timer` | `chown -R root:root` | UI loads; spans queryable |
| `/srv/data/tagr` (+ export `/srv/data/state-backups/tagr/tagr.sqlite3`) | `podman-tagr.service` | `chown -R root:root`, mode 0750 | prefer the SQLite export; `PRAGMA integrity_check` → ok; login works |

Notes:

- Bifrost: `bifrost-config.service` regenerates `config.json` from repo input and deletes `config.db` at start — restore the app data first, then start it; do not expect `config.db` to survive.
- Karakeep: object assets in its external R2 bucket are NOT in restic; restore them from R2/their external authority separately (external recovery dependency, no replication/versioning claimed).
- Paperless data also lives in the shared PostgreSQL cluster — restore PostgreSQL (section 5) as part of a Paperless restore.

Not restored from restic (explicitly excluded, reproducible or external): ntfy (section 8), slskd local DB/history, Beszel agent state, ACME/Caddy state, AudioMuse Redis/temp state (authority is PostgreSQL), Karakeep R2 assets.

## 10. Rollback and cleanup

- If validation fails: restore the preserved pre-restore copy (`sudo rm -rf <live>` then `sudo mv <live>.pre-restore-* <live>`), start the old state, and investigate before retrying.
- Keep the staging directory and the snapshot until the restored state has soaked and a fresh verified backup exists; only then remove the staging directory (target host):

```sh
sudo rm -rf /var/tmp/state-restore/<id>
```

- After a successful restore, capture a fresh backup: `just backups run <host>` then `just backups status <host>`; retain the restored-from snapshot until that backup is verified.
- Record: source host/repository, snapshot ID/time, staged path, applied artifact version, validation results.
