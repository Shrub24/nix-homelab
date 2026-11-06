# Tasks

Planning only. No deployment, live user mutation or secret editing is authorized. During apply, dispatch one bounded writer task at a time; the parent owns integration gates and checkpoint review. Keep work in the mutable change rather than appending a commit per fix.

## 1. Prove the native flow seams

- [x] 1.1 Use an isolated instance of the pinned Authentik release with disposable users to prove the enrollment chooser can insert Passkey or the email setup stage, the email device survives for subsequent challenges, and post-setup policies see the created device. Exercise existing duplicate-device handling and the native recovery email stage's activation option. Record reproducible commands and observed results in the change's acceptance report; do not modify production or build a general-purpose auth testing framework. Done when both paths have a demonstrated native execution path rather than only a schema-valid plan.

## 2. Separate verification, device enrollment and administrative status

- [x] 2.1 In `modules/identity/authentik/_blueprint/fragments/verification.yaml`, remove activation side effects, reuse confirmed same-user exact-address devices and make recording/enrollment idempotent. Retain independent email authenticators when the account address changes; nonmatching devices cannot verify it. Keep the verification setup stage available for later address changes without deleting confirmed devices. Extend `tests/assert-authentik-email-policy.py` around the actual expressions for exact-address reuse, another user's device, nonmatching or unconfirmed devices, repeated evaluation and disabled-account preservation; update the email-verification section of `docs/identity.md`. Verify with `bash tests/check-identity-contract-directionality.sh` and the isolated instance: an exact-address confirmed device is reused, while missing evidence requires a code for the current address without deleting other devices.

## 3. Deliver both enrollment and login paths

- [x] 3.1 Rework `fragments/enrollment.yaml` into username/email → active account reservation → native Passkey/Email code setup → conditional password prompt/write → remaining email verification → guarded login. Reuse the existing strength policy and passkey configuration; do not use the private selected-stage context key. Use shared repeatable MFA/email requirements at sign-in without a legacy compatibility layer; TOTP must remain accepted and available. Document both user journeys in `docs/identity.md`. Verify the assembled blueprint with `bash tests/check-identity-contract-directionality.sh`, then show session denial before completion and successful subsequent login on both paths in the isolated instance, including existing password/TOTP users.

## 4. Make interrupted enrollment and recovery usable

- [x] 4.1 Update `fragments/recovery.yaml` and the shared verification seam so mailbox-proved recovery completes a credential-less reservation or lost-passkey account with a strength-checked password and usable email factor; it must not force TOTP or automatically reactivate disabled users. For never-verified reservations, invalidate pre-verification credentials before the recovered session is issued. Add concise completion/recovery guidance using native flow content without a new custom UI. Land behavioral regression coverage at the faithful pinned-instance boundary and update `docs/runbooks/identity-migration.md`. Verify abandoned-before-credential, email-proven-before-password and passkey-before-email cases, plus an adversarial unverified reservation with someone else's pre-enrolled passkey. Record exact session and subsequent-login outcomes.

## 5. Integrate, review and prepare rollout

- [ ] 5.1 Reconcile the overlapping active identity/MFA/SSO change artifacts and identity docs with the selected email alternative; record the owner-confirmed decision through the repository's rationale workflow. Document reviewed repair for legacy inactive users, invitation replacement before account creation, mail-delivery dependency and stateful rollback limitations. Verify with `openspec validate resumable-passkey-email-enrollment --strict` and a focused read-only checkpoint review; no blanket activation, invitation widening or deletion of existing users is permitted.
- [ ] 5.2 Run the parent-owned final gates on the indexed final tree (`git add -A` before `.#` evaluation): `treefmt --fail-on-change`, `just checks all`, and `nix flake check`. Execute the complete design acceptance matrix in the isolated pinned instance and retain its results. Done only when schema/import validation, repo-owned policy behavior and browser-level session issuance agree; report an unavailable harness or failed path as a blocker, not as a deferred success.

## Workflow follow-up

- After explicit deploy approval, retain an administrator session and break-glass access, deploy the provider and accept one disposable invited user on each path before inviting real users.
- The operator reviews and repairs the already-stranded users separately; neither apply nor rollout automatically changes their active flag.
- Archive after implementation review and acceptance. The welcome animation remains a separate unimplemented experiment.
