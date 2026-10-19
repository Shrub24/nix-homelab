# Actual Budget, Memos and tududi

## Placement and readiness

All three applications are selected on `oci-melb-1`. Actual Budget and Memos use native nixpkgs services; tududi uses a digest-pinned container with loopback port publication. The edge publishes their application-authenticated routes without Cloudflare Access:

| Application | Public URL | Loopback port | Kanidm callback |
| --- | --- | --- | --- |
| Actual Budget | https://budget.shrublab.xyz | 5006 | `/openid/callback` |
| Memos | https://memos.shrublab.xyz | 5230 | `/auth/callback` |
| tududi | https://tududi.shrublab.xyz | 3002 | `/api/oidc/callback/kanidm` |

Implementation is not deployment evidence. Initial login, Memos' provider-file access under its systemd sandbox, and client compatibility still need live verification. The missing tududi secret currently prevents the complete OCI host derivation from evaluating.

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

   Each value must match the corresponding Kanidm OAuth2 client's secret. The identity provider's provisioning source map and the application read the same key. Do not substitute a separate application-side credential.

3. Track the encrypted file and refresh the Git index before evaluation (`git add -A`). Run `treefmt --fail-on-change`, `just checks all` and strict OpenSpec validation. The scaffold test must pass in full; a lazy option probe is not sufficient.

## Rollout

Apply the Kanidm client provisioning on `la-admin-1` before testing application logins, publish the web-policy DNS changes through the existing OpenTofu workflow, then deploy `oci-melb-1`:

```sh
just deploy la-admin-1
just deploy oci-melb-1
```

Check `actual.service`, `memos.service` and `podman-tududi.service` and their journals. Test browser login for each app with an authorized Kanidm user. Also test Actual's sync client and Memos' token/API or mobile access: a browser-only success does not establish client compatibility. Actual keeps password login available because its OpenID integration is upstream preview functionality. Its user provisioning and the inferred RS256 compatibility settings for Actual and tududi require a real login test.

## Memos provider-file acceptance

The provider is delivered as a systemd credential. sops-nix renders `memos-idp-kanidm.json` root-owned under its default `/run/secrets/rendered` directory, and the unit loads it with `LoadCredential=` and binds its credential directory over `/etc/secrets` with `BindReadOnlyPaths=/run/credentials/memos.service:/etc/secrets`. Memos 0.31.0 scans `/etc/secrets` at startup and offers no configurable directory, so the fixed path is preserved inside the unit's namespace while the shared directory keeps its own permissions. The unit orders itself after sops installation, and template rotation requests a service restart.

This replaces an earlier delivery that rendered the provider directly into `/etc/secrets` owned `memos:memos` with mode `0400`. That failed on the first live deployment: `/run/secrets.d/2/rendered` is `root:root 0750`, so the `memos` account could not stat the file. Changing that shared directory's ownership or mode would widen access to every rendered secret, so it is left alone; the credential copy is the isolation boundary. The bind literal is fixed rather than `%d`-expanded because systemd rejected `%d` in `BindReadOnlyPaths` on the OCI host.

After the first deployment:

1. Inspect the credential directory with `systemctl show memos -p LoadCredential` and the unit's namespace with `nsenter`, without printing the file contents. Confirm the provider file is present and owned by the service account.
2. Check `journalctl -u memos` for provider-loading or permission errors. The live transient-unit probe on OCI reproduced an unprivileged read failing and a credential bind reading the provider, under the same sandbox settings the unit uses.
3. Confirm Kanidm appears on the login page and complete a login. Check that the account identifier uses `sub`, and that name and email map correctly. Kanidm does not emit `picture`; an absent avatar is expected.
4. On a later operator-managed credential rotation, confirm the rendered file changes, Memos restarts, and login still works. Do not assume startup loading notices a change without a restart.

### Instance-settings fallback

If the running service cannot load the rendered file, investigate its journal before configuring a second provider. Avoid duplicate providers with the same identity. The fallback is an operator-created OAuth2 provider in Memos' instance settings, using the same client and secret.

Read the non-secret endpoints from the live discovery document at `https://id.shrublab.xyz/oauth2/openid/memos/.well-known/openid-configuration`. Use its authorization, token and userinfo endpoints, client ID `memos`, the matching operator-held client secret, callback `https://memos.shrublab.xyz/auth/callback`, scopes `openid profile email`, and mappings:

| Memos field | Claim |
| --- | --- |
| identifier | sub |
| displayName | name |
| email | email |
| avatarUrl | picture (absent from Kanidm) |

Repeat the login and client checks. This fallback lives in Memos' database, not in the declarative provider file. A bare reimage without restoring that database loses it; restoring the captured database should restore the setting. Record that the fallback was used before treating the deployment as complete.

## State and recovery

State lives under `/srv/data/{actual,memos,tududi}`. State-backups exports Actual's `server-files/account.sqlite`, Memos' `memos_prod.db`, and tududi's `db/production.sqlite3` with read-only `sqlite3 .backup` before restic runs. A missing source fails the capture rather than creating an empty database. Memos' live database and WAL files are excluded from its raw directory copy; tududi's raw capture includes uploads and backups, not its live database directory.

Actual's `user-files` are still copied raw. Their format and consistency under concurrent writes have not been established; do not describe that part as a proven coherent backup. Use the [state restore runbook](state-restore.md), restoring each exported database to its live location while its service is stopped. Verify application data and login after restoration.

Source verification and version-specific details are in [the upstream research brief](../research/actual-memos-tududi-upstream-facts.md). The exposure and identity decision is D-091 in `docs/decisions.md`.
