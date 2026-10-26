## Why

Login enforces a second factor only for users who already enrolled a WebAuthn device (the upstream MFA stage skips users with no device). The policy is inconsistent, and a user without their passkey device has no second route: after a password the flow can only ask for the passkey again.

## What Changes

- Make MFA mandatory for every password sign-in: the MFA stage stops skipping unenrolled users and injects a setup stage instead.
- Offer three validation methods on one screen: passkey or authenticator code (TOTP). The native device picker is the fallback route; there is no new flow and no frontend patch.
- Keep one-step passkey sign-in from the username field unchanged: it skips the password and MFA stages.
- Make the email recovery flow the single route for a lost device: link from the sign-in page (no password needed), set a new password, enrol a replacement authenticator code, then sign in.
- Enrollment ends with a required passkey or authenticator code, replacing the optional passkey checkbox.
- Fix the desktop login pane at one size across every flow so MFA and setup screens do not resize it (already implemented in the theme).

## Capabilities

### New Capabilities

- `authentik-mfa-policy`: mandatory MFA, method choice, one-flow email recovery, and enrollment requirements for the Authentik login and enrollment flows.

### Modified Capabilities

None. No existing spec covers these flows.

## Impact

- `modules/identity/authentik/_blueprints/` (passkeys, enrollment, a new MFA blueprint) and `_blueprint.nix` wiring.
- `modules/identity/authentik/_blueprints/wording.yaml` for the setup-screen titles.
- Existing users are asked to enrol on their next password sign-in; no data migration.
- `docs/identity.md` and the identity contract check.
- Not in scope: SMS or email as MFA, a passkey-only landing page, a frontend patch, Kanidm removal.
