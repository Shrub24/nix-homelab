# Identity migration: Kanidm → Authentik

Operator steps for moving application SSO from Kanidm to Authentik. The mechanism behind
them — ownership split, flows, the email claim, per-application continuity — is
[`docs/identity.md`](../identity.md); the decision is D-115.

This procedure was written for the window in which Kanidm still served host authentication.
That window closed with D-122, so nothing here restores it; what remains are the steps for
repairing or repeating the application-SSO move.

## Preflight

1. Create `secrets/identity/authentik.yaml` from
   `secrets/.templates/identity/authentik.yaml.j2` and fill in nothing else — mail reuses
   the relay account already in `secrets/applications/admin.yaml`
   ([`authentik-secrets.md`](authentik-secrets.md)).
2. Confirm a test email leaves the host:
   `authentik-manage sendtestemail <your-address>`.
3. Exercise one local admin path per OIDC-enabled application against the continuity table
   in [`docs/identity.md`](../identity.md#account-continuity). Record what you did; this is
   the break-glass path if the cutover fails.

## Stage the candidate

1. Deploy the identity host (`oci-melb-1`). The policy's active provider is still `kanidm`, so application
   identity does not move; the Authentik runtime starts inert and then enables itself once
   its secret file exists.
2. Confirm `authentik` and `authentik-worker` are active and that `homelab-identity`
   reports `successful` in **System > Blueprints**. A mounted file is not proof of
   application.
3. Sign in at the tailnet front as `akadmin` using `authentik_bootstrap_password` from the
   secret file.

## People

Before inviting anyone, confirm **System > Settings > Base URL** reads
`https://auth.shrublab.xyz`. It is seeded from `services.authentik.settings.web.base_url` on
first start and authentik never re-reads the config afterwards, so a value edited here wins
until the setting is cleared; without it, invitation and verification links have no origin.

Seeding and inviting are alternatives per person: enrollment creates the person, so an
invitation for a username that already exists fails.

- **Invited person** — create an invitation in **Directory > Invitations** (choose
  `expires` and `single_use`) and hand over its link:
  `https://auth.shrublab.xyz/if/flow/enrollment/?itoken=<token>`. They set their own
  password, answer **Add a passkey now?** (declining is fine), and confirm their address
  with the emailed code. A passkey declined at enrollment is added later from
  **Settings > MFA Devices > Enroll > Passkey**.
- **Password recovery** — the login page carries the recovery link; anyone signed out can
  also open `https://auth.shrublab.xyz/if/flow/recovery/` directly.
- **Seeded person** — add the entry to `users` in `policy/identity.nix`, deploy, then set
  an initial password in **Directory > Users**. The account stays unverified until it runs
  `https://auth.shrublab.xyz/if/flow/verify-email/`.
- **Break-glass administrator** — keep `akadmin`, set its email, and treat it as
  login-only-when-locked-out. It lives in Authentik's own `authentik Admins` group, which
  stays as upstream created it.

Groups nest, so add a person to the most privileged group they need and they inherit the
rest: `superusers` (administers the provider) → `admins` (operator console apps) →
`service-admins` (user-facing apps) → `users` (every confirmed person, where enrollment
lands). Membership is set in **Directory > Groups**.

Use each person's existing address: continuity is matched on the email claim, so a new
address orphans their application accounts.

### Verifying an address

1. Start login or invitation enrollment and stop at the email-code screen. For an already
   signed-in account, open `https://auth.shrublab.xyz/if/flow/verify-email/`.
2. Read the message on any device and enter its code in the original browser.
3. Confirm enrollment reaches **Email verified**, or login returns to its original destination.
4. Try an incorrect code first on a test account; confirm it does not activate or verify it,
   then submit the correct code.
5. Sign in again and confirm no email code is requested for an unchanged verified address.
6. Change the test account's address and verify it again. Confirm the old address no longer
   reports verified and a fresh code to the new address succeeds.
7. Confirm the record before treating the claim as true:

```sh
ssh oci-melb-1 'sudo -u postgres psql -p 5432 -d authentik -tAc \
  "select username, attributes from authentik_core_user"'
```

`email_verified_address` must equal the account's current `email`; the claim reports true only
while they match, so changing an address un-verifies it until the flow runs again.

### Passkeys

1. Sign in with the existing password and open **Settings → MFA Devices → Enroll → Passkey**.
2. Enroll a synced passkey or compatible security key and give it a recognizable name.
3. In a fresh browser session, use the passkey offered on the identification screen. Confirm
   it signs in without the password and returns to the requested application.
4. Test username and email password sign-in separately; keep both as fallback.
5. Enroll a second passkey or retain tested recovery before removing any existing credential.
6. Record browser/device results before treating passwordless login as accepted.

## Cut over

One window, in this order. The tree already names Authentik (`provider` in
`policy/identity.nix`), so the deploy is the flip.

1. Confirm both hosts are reachable by Tailscale SSH and their static `sshd` keys.
2. Back up the Authentik database, the Kanidm state and each application's own database.
3. `geopulse` on `oci-melb-1`: delete the `authentik` row from the `oidc_providers` table. Its
   client is declared in Nix now, and a database row of the same name shadows the declarative
   configuration, so leaving it means the app keeps the settings it was given in its admin UI.
4. Move the two clients whose configuration lives in their own database — `beszel` and
   `bookorbit` — to the Authentik issuer in each application's own settings, and confirm one
   login each. Nix cannot move them.
5. Deploy the consumer hosts first, then the provider host last: identity carries the blueprint
   whose brand fields change.
6. `./scripts/export-web-services-policy.sh`, then apply OpenTofu — Cloudflare Access
   federation points at the contract's endpoints. The identity suite fails while the two
   disagree, so this cannot be skipped silently.
7. Endpoints come from the contract and change only on redeploy, so every host that serves the
   identity and every host that consumes a client needs its own deploy.
8. Keep the identity host outside Cloudflare Access.
9. Leave `id` where it is: it is the retired provider's issuer, and repointing it moves every
   stored issuer.

## Per-application acceptance

Fill every row before that client is considered migrated. Matching email addresses, client
ids or unchanged secrets do not establish continuity; an empty second account is a failed
migration.

| Client | Existing account | Allowed user | Denied user | Group claim | Rollback |
| --- | --- | --- | --- | --- | --- |
| beszel | | | | n/a | |
| termix | | | | n/a | |
| karakeep | | | | n/a | |
| paperless | | | | `groups` | |
| langfuse | | | | n/a | |
| grafana | | | | `admins` → Admin | |
| actual | | | | n/a | |
| memos | | | | n/a | |
| bookorbit | | | | `groups` | |
| tududi | | | | n/a | |
| geopulse | | | | n/a | |
| homarr | | | | `groups` | |
| cloudflare-access | n/a | | | `groups` | |

Acceptance per client: the existing account still reaches its own data and roles, an
allowed user signs in, a user outside the client's access groups is refused, and the claim
the application maps roles from carries the expected values.

Back up an application's own state before its first new-provider login; reverting the route
does not revert it.

## Host access before cutover

Host login is Tailscale SSH plus the static keys in `sshd`; no identity provider serves it.
Before the flip:

1. From independent sessions, reach `la-admin-1` and `oci-melb-1` by Tailscale SSH.
2. Confirm a key-based `ssh` login on each host, outside Tailscale, as the break-glass path.
3. Keep a console or provider-console route to each host until both are verified after the
   switch.

## Rollback

There is no second provider to fall back to (D-122). Repair in place: restore the Authentik
database from the backup the state-backups contract captures, reapply blueprints, and redeploy
the provider host. Application-side state written during a broken window may not follow, so
restore the application's own backup if it changed materially. The three database-configured
clients need their issuer changed by hand if the public route moves.

## Recovery

Authentik state is the database, persistent assets and the stable secret key and signing
material. Reapplying blueprints restores configuration only — never people, credentials or
memberships. Restore into an isolated target first with mail delivery and consumer effects
disabled, then verify a login there. [`state-restore.md`](state-restore.md) covers the
mechanism.

## Removing Kanidm

Done (D-122). The observation window closed with Authentik serving every client and no host
selecting the Kanidm aspects, so the implementation, its secret rule and its restore helper are
deleted rather than kept dormant. `secrets/identity/kanidm.yaml` remains on disk for the
operator to delete, and one restore of that state should be kept until the change is archived.
