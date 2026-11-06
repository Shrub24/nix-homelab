# Actual Budget, Memos and tududi

## Placement and readiness

All three applications are selected on `oci-melb-1`. Actual Budget and Memos use native nixpkgs services; tududi uses a digest-pinned container with loopback port publication. The edge publishes their application-authenticated routes without Cloudflare Access:

| Application | Public URL | Loopback port | Callback path |
| --- | --- | --- | --- |
| Actual Budget | https://budget.shrublab.xyz | 5006 | `/openid/callback` |
| Memos | https://memos.shrublab.xyz | 5230 | `/auth/callback` |
| tududi | https://tududi.shrublab.xyz | 3002 | `/api/oidc/callback/tududi` |

Implementation is not deployment evidence. Initial login, Memos' provider-file access under its systemd sandbox, and client compatibility still need live verification.

## Operator secret preparation

Only the operator creates or edits encrypted secrets. Do not deploy until both files contain the required keys.

1. Export `TUDUDI_ADMIN_EMAIL` to the intended local recovery account's address, then run:

   ```sh
   just secrets bootstrap secrets/services/tududi.yaml
   sops updatekeys secrets/services/tududi.yaml
   ```

   The template generates `tududi/admin_password` and `tududi/session_secret` and takes `tududi/admin_email` from that environment variable. An omitted address renders empty and disables bootstrap-account creation; it does not create a usable password recovery account. Retain the generated password securely. This is an initial-account bootstrap, not a promise that changing the secret later rotates an existing account's password.

2. In `secrets/hosts/oci-melb-1/oidc.yaml`, provide:

   - `actual/client_secret`
   - `memos/client_secret`
   - `tududi/client_secret`

   Each value must match the corresponding OAuth2 client's secret in the identity provider. Its provisioning source map and the application read the same key. Do not substitute a separate application-side credential.

3. Track the encrypted file and refresh the Git index before evaluation (`git add -A`). Run `treefmt --fail-on-change`, `just checks all` and strict OpenSpec validation. The scaffold test must pass in full; a lazy option probe is not sufficient.

## Rollout

The identity provider runs on `oci-melb-1` beside these applications, so the blueprint that provisions their clients lands in the same deploy. Publish the web-policy DNS changes through the existing OpenTofu workflow, then deploy:

```sh
just deploy oci-melb-1
```

Check `actual.service`, `memos.service` and `podman-tududi.service` and their journals. Test browser login for each app with an authorized identity. Also test Actual's sync client and Memos' token/API or mobile access: a browser-only success does not establish client compatibility. Actual keeps password login available because its OpenID integration is upstream preview functionality. Its user provisioning and the inferred RS256 compatibility settings for Actual and tududi require a real login test.

### Actual account admission

Actual creates a user on first login (`userCreationMode = "login"`), taking the Authentik
`preferred_username` as `user_name`. A refused login answers HTTP 400 with body
`{"status":"error","reason":"openid-grant-failed"}` and writes nothing to the journal — the
unmatched-login path returns from an inner catch — so the server-side evidence is the earlier
`authorize_application` entry naming the Authentik username. That happens when the row exists but
is disabled, or when an existing row was created under a different name. Compare the browser's
Authentik account with `select user_name, enabled from users` in
`/srv/data/actual/server-files/account.sqlite`, read-only.

## Memos provider-file acceptance

The provider arrives as a systemd credential bound at Memos' fixed `/etc/secrets` path; D-091 records why that is the delivery shape. After the first deployment:

1. Inspect the credential directory with `systemctl show memos -p LoadCredential` and the unit's namespace with `nsenter`, without printing the file contents. Confirm the provider file is present and owned by the service account.
2. Check `journalctl -u memos` for provider-loading or permission errors. The live transient-unit probe on OCI reproduced an unprivileged read failing and a credential bind reading the provider, under the same sandbox settings the unit uses.
3. Confirm the identity provider appears on the login page and complete a login. Check that the account identifier uses `sub`, and that name and email map correctly. The provider does not emit `picture`; an absent avatar is expected.
4. On a later operator-managed credential rotation, confirm the rendered file changes, Memos restarts, and login still works. Do not assume startup loading notices a change without a restart.

### Instance-settings fallback

If the running service cannot load the rendered file, investigate its journal before configuring a second provider. Avoid duplicate providers with the same identity. The fallback is an operator-created OAuth2 provider in Memos' instance settings, using the same client and secret.

Read the non-secret endpoints from the live discovery document at `https://auth.shrublab.xyz/application/o/memos/.well-known/openid-configuration`. Use its authorization, token and userinfo endpoints, client ID `memos`, the matching operator-held client secret, callback `https://memos.shrublab.xyz/auth/callback`, scopes `openid profile email`, and mappings:

| Memos field | Claim |
| --- | --- |
| identifier | sub |
| displayName | name |
| email | email |
| avatarUrl | picture (absent from the provider) |

Repeat the login and client checks. This fallback lives in Memos' database, not in the declarative provider file. A bare reimage without restoring that database loses it; restoring the captured database should restore the setting. Record that the fallback was used before treating the deployment as complete.

## State and recovery

State lives under `/srv/data/{actual,memos,tududi}`. State-backups exports Actual's `server-files/account.sqlite`, Memos' `memos_prod.db`, and tududi's `db/production.sqlite3` with read-only `sqlite3 .backup` before restic runs. A missing source fails the capture rather than creating an empty database. Memos' live database and WAL files are excluded from its raw directory copy; tududi's raw capture includes uploads and backups, not its live database directory.

Actual's `user-files` are still copied raw. Their format and consistency under concurrent writes have not been established; do not describe that part as a proven coherent backup. Use the [state restore runbook](state-restore.md), restoring each exported database to its live location while its service is stopped. Verify application data and login after restoration.

Source verification and version-specific details are in [the upstream research brief](../research/actual-memos-tududi-upstream-facts.md). The exposure and identity decision is D-091 in `docs/decisions.md`.
