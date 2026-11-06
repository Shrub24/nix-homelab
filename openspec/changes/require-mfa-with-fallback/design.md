## Current scope

Enrollment and recovery now follow `../resumable-passkey-email-enrollment/design.md` (D-131). The mandatory-factor requirement remains; email codes are an accepted alternative and TOTP remains available. Live rollout acceptance is still separate from isolated flow acceptance.

## Context

The pinned default authentication flow binds `default-authentication-mfa-validation` at order 30 with all device classes and `not_configured_action: skip`, gated by a policy that skips it after passwordless sign-in (`auth_method == auth_webauthn_pwl`). The identification stage already offers passkey autofill (`webauthn_stage`), so a registered passkey signs in with one step. Authentik offers no native "other ways to sign in" link from the passkey prompt; the native fallback is the validation stage's device picker (checked against the pinned source and a local preview).

## Goals / Non-Goals

**Goals:** every sign-in ends with a verified second factor or a user-verified passkey; a lost device has a recovery route; no frontend patch; the panel does not resize between screens.

**Non-Goals:** passkey-only landing page, SMS MFA, remembering devices, changing the passkey-autofill path.

## Decisions

1. **Reuse the upstream MFA stage, change its action.** Set `not_configured_action: configure`, accepting passkeys, email codes and TOTP, with native setup stages for all three. With several enrolled devices the stage shows its picker; with one it prompts directly. Rejected: two separate flows (needs a prompt stage, policy routing and cross-flow redirects for no gain).
2. **Email recovery is the lost-device route, in one flow.** The recovery link is requested from the sign-in page without a credential. Its captured recipient must match the current account address. Mailbox proof establishes an email factor, followed by a strength-checked password and guarded login. Established verified accounts retain their devices; never-verified reservations lose pre-verification credentials before the recovered session. Disabled accounts remain disabled. Rejected: recovery codes (an extra forced step for everyone, to avoid trusting the mailbox the recovery flow already trusts) and a separate "reset MFA" flow (two flows for one situation).
3. **Password is required only without a confirmed passkey.** Passkey enrollment needs no password. Password plus email code or TOTP remains supported, and mailbox recovery can establish a password after passkey loss.
4. **Enrollment.** Create an active username/email reservation before native method setup. Without a confirmed passkey, require a password. Record confirmed exact-address ownership and complete any remaining email verification before login.
5. **Recovery leaves a usable factor.** Mailbox proof creates or confirms the current-address email authenticator without forcing TOTP setup. The same mailbox proof guards password prompting, password write and session creation.
6. **Fixed pane.** Already done in the theme: one desktop pane size, scaled by viewport, flow titles visually hidden so no flow exceeds the login form.

## Risks / Trade-offs

- **Auto-selected method:** Authentik prefers the last-used device, so a passkey user may see the passkey prompt first, with a link to choose another. Verified only in a local preview; confirm on the live flow.
- **Existing users:** the first password sign-in after deploy forces setup. Do the admin account first and confirm the email recovery flow works before deploying to others.
- **Lockout:** a misordered binding could deny everyone. Deploy through the existing activation gate, and keep the admin console session until the live flow is confirmed.
- **Blueprint conflict:** the stage is owned by the upstream default blueprint; our blueprint must modify it by identifier without changing the order-30 binding or the passwordless skip policy.
- **Firefox and platform authenticators** have known WebAuthn issues; TOTP is the cross-browser route.

## Migration Plan

1. Deploy the blueprint; the activation gate validates and applies it.
2. Sign in as the admin; exercise mailbox recovery and confirm a subsequent password/email-code login works without forcing TOTP setup.
3. Verify passkey autofill still signs in in one step.
4. Verify a new invitation enrolls with a required method.
Rollback restores configuration, not user/device state. Follow the stateful rollback procedure in `docs/runbooks/identity-migration.md`.

## Open Questions

- Whether the picker's last-used preference needs a longer MFA remember window (default none).
