## Context

The pinned default authentication flow binds `default-authentication-mfa-validation` at order 30 with all device classes and `not_configured_action: skip`, gated by a policy that skips it after passwordless sign-in (`auth_method == auth_webauthn_pwl`). The identification stage already offers passkey autofill (`webauthn_stage`), so a registered passkey signs in with one step. Authentik offers no native "other ways to sign in" link from the passkey prompt; the native fallback is the validation stage's device picker (checked against the pinned source and a local preview).

## Goals / Non-Goals

**Goals:** every sign-in ends with a verified second factor or a user-verified passkey; a lost device has a recovery route; no frontend patch; the panel does not resize between screens.

**Non-Goals:** passkey-only landing page, SMS/email MFA, remembering devices, changing the passkey-autofill path.

## Decisions

1. **Reuse the upstream MFA stage, change its action.** Set `not_configured_action: configure`, device classes `webauthn` and `totp`, and configuration stages for the passkey and TOTP setup stages. With several enrolled devices the stage shows its picker; with one it prompts directly. Rejected: two separate flows (needs a prompt stage, policy routing and cross-flow redirects for no gain).
2. **Email recovery is the lost-device route, in one flow.** The recovery link is requested from the sign-in page and needs no password. The flow is: identify, email link, new password, enrol a replacement authenticator code, sign in. Resetting only the password would strand the user, because the MFA stage would then demand the lost device. The flow signs in directly after enrolment because the email link already proved mailbox control; old devices stay enrolled until removed under Settings. Rejected: recovery codes (an extra forced step for everyone, to avoid trusting the mailbox the recovery flow already trusts) and a separate "reset MFA" flow (two flows for one situation).
3. **Password stays at signup.** Password plus an authenticator code is the route for someone without their passkey device. Rejected: passwordless-only accounts, which have no fallback at all.
4. **Enrollment.** Replace the optional passkey checkbox and its conditional stage with a required configuration step: the enrollment flow ends with the same MFA-setup injection before the first session. The email-verification gate order (40) is unchanged and runs before login.
5. **Recovery does not skip MFA setup.** The recovery flow ends in a required TOTP enrolment (a passkey can be added later in Settings), so a recovered account never reaches a session with no method. The mailbox is the root of trust for recovery; the email-verification gate (order 40) is therefore load-bearing.
6. **Fixed pane.** Already done in the theme: one desktop pane size, scaled by viewport, flow titles visually hidden so no flow exceeds the login form.

## Risks / Trade-offs

- **Auto-selected method:** Authentik prefers the last-used device, so a passkey user may see the passkey prompt first, with a link to choose another. Verified only in a local preview; confirm on the live flow.
- **Existing users:** the first password sign-in after deploy forces setup. Do the admin account first and confirm the email recovery flow works before deploying to others.
- **Lockout:** a misordered binding could deny everyone. Deploy through the existing activation gate, and keep the admin console session until the live flow is confirmed.
- **Blueprint conflict:** the stage is owned by the upstream default blueprint; our blueprint must modify it by identifier without changing the order-30 binding or the passwordless skip policy.
- **Firefox and platform authenticators** have known WebAuthn issues; TOTP is the cross-browser route.

## Migration Plan

1. Deploy the blueprint; the activation gate validates and applies it.
2. Sign in as the admin (password, then setup); run the email recovery flow once and confirm it ends signed in with a new authenticator code.
3. Verify passkey autofill still signs in in one step.
4. Verify a new invitation enrolls with a required method.
Rollback: revert the blueprint; the upstream default skips unenrolled users again.

## Open Questions

- Whether the picker's last-used preference needs a longer MFA remember window (default none).
