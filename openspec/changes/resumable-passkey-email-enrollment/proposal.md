## Why

Two invited users have been stranded by incomplete enrollment: the account is created inactive, but ordinary sign-in rejects it before the email-verification gate can run. Enrollment also requires a password even when a passkey could replace it.

**Core Value:** An invited person can choose passkey sign-in or password plus an emailed code, prove their email address, and recover an interrupted enrollment without operator intervention.

## What Changes

- Create enrollment accounts active; reserve account disablement for an administrative decision, not progress through signup. Verification policies must not reactivate disabled people.
- Collect username and email first. Offer the native authenticator setup chooser with Passkey and Email code. Passkey users set no password; email-code users set a strength-checked password after proving mailbox possession. Both paths require email verification before a session.
- Reuse a confirmed email authenticator belonging to the same user and matching the account address as verification evidence. Send a code and create a device only when that address has not already been proved; retain independent devices and TOTP.
- Preserve existing passkey sign-in and existing password/TOTP accounts. Add password plus email-code login without enabling email-only login.
- Make mailbox recovery the supported route for a lost passkey or an abandoned account without credentials. Do not make users repeat an invitation to recover an existing account.
- Document operator-assisted repair for the already-inactive users, with explicit review rather than blanket activation.
- **BREAKING security-policy change:** Ordinary users may choose password plus email OTP instead of password plus TOTP. Mailbox compromise is therefore an accepted fallback risk; this is not phishing-resistant MFA.

## Capabilities

### New Capabilities

- `identity-enrollment`: Invitation-gated credential choice, verified email, interruption recovery and compatibility with existing accounts.

### Modified Capabilities

None. `openspec/specs/provider-owned-oidc-uris/spec.md` continues to own client-facing endpoint projection; it does not own enrollment. The active changes `migrate-identity-to-authentik`, `require-mfa-with-fallback` and `harden-application-sso` overlap this area and must be reconciled at implementation closeout rather than treated as independent promises.

## Impact

The Authentik blueprint fragments under `modules/identity/authentik/_blueprint/fragments/` (enrollment, verification, MFA, passkeys and recovery), their repo-owned behavioral checks, and identity documentation/runbook. No application OIDC client, route, host placement, encrypted secret or new dependency changes are intended.

Constraints: use pinned Authentik stages and policies, retain invitation gating and existing user/device state, avoid private flow-context branch keys, preserve disabled-account semantics, and prove the flow in an isolated pinned Authentik instance before claiming readiness. No live flow changes, deployments or user edits are authorized by this proposal. The welcome-animation experiment remains separate.
