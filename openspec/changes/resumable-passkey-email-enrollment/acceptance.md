# Native seam investigation

## Scope and status

2026-11-04. Planning aligned with the owner's final rulings: retain TOTP, retain independent email authenticators when the account address changes, use repeatable sign-in gates, and recover credential-less reservations through mailbox proof. No runtime blueprint, production service or live user was changed in this investigation. The initial verification-mechanism blocker below was resolved by the owner's clarification: reuse a confirmed same-user exact-address device, and create one only when missing. No implementation task was complete at the time of this native-seam investigation.

## Environment

Local rootless Podman network `enrollment-test`, disposable PostgreSQL 16 and `ghcr.io/goauthentik/server:2026.8.5` (local image ID `32dd380d0e766ff6a8100935f957b27574bd6af349832e1f0780c99f963b0204`). Release matches the evaluated native Authentik components' 2026.8.5 version, but this is the official image, not evidence that the Nix-built runtime has been exercised. All credentials were test-only; no production mail was sent.

The database was initialized through `/ak-root/.venv/bin/python -m lifecycle.migrate`. A first attempt using the bare `ak migrate` command omitted native system migrations; that partial database was discarded before the successful lifecycle bootstrap. No fake migrations or production workaround was introduced.

## Observations

A scratch probe (`/tmp/enrollment-native-probe.py`) exercised actual flow-executor HTTP endpoints with DRF's APIClient, authenticated only to enter a stage-configuration test flow. The outbound-mail dispatch boundary was mocked; the ORM, flow planner, chooser, email-code validation, device persistence and subsequent challenge selection were real. This is a native-seam experiment, not proof of complete enrollment or an anonymous login session.

- A device-less account received the native Email/Passkey setup chooser.
- Selecting Email entered the code stage for the supplied account address.
- Submitting the actual plan's generated code advanced to the next stage and saved a confirmed device visible to subsequent policies.
- A new flow with that account offered an email authentication challenge rather than the setup chooser.
- Selecting Passkey on another device-less account entered the WebAuthn registration challenge with resident keys and user verification required. Registration/sign-in were not completed by this probe.
- The native recovery email stage defaults `activate_user_on_success` to false. The current recovery fragment does not override it; previous conversational warnings must not be read as evidence that it currently reactivates users.

## Blocking constraint

The pinned native `EmailDevice` model has `unique_together = (("user", "email"),)`, independent of its setup stage. With a confirmed device already enrolled, creating another same-user/same-address device under a different verification stage was rejected by the real database with:

```text
SECOND_STAGE_SAME_ADDRESS_REJECTED authentik_stages_authent_user_id_email_9e852c67_uniq
EXISTING_DEVICE_PRESERVED True
```

The setup stage also refuses setup when a device for the user and that stage already exists. Merely separating proof and durable-device stage names does not solve verification when a retained authenticator already exists for the address being proved (for example, changing the account address to an independently enrolled address).

The initial plan's separate transient-device proof could not meet retained-device and mandatory-fresh-proof requirements using unmodified native setup stages. The owner subsequently clarified that an already confirmed address needs no new proof; that removes the duplicate-device requirement. Do not delete the retained authenticator or weaken fresh verification to pass the gate.

## Initial alternatives (superseded by the owner's clarified rule)

Recommended: use native email-link verification for the account email, separate from native email-OTP authenticator enrollment. Initial Email code setup can still establish address ownership; later account-address proof uses a link without trying to create a duplicate device. Preserve a flow-scoped snapshot of the challenged address and require it to match before recording verification. This changes the verification UI for the affected paths and needs the owner's approval before implementation.

Alternative: retain code-only verification everywhere, which needs an additional supported verification mechanism (an upstream extension or a local stage) capable of challenging an existing exact-address device without treating every retained email factor as proof of the account address. No such implementation was added or claimed verified.
