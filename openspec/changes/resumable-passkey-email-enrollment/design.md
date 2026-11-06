# Design

## Context

See `proposal.md` for motivation. Implementation stays with the identity concern's private blueprint fragments; `blueprints.nix`, the assembler and the pinned import gate remain the delivery mechanism. All consuming applications continue to use the intrinsic OIDC contract unchanged. The provider is placed on oci-melb-1; this changes no other host's runtime or secret readership.

Observed seams:

- `enrollment.yaml` creates inactive users before email setup and MFA, then gates its login stage with `policy-email-verified`.
- `verification.yaml` consumes a confirmed `EmailDevice` scoped to `verify-email-code`, records the exact address, activates the person and deletes the proof. The login gate carries the same consuming block.
- `passkeys.yaml` already configures discoverable, user-verifying passkeys and conditional passkey identification. No new passkey-login mechanism is required.
- `mfa.yaml` overrides the shared validation stage with passkey/TOTP setup. It is not an enrollment-only object.
- `recovery.yaml` proves mailbox access through a link, sets a password and forces TOTP enrollment before logging in. It currently has no shared enrollment password-strength policy on its password prompt.
- The pinned authenticator chooser inserts the selected setup stage and advances; it is not a general branch primitive and must not be assumed to re-check the result afterwards.

These observations correct earlier conversational claims that passkey identification was missing and that the chooser necessarily resumes to validate a newly created device. The isolated flow test, not the earlier explanation, is the acceptance evidence.

## Goals / Non-Goals

Goals: implement ENR-1 through ENR-5 using native stages plus small repo-owned policies, with no custom Authentik frontend or fork. Preserve disabled-account semantics and both existing credential families.

Non-goals: the welcome animation and broad theme changes; unattended user cleanup; changes to invitation sharing policy; passwords or passkeys in Nix/SOPS; changing OIDC clients, groups or application permissions; an admin-only authentication policy not requested here.

## Decisions

### ENR-1: Keep native setup and repeatable sign-in gates

Target visible sequence:

1. Username and email, followed by user creation, active but without a usable password.
2. Native setup choice: **Passkey** or **Email code**.
3. Passkey choice: register the passkey, skip password setup, then verify email.
4. Email choice: verify email through the selected setup stage, then set a strength-checked password; skip the final email challenge because the exact address is already recorded.
5. Issue a session only when the selected path is complete and the address is proven.

Use the shared native MFA requirements for enrollment and subsequent sign-in, rather than a compatibility layer or a permanent signup mode. Offer Passkey and Email code at enrollment; TOTP remains accepted at sign-in and available for setup. A dedicated setup stage is justified only if native challenge validation would otherwise challenge an enrolled method instead of offering the enrollment choice. Gate both password prompting and its write on the absence of an eligible passkey, evaluated after setup. Do not inspect the private selected-stage context key or store a permanent signup-mode attribute.

A passkey must attach to an existing user, so the early user write is necessary. It is an account reservation, not authentication: no credential and no session means username knowledge gives no access. Never let a retry overwrite an existing user's credentials based on matching username/email alone.

Alternative: a custom two-button frontend and branch selector. Rejected because the native setup chooser already supplies the desired interaction.

### ENR-3: Reuse confirmed exact-address devices

The owner clarified that prior confirmation of the same address is sufficient; fresh proof is not required on every address change. Query confirmed email devices belonging to the pending user and matching the current account address. If one exists, record that address as verified without sending another code, deleting it or creating a duplicate. Otherwise use the native email-code setup stage and retain its confirmed device. Keep the existing exact-address verified attribute as accepted recorded evidence. Remove all verification-policy writes to `is_active`.

Native email setup refuses a second device for a user under the same setup stage, even for another address. After setup, associate confirmed devices from the verification setup stage with the durable email-authenticator stage. This preserves the same device and its confirmation while leaving the setup stage available for a different unproved address. Same-user/same-address uniqueness is respected by reusing the device before setup, not by replacing it. Record ownership immediately after email setup, before any password screen, so the email branch receives no second code.

Retain previously enrolled email authenticators independently of the account address; the user may remove them. An old-address device remains an authentication factor but cannot establish verification of a new account address. Keep the final verification check before every affected login/session path; stage skipping is not proof that a session was safely denied.

### ENR-2: Passkey or password plus code; not email-only login

Reuse existing conditional passkey identification and its password/MFA bypass for successful passkey authentication. Add email to the accepted password-MFA methods without removing TOTP or WebAuthn for established users. A passkey-only account gaining a persistent email device still cannot sign in with that code alone: it has no usable password. Mailbox recovery can establish one deliberately.

Accept the weaker mailbox-based fallback as the owner's choice, rather than describe it as equivalent to phishing-resistant passkeys. Do not introduce a separate admin exception silently. If that is wanted later it is a separate policy decision.

### ENR-4: Recovery is part of enrollment completion

Changing creation to active prevents future activation limbo, but does not itself solve abandonment before any credential exists. Reuse mailbox recovery as the authenticated completion route for that account, with neutral guidance from signup/sign-in. No fresh invitation is required for recovery of an existing person.

Recovery must produce a usable password plus email factor instead of forcing a TOTP app contrary to the chosen enrollment offer. Apply the same password-strength policy to recovery. Reuse the email-proof/device seam; if the existing recovery link does not supply the required exact-address evidence, run the shared code stage rather than synthesize verification from a pending user. Session creation remains behind the shared verification requirement. Explicitly prevent automatic reactivation, including the native recovery email stage's `activate_user_on_success` behavior.

Pre-account takeover consideration: a credential attached to an unverified reservation is not necessarily the mailbox owner's. When recovering such an account, invalidate pre-verification credentials before issuing the recovered session, then establish the selected usable credentials. Do not reset established verified users' devices as a side effect of normal recovery. Recovery for a lost established passkey must be demonstrated with the new email fallback; no promise of a particular fallback is made solely from blueprint validation.

Alternative: add a separate public completion flow. Rejected initially because it duplicates mailbox recovery and creates another session-issuing path to maintain.

### ENR-5: Preserve state and repair only reviewed stranded accounts

No bulk activation or database migration. The operator identifies the reported stranded people, distinguishes incomplete signup from intentional suspension, enables only those approved accounts and lets verification/completion establish ownership. Do not delete users or application links to make testing easier.

Single-use invitations are consumed at the invitation stage, not at successful signup. Do not casually switch to reusable invitations: that changes who may create accounts. Preserve current semantics. An interrupted browser can continue while its plan survives; otherwise an existing account uses recovery, and a user who abandoned before account creation needs a replacement invitation.

## Risks / Trade-offs

- Mailbox compromise defeats email-based fallback and mailbox recovery → state this explicitly; keep passkey sign-in the convenient recommended path, not an additional mandatory password.
- Credentials can be created before address ownership is established → no session before proof; clean untrusted credentials during recovery of never-verified reservations; test this adversarially.
- An email change leaves a device targeting the old mailbox → deliberately retain that independent factor, but require proof of the new account address. Do not rewrite or delete the device automatically.
- Editing the shared validation stage could strand users → keep TOTP accepted alongside passkey and email, and exercise all three methods without a legacy compatibility branch.
- Abandoned rows reserve a username → mailbox-proved completion, no unauthenticated overwrite and no cleanup daemon in this change.
- A schema-valid blueprint can still skip a crucial binding or strand a user → isolated pinned Authentik flow acceptance is a release gate, not an optional post-deploy check.

## Migration Plan

1. Verify the pinned native seams in an isolated instance with disposable accounts, no production mail or user mutations. Capture the behavior at each interruption point.
2. Implement and review the blueprint changes and repo-owned policy tests; preserve object identity where bindings already exist, explicitly retire superseded bindings through native blueprint lifecycle.
3. Reconcile overlapping promises in `migrate-identity-to-authentik`, `require-mfa-with-fallback` and `harden-application-sso`; update identity docs, the recovery runbook and decision record with owner-confirmed rationale.
4. Run static/schema checks, focused behavioral checks and the parent-owned full gates. Keep production unchanged until acceptance is complete.
5. Deploy with an existing administrator session and working break-glass access retained. Exercise one disposable invited user on each path before inviting real users. Operator-approved repair of the two stranded accounts is separate from deployment.
6. Roll back the provider generation/blueprint if required, accounting for durable state: newly created passwordless or email-factor accounts survive a config rollback and the old policy may not admit them. Keep the tested recovery configuration available; do not claim that a Nix generation rollback undoes users or devices.

## Validation

Test promises, not YAML keys, stage order numbers or Nix module semantics. Extend policy tests by executing shipped expressions with hostile evidence: another user's device, a nonmatching address, an unconfirmed device, exact-address reuse, repeated evaluation and an administratively disabled user. Do not copy the production decision logic into expected results.

The pinned-instance acceptance matrix must cover: both completed enrollments; password plus email OTP and passkey-only login; existing password/TOTP login; abandonment before credential creation, after email proof before password and after passkey before verification; completion through recovery; never-verified reservation credential invalidation; wrong/expired codes; address change; administrative disablement; duplicate submission and a consumed single-use invitation. Assert session issuance/non-issuance and usable subsequent login, not merely successful blueprint import. If the existing harness cannot execute these paths, build the smallest reusable pinned-instance fixture and report the validation gap until it runs.
