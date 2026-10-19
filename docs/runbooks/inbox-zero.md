# Inbox Zero

Inbox Zero runs on `oci-melb-1` for one personal Gmail account. It is served at `https://inbox.shrublab.xyz` as a direct OCI route with Cloudflare Access and application OIDC off; Google sign-in is the application gate. Its database is the fleet's native PostgreSQL substrate, and its model calls go to the colocated Bifrost gateway.

The Inbox Zero service is deployed on `oci-melb-1`. The encrypted service file and Google resources are prepared. This runbook records their setup and the remaining live acceptance; do not treat deployment as complete until the application, Google sign-in, Pub/Sub delivery, and maintenance calls have been verified.

## Google resources

Use one Google Cloud project for the OAuth client and the Gmail topic. Enable the Gmail API and the Pub/Sub API.

### OAuth client

Create a Web application OAuth client with these exact redirect URIs:

- `https://inbox.shrublab.xyz/api/auth/callback/google`: sign-in and first Gmail authorization.
- `https://inbox.shrublab.xyz/api/google/linking/callback`: linking another Google mailbox. Register it even for a single mailbox, as upstream's setup guide does.

Request these scopes: `userinfo.profile`, `userinfo.email`, `gmail.modify` and `gmail.settings.basic`. The Gmail scopes are restricted. Contacts, calendar and Drive scopes stay disabled.

Record the client ID and client secret for the bootstrap step below. Do not paste them into shell history or tickets.

### Consent mode

A Google OAuth app in **Testing** expires Gmail-scoped refresh tokens after seven days. Testing is acceptable for the setup window only. It is not an unattended operating configuration.

The production consent choice for personal use is deferred. Keep the app in Testing while preparing and testing the integration; use the production procedure below when you are ready to switch.

#### Test users (while the app is in Testing)

In the Google Cloud project, open **Google Auth Platform → Audience → Test users → Add users** (the older console calls this **OAuth consent screen → Test users**). Add every Google account that needs to sign in while the app remains in Testing. Google allows up to 100 test users in this state; accounts not on the list are blocked by Google before reaching Inbox Zero.

There is a second, independent allowlist in Inbox Zero. Add the same sign-in addresses to `inbox-zero.auth_allowed_emails` in the encrypted service file, comma-separated, for example `first@gmail.com,second@gmail.com`. The pinned Inbox Zero code parses this variable as a comma-separated list and rejects new account creation for addresses outside it. This is a sign-up gate, not a revocation mechanism for accounts already created. Edit the encrypted file with `sops`, not by printing decrypted values. The Google test-user list permits the OAuth flow; Inbox Zero's allowlist permits account creation. Both must include the user.

Adding a different Gmail mailbox for an existing Inbox Zero account is a separate mailbox-linking operation; add that Google identity to Test users while still in Testing, but do not add it to the Inbox Zero sign-in allowlist unless that person should also have an Inbox Zero account.

Test-user membership does not extend token lifetime. Refresh tokens issued in Testing still expire after seven days.

#### Personal-instance production setup (deferred until the operator is ready)

For fewer than 10 users, Google's current policy says personal-use apps with fewer than 100 users can be used without completing OAuth verification; users may see an unverified-app warning. This is not the same as Testing mode, and it is not a Google review or approval of this particular application. Google's policy and UI can change, so confirm the current requirements in the project before proceeding.

When ready:

1. Confirm the app's audience is **External** and the requested scopes are only those required for Inbox Zero (including `gmail.modify` and `gmail.settings.basic`).
2. In **Google Auth Platform → Audience**, select **Publish app** (older console: **Push to production**). Do not submit a verification request for the personal-use path unless Google requires it or the app's use grows beyond the stated exemption.
3. In production, the Google Test users list is no longer the gate; Google OAuth may be initiated by Google accounts generally. Inbox Zero's `auth_allowed_emails` setting blocks account creation for addresses not on the list, but does not revoke accounts already created. Add only intended new Inbox Zero users there before their first sign-in.
4. Users may see an unverified-app warning and need to choose **Advanced → Go to Inbox Zero (unsafe)**. Google's personal-use guidance applies below 100 users; do not treat that as an unlimited user allowance.
5. Revoke and re-authorize any Gmail grant created in Testing. A refresh token minted in Testing keeps its seven-day expiry. Verify the new grant and confirm Gmail watch renewal continues beyond the old token's expiry window.

References: [Google: Manage app audience](https://support.google.com/cloud/answer/15549945), [Google: When is verification not needed](https://support.google.com/cloud/answer/13464323), and [Google: OAuth 2.0 refresh-token behavior](https://developers.google.com/identity/protocols/oauth2).

### Pub/Sub topic and publisher grant

Create a topic and record its full name, `projects/<project-id>/topics/<topic-id>`. Grant Gmail's push publisher identity the publisher role on that topic:

```sh
gcloud pubsub topics add-iam-policy-binding <topic-id> \
  --project <project-id> \
  --member=serviceAccount:gmail-api-push@system.gserviceaccount.com \
  --role=roles/pubsub.publisher
```

### Push subscription

Create a push subscription with no push authentication and the default wrapped delivery. The shared token is the only check on this route, so it must be the value stored under `pubsub_verification_token` in the encrypted file. Read it into a shell variable from the encrypted file, without echoing it, on the operator workstation:

```sh
TOKEN="$(sops decrypt --extract '["inbox-zero"]["pubsub_verification_token"]' secrets/services/inbox-zero.yaml)"
gcloud pubsub subscriptions create inbox-zero-push \
  --topic <topic-id> \
  --project <project-id> \
  --push-endpoint="https://inbox.shrublab.xyz/api/google/webhook?token=${TOKEN}"
unset TOKEN
```

Run this only on a trusted operator workstation with shell tracing disabled: the expanded push URL is visible in the `gcloud` process arguments and is stored in the subscription configuration. It is not a public or log-safe URL.

The route returns 503 when the verification-token setting is absent and 403 when a configured token does not match. An explicitly empty setting disables checking, which is why the template generates a nonempty value and startup validation must reject an empty one.

Google cannot supply a Cloudflare Access identity, so this route must stay outside Access. The `inbox-zero` route is configured that way in `policy/web-services.nix`.

### Query-token logging risk

The push URL carries the verification token in its query string. Any access log that records full request URLs, including Caddy access logs and any Cloudflare or Google log product, can store that token. Caddy does not write HTTP access logs unless a site or server enables the `log` directive, and this repository's edge Caddyfile emits none, so the token is not logged today. Caddy's `log` filter can redact it if access logging is ever enabled: `request>uri query { replace token REDACTED }` inside the `format filter` block. Before the subscription goes live, confirm on the rendered proxy configuration that no `log` directive applies to the Inbox Zero route, and restrict any external log product the same way. Task 3.2 verifies the rendered Caddy configuration. If you rotate the verification token, update the subscription's endpoint at the same time.

## Secret preparation

Only the operator creates or edits encrypted secrets. The template generates the database password, the auth and email-encryption material, the Pub/Sub token, the cron secret and the internal API key. It does not generate the Google credentials.

1. Export the two non-secret inputs. Use the full topic name from the Pub/Sub step and the single Gmail address allowed to sign in:

   ```sh
   export INBOX_ZERO_PUBSUB_TOPIC='projects/<project-id>/topics/<topic-id>'
   export INBOX_ZERO_ALLOWED_EMAIL='<operator gmail address>'
   ```

   Without an allowlisted address, sign-in is not restricted to the operator. Do not deploy with an empty allowlist.

2. Bootstrap the file, then add the recipients the `.sops.yaml` rule names:

   ```sh
   just secrets bootstrap secrets/services/inbox-zero.yaml
   sops updatekeys secrets/services/inbox-zero.yaml
   ```

3. As the operator, open the encrypted file with SOPS and fill `inbox-zero.google_client_id` and `inbox-zero.google_client_secret` in its editor. Do not put their values in command arguments or shell history:

   ```sh
   sops secrets/services/inbox-zero.yaml
   ```

4. The file's `sops:` metadata should list only the owner and `oci-melb-1` age recipients. Run `sops updatekeys` again after any recipient change. Do not print decrypted values into logs or tickets.

The encrypted file is present and bound on `oci-melb-1`; these bootstrap steps are retained for recovery or deliberate re-bootstrap. Do not re-bootstrap merely to add a user, because that regenerates other credentials. Use `sops` to edit only the comma-separated `auth_allowed_emails` value, then deploy the updated configuration.

## Database migrations

The image runs `prisma migrate deploy` at container start. Upstream's
`start.sh` logs a failure and starts the app anyway, so a stuck migration looks
like a healthy container serving a partial schema — the failure surfaces later as
HTTP 500 from whichever endpoint touches a missing table.

That happened once. Migration `20240116235134_shared_premium` ends with
`DROP EXTENSION "uuid-ossp"`, and only the creating role may drop an extension.
The substrate's `setupSQL` had created it as the cluster superuser, so the
migration failed with `must be owner of extension uuid-ossp` (SQLSTATE 42501).
Prisma then refuses every later migration, and the schema froze at 2024-01: the
`EmailAccount` and `ScheduledAction` tables never appeared, so
`inbox-zero-watch-renewal` and `inbox-zero-scheduled-actions` failed with
`curl: (22) … 500`.

The substrate no longer installs `uuid-ossp` for this consumer; the migration
creates it as the database-owning role (it is a trusted extension) and drops it
again. The only extension the substrate installs is `btree_gist`.

### Diagnosing a stuck schema

```sh
# What actually failed, and what is still unresolved
sudo -u postgres psql -d inbox_zero -Atc "select migration_name, finished_at, rolled_back_at, left(coalesce(logs,''''), 400) from _prisma_migrations where finished_at is null"
sudo -u postgres psql -d inbox_zero -Atc "select count(*) from _prisma_migrations where finished_at is not null"
# The container's own view of the last attempt
sudo podman logs --tail 400 inbox-zero | grep -iE 'migrat|prisma|error'
```

### Recovering a failed migration

Prisma will not retry past a failed row until it is marked rolled back, and the
extension ownership has to be right before the retry can drop what it created.

```sh
# 1. Let the app role own what its migration must drop (superuser, not the app role).
sudo -u postgres psql -d inbox_zero -c 'DROP EXTENSION IF EXISTS "uuid-ossp";'

# 2. Mark the failed attempt rolled back, from inside the container.
sudo podman exec -w /app inbox-zero prisma migrate resolve --rolled-back <migration_name> \
  --config=/app/docker/scripts/prisma.config.ts --schema=./apps/web/prisma/schema.prisma

# 3. Restart so start.sh re-runs migrate deploy.
sudo systemctl restart podman-inbox-zero.service

# 4. Confirm it finished: the log ends with "All migrations have been successfully applied."
sudo podman logs --tail 400 inbox-zero | grep -E 'migrations|error'
sudo -u postgres psql -d inbox_zero -Atc "select count(*) from _prisma_migrations where finished_at is not null"
```

A migration set of this size takes longer than a minute on `oci-melb-1`; check the
container log rather than querying the table a few seconds after the restart.
Then run both maintenance units and confirm `Result=success`:

```sh
sudo systemctl reset-failed inbox-zero-watch-renewal.service inbox-zero-scheduled-actions.service
sudo systemctl start inbox-zero-watch-renewal.service inbox-zero-scheduled-actions.service
```

Before recovering a database that holds real mail metadata, take a
`pg_dumpall` export first: these are forward migrations, and a Nix generation
rollback does not undo them.
