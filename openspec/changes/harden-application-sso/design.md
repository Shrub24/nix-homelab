# Design

## Context

See `proposal.md` for motivation and `specs/application-sso/spec.md` for the behavior contract. The canonical OIDC URI contract remains unchanged (`openspec/specs/provider-owned-oidc-uris/spec.md`).

All twelve active OIDC discovery documents currently return HTTP 200. That establishes endpoint reachability only, not authorization, callback exchange, or account resolution. The existing Actual Budget failure is after token and user-info requests succeed: its deployed user lookup uses `preferred_username`, which is `saurabhj`, while the existing account row is named `saurabhj@id.shrublab.xyz`. The failure is an identity-continuity issue, not discovery or client-secret failure. The Langfuse OAuth error has not yet been tied to a specific stage; no correlated log entry was available in the inspected window, so it must be reproduced with a timestamp and application/provider logs.

The deployed Memos package is 0.31.0. Its release documentation supports file-backed `ACCESS` and `GENERAL` settings through the existing `/etc/secrets` loader. `ACCESS=PRIVATE` blocks anonymous instance browsing but preserves explicit memo share links. The pinned Langfuse image is 4.70.0; its source supports `AUTH_DISABLE_USERNAME_PASSWORD`, which rejects username/password sign-in and password-reset email codes while leaving configured SSO providers available. `AUTH_DISABLE_SIGNUP` also blocks first-time account creation through SSO, so it is not part of this change unless testing proves it necessary and the account migration is resolved.

## Goals / Non-Goals

**Goals:**

- Make Authentik OIDC the only supported interactive login for active native OIDC clients where the app has a supported local-auth control.
- Preserve existing application account IDs and owned data through identity-provider cutover.
- Make Memos private to signed-in users while retaining explicit shares.
- Identify OIDC as Shrublab and align the desktop dashboard list view without changing protocol identity or mobile/grid behavior.
- Diagnose actual login behavior, not just discovery documents.

**Non-Goals:**

- No new Cloudflare Access proxying, public-route, client-ID, callback, issuer, or token-claim changes.
- No blanket SSO claim for applications without a native Authentik client (Inbox Zero's Google integration remains an explicit exception).
- No Authentik frontend patch, local database edit, secret rotation, or deployment in this change.
- No disabling local authentication until that app's OIDC login and account resolution are proven.

## Decisions

### SSO enforcement is per application and follows successful acceptance

Keep each application's existing OIDC configuration and canonical endpoints. Disable its supported local username/password or email path only after an end-to-end login reaches the intended existing account. Do not use discovery HTTP 200 as acceptance. For Langfuse, reproduce the failure with a timestamp, inspect the app and Authentik logs through the authorization, callback, and account-link stages, then test the existing account. Do not set `AUTH_DISABLE_SIGNUP`: it blocks first-time SSO account creation as well as local signup. Do not enable dangerous email-based account linking without a separate review; prefer the application's supported account-linking path.

**Actual Budget gate:** preserve the existing user and data. First establish a supported, account-preserving way to make the legacy `user_name` resolve from Authentik's `preferred_username=saurabhj`; confirm an OIDC login reaches the same user ID. Keep password login available until then. Do not change the fleet-wide `preferred_username` claim to match the legacy SPN and do not update the live SQLite database directly. If no supported migration path exists, stop before removing the fallback and ask for approval before considering a database-level migration.

### Memos access policy uses its pinned file-backed settings

Render Memos 0.31's supported instance settings for private access and disabled password authentication, alongside the existing OIDC provider file. Preserve the current narrow credential namespace: the service receives only the provider and settings files at `/etc/secrets`, not the host's general secret directory. The files override instance settings at startup without editing the database. Keep registration behavior that OIDC requires; do not disable first-time OIDC account creation by assumption. Private mode does not revoke explicit share links, which the user has chosen to preserve.

### Use the OIDC provider label, not client identity, for branding

Change the shared provider display name from `Authentik` to `Shrublab`. This value feeds app-facing labels (for example, Langfuse's custom-provider name and Memos' provider name). Keep the `memos` provider UID/client ID and every client ID, issuer, callback and claim unchanged. `client.displayName` remains the application tile name, not the sign-in provider label.

### Keep dashboard CSS narrowly scoped

Change the existing desktop list-view container from a centered column to left alignment at desktop widths. Leave row sizing, grid mode, mobile layout, and the shared glass-surface rules untouched. Verify the selector against the pinned Authentik frontend and the existing browser fixture; do not introduce a frontend bundle patch.

## Risks / Trade-offs

- **[Risk] Actual's legacy account cannot be linked through a supported app path** → Keep password fallback and stop the SSO-only cutover; ask before any SQLite-level identity migration.
- **[Risk] Langfuse's OAuth error has a different root cause or its existing account does not auto-link** → Correlate a fresh attempt with logs and prove account continuity before enabling its SSO-only setting; do not enable dangerous auto-linking by default.
- **[Risk] Memos' settings file is not visible inside the service sandbox or its upgrade path changes** → Verify the rendered credential mount and the live anonymous/read and login behavior before considering the deployment accepted; roll back the service generation if it fails.
- **[Risk] Disabling local login before a callback is verified locks out the operator** → Preserve local auth until the app-specific acceptance gate passes; stage each host separately and retain the previous Nix generation for rollback.
- **[Risk] A provider label change alters app identity** → Keep provider IDs and client IDs fixed and assert their rendered values in tests.

## Migration Plan

1. For Actual, determine and execute only a supported account-preserving identity migration; verify the same account ID through OIDC before disabling password auth. If the supported path is unavailable, pause and obtain approval before a database-level migration.
2. Reproduce Langfuse's OAuth failure with a recorded timestamp, capture relevant application and Authentik logs, repair the specific cause, and prove the existing account receives the expected session.
3. Add SSO-only controls to supported apps, private/password-disabled Memos settings, the Shrublab provider label, and desktop list alignment. Add contract tests and update `docs/identity.md` with supported clients, login exceptions, and operator acceptance steps.
4. Evaluate and run focused checks, then full repository checks. Deploy separately to the hosts owning the affected apps only after operator approval; test Actual/Memos on `oci-melb-1` and Langfuse on `home-forge` before treating the change as accepted.
5. Rollback by restoring the prior Nix generation and its local-auth settings. Memos' file-backed settings do not mutate the database; no user-data migration is automatically reversed.

## Open Questions

None change the selected design. Actual's supported account migration path is a fail-closed implementation preflight: if it cannot be verified, do not remove its password fallback or perform a database edit without approval.