# SparkyFitness runbook

Deployment and recovery of the SparkyFitness instance on `oci-melb-1`. What it is and how it is wired: `docs/sparkyfitness.md`.

## 1. Preflight

- `policy/oci-images.nix` carries `sparkyFitness` and `sparkyFitnessServer`, both `docker.io/codewithcj/*` tag and digest pinned. Renovate proposes bumps.
- `policy/web-services.nix` declares the `sparkyfitness` route (`fit` subdomain, `direct`, port 3105) and `policy/identity.nix` declares the `sparkyfitness` client with callback `/api/auth/sso/callback/authentik`.
- Without `secrets/services/sparkyfitness.yaml` the host does not evaluate: the failure names that path. Create the file in the next step before deploying.

## 2. Create the secret

```sh
just secrets bootstrap secrets/services/sparkyfitness.yaml
just secrets updatekeys secrets/services/sparkyfitness.yaml
```

The template generates both database passwords, the 64-hex encryption key and the session secret.

The OIDC client secret is not in that file: it belongs with the host's other client secrets, in
`secrets/hosts/oci-melb-1/oidc.yaml`, which the identity provider also reads. That file already
exists, so add the block rather than re-bootstrapping it — a re-bootstrap rotates every client
secret on the host:

```sh
sops edit secrets/hosts/oci-melb-1/oidc.yaml
# sparkyfitness:\n#   client_secret: <48 hex characters>
```

Verify the generated value is 64 hex characters before deploying:

```sh
sops decrypt --extract '["app"]["encryption_key"]' secrets/services/sparkyfitness.yaml | wc -c   # 64
```

## 3. Deploy

```sh
git add -A                    # `.#` reads the Git index
just deploy oci-melb-1
```

The deploy creates both database roles, applies their passwords, runs the setup SQL, and starts the two containers. The backend applies its schema migrations on first start, which is why its start budget is 300s.

## 4. Acceptance

| Check | Command or action | Pass |
| --- | --- | --- |
| Units clean | `ssh oci-melb-1 'systemctl --failed --no-legend; podman ps --format "{{.Names}} {{.Status}}"'` | no failed units; both containers up, backend reports `(healthy)` |
| Edge route | `curl -sI https://fit.shrublab.xyz` | `200` |
| Sign-in | open the origin, sign in | redirected to the identity provider, returned with a session |
| Administrator | sign in as a `service-admins` member | admin panel reachable |
| Isolation | `ssh oci-melb-1 'PGPASSWORD=$(sops …) psql -h 127.0.0.1 -U sparkyfitness_app -d sparkyfitness -c "CREATE ROLE x"'` | refused |
| Upload | create an entry with an uploaded file | file appears under `/srv/data/sparkyfitness/uploads` |
| Backup | `just backups run oci-melb-1` then `just backups status oci-melb-1` | run succeeds; snapshot includes `srv/data/sparkyfitness/uploads` |

Record the acceptance result on the change, not in this file.

## 5. Break-glass

The application's password login is hidden while the identity provider is the sign-in path. The
retained local administrator is a password account with `services.sparkyfitness.adminEmail` set.

1. In `modules/hosts/oci-melb-1/_nixos.nix`, where the host binds `sparkyfitness.secretFiles.oidc`, add
   `sparkyfitness.disablePasswordLogin = false;` and `sparkyfitness.adminEmail = "<the account's address>";`.
   If no local account exists yet, create one through the application's sign-up form once the deploy
   lands.
2. `just deploy oci-melb-1`, then sign in with that account at `https://fit.shrublab.xyz`.
3. When the identity provider is back, delete the override, deploy again, and confirm the hidden
   login form has returned.

## 6. Restore

Restores follow `docs/runbooks/state-restore.md`. Two parts, both required:

1. The database: restore the substrate export (`postgres` directory in the snapshot) and load it with
   `psql` as the cluster superuser. Roles and databases are recreated by the dump, so the consumer
   registry and `pg_hba` must already match the deployed generation.
2. Uploaded files: stage `/srv/data/sparkyfitness/uploads` from the same snapshot with
   `just backups restore-stage oci-melb-1 <snapshot> srv/data/sparkyfitness/uploads`.

`app/encryption_key` must be the key from the deployment that wrote the data, otherwise stored
integration credentials decrypt to nothing. If the key cannot be recovered, treat integrations as
lost and re-enter them.

Because the database and the uploads are captured at different moments, verify a record's upload
after a restore; a record whose upload predates the file capture is the expected gap.

## 7. Rollback

`just deploy` rolls back a failed activation automatically. To retire the instance without losing
data: remove `sparkyfitness` from the host record's aspects, deploy, then take a final backup before
deleting `/srv/data/sparkyfitness` and the `sparkyfitness` database by hand.
