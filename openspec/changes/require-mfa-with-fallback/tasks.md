## 1. Policy blueprint

- [x] 1.1 Add `_blueprints/mfa.yaml` modifying `default-authentication-mfa-validation`: device classes webauthn/totp, `not_configured_action: configure`, configuration stages (passkey, TOTP setup); keep its order-30 binding and passwordless skip policy.
- [x] 1.2 Extend `recovery.yaml`: after the new-password step bind the TOTP setup stage, then login; keep the flow reachable from the sign-in page without a password.
- [x] 1.3 Replace the optional passkey checkbox and its conditional stage in `enrollment.yaml` with a required MFA-setup step before the first session; keep the email-verification gate order.
- [x] 1.4 Wire the file through `_blueprints.py`/`_blueprint.nix`; update titles in `wording.yaml`.
- [x] 1.5 Verify the converted blueprint against the prior document entry-by-entry, and run the build-time schema validation.

## 2. Verification

- [ ] 2.1 Isolated activation test: password-only user is forced to enrol, passkey sign-in skips MFA, recovery ends with a forced enrolment (blocked: needs an aarch64 builder; the schema check, the plan invariant and the delivery VM test cover the wiring until then).
- [x] 2.2 Behavioural check for MFA-5 (recovery creates no session before enrolment); no config-echo assertions.
- [x] 2.3 Preview the real picker and setup screens at desktop and mobile widths (pane unchanged).

## 3. Rollout

- [x] 3.1 Update `docs/identity.md` and `design.md` of `migrate-identity-to-authentik` where they describe optional passkeys.
- [x] 3.2 Record the decision (mandatory MFA, email recovery as the lost-device route) in `docs/decisions.md`.
- [ ] 3.3 Deploy, then complete the migration plan: admin first, email recovery run once, passkey autofill, new invitation.
