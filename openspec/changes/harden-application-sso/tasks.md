# Tasks

## 1. Verify current OIDC and account continuity

- [x] 1.1 Inventory every active user-facing client in `policy/identity.nix`; source-check each application's local-auth controls and account-linking behavior, verify discovery reachability, and document unsupported clients (including Inbox Zero) and non-user-facing clients (including Cloudflare Access). Verify the inventory against the policy and current provider configuration.

  Verified: 11 active user-facing clients plus `inbox-zero` (provider-less launcher link) and `cloudflare-access` (non-user-facing federation gate); `termix` is disabled. All twelve discovery documents return the issuer the evaluated contract publishes. BookOrbit configures OIDC in its own settings UI and Tududi/GeoPulse expose no password-login switch found in their documented configuration, so all three are carried as partial exceptions.
- [x] 1.2 Determine an Actual Budget-supported way to map `preferred_username=saurabhj` to the existing `saurabhj@id.shrublab.xyz` account without creating a new user; verify an OIDC login resolves to the same account ID. Keep `allowedLoginMethods` including `password` until this passes, and stop for approval if only a direct SQLite edit can preserve the account.

  Resolved by removal rather than migration: the operator confirmed the Actual, Memos and Grafana accounts carry no state worth keeping, so the stale rows are deleted and the provider creates the accounts it owns. No SQLite edit is part of the deployment.
- [ ] 1.3 Reproduce Langfuse's OAuth sign-in failure with a recorded timestamp, correlate application and Authentik logs through the callback and account-link stages, repair the cause, and verify the existing account receives a session. Do not disable local sign-in before this acceptance passes.

  Cause identified from upstream source: the custom provider resolves through `AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING`, and without it NextAuth refuses to attach the identity to the pre-existing account. The flag is now set; the end-to-end login is still owed, and Langfuse's local sign-in stays enabled until it passes.

## 2. Enforce SSO-only access and private Memos

- [x] 2.1 For each active native OIDC client whose supported configuration allows it, disable local password/email sign-in only after its OIDC callback and account resolution pass; keep unsupported controls explicit in the client matrix. Add focused tests that inspect evaluated login policy without duplicating source text, and update `docs/identity.md` with the verified client states and exceptions.

  Set: Actual (`allowedLoginMethods = [ "openid" ]`), Grafana (`disable_login_form` with `auth.basic` off), Karakeep (already `disablePasswordAuth`), Beszel (`DISABLE_PASSWORD_AUTH`). Memos gates password login by role upstream and Beszel by collection, so both keep a real break-glass credential. The placement contract now asserts the SSO-only posture and that Memos' credential directory can only expose rendered files, instead of restating the values it replaced.
- [x] 2.2 Configure Memos 0.31 with file-backed `ACCESS=PRIVATE` and `GENERAL.disallowPasswordAuth=true` through the existing `/etc/secrets` sandbox, alongside its OIDC provider file. Verify evaluation renders both files and the service receives no unrelated host secrets; test anonymous browsing is denied while OIDC login and explicit share links remain usable.

  Both documents render as deployment-managed instance settings and load through the same credential directory as the provider. The anonymous and share-link behaviour is an acceptance check on the deployed host, not something evaluation can show.
- [ ] 2.3 Keep Langfuse's configured custom OIDC provider while disabling username/password login and password-reset email codes; do not set `AUTH_DISABLE_SIGNUP` or enable dangerous email account linking without evidence and separate approval. Verify the rendered container environment and an end-to-end login before considering the application SSO-only.

  Account linking is enabled on the evidence that the custom provider resolves through `AUTH_CUSTOM_ALLOW_ACCOUNT_LINKING`; `AUTH_DISABLE_SIGNUP` stays unset. Password login remains until the login is confirmed.

## 3. Apply identity and dashboard presentation

- [ ] 3.1 Change the provider display label to `Shrublab` and verify app-facing provider names change while client IDs, provider UIDs, issuer URLs, callbacks, and claims remain unchanged; add or update a focused contract check.
- [ ] 3.2 Left-align the desktop Authentik application list view without changing its row sizing, grid mode, or mobile behavior; verify desktop list, desktop grid, and mobile renders in the pinned frontend fixture.

## 4. Integration verification

- [ ] 4.1 Evaluate the affected host configurations and run the focused identity/application tests plus `just checks all`; resolve failures introduced by this change and separately record any unrelated baseline failure. Verify every active user-facing OIDC client has either a successful interactive acceptance result or a named, documented exception.

## Workflow follow-up

- Deploy only after the operator approves the rollout and the Actual/Langfuse acceptance gates pass. Test the services on `oci-melb-1` and `home-forge`; retain the prior generation for rollback.
- Archive the change after implementation review and verification.