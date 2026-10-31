# Proposal

## Why

Replace Kanidm application SSO with Authentik while preserving reproducible client registration and allowing onboarding, user administration and memberships through Authentik's UI. The current OIDC projection is a useful boundary, but committed policy and application configuration still encode Kanidm-specific scopes, endpoints and provider names.

**Core Value:** One explicit identity policy constructs both server registration and remote application configuration, without making consumer-host evaluation a provisioning mechanism or sacrificing recoverable access.

## What Changes

- Group provider implementations under `modules/identity/kanidm/` and `modules/identity/authentik/`. Discovered files remain flake-parts contributors; intrinsic contracts and pure helpers remain underscore-prefixed. Refine the flat-sibling convention for substantial cohesive feature directories, without reorganizing unrelated domains.
- Keep `modules/identity/_oidc.nix` as the intrinsic application-facing interface. Provider-local `_client.nix` helpers construct the OIDC shape from explicit identity policy and canonical web policy. Importing the interface deploys nothing and does not register a client.
- Replace the Kanidm-shaped shared policy with common registration intent, preserving explicit provider-specific exceptions. The server independently realizes approved registrations; it never collects them from evaluated consumer hosts. Registrations may exist for deselected or externally managed applications.
- Move provider-specific OIDC knowledge out of application runtime modules into the client projection and narrowly scoped application adapters where needed. Preserve stable callback/provider identifiers when changing them would break account linkage.
- Add a pinned Authentik implementation on `la-admin-1`, with server/worker, PostgreSQL, runtime secrets, blueprint delivery, notification and export-first recovery wiring. Prefer the native `authentik-nix` integration; verify and pin a compatible release before implementation depends on its interface.
- Generate repetitive provider/application/group/access objects from shared policy. Keep Authentik-specific flows, stages, policies, bindings and templates native rather than inventing a generic identity workflow language.
- **BREAKING:** Authentik owns people, invitations, credentials and memberships in its database/UI; the Kanidm encrypted authoritative membership overlay is not an Authentik reconciliation input. Repository policy owns group definitions and access rules, not member lists.
- **BREAKING:** Provider issuer/subject/signing behaviour and Cloudflare federation change at an explicitly approved cutover. Require per-application account-continuity evidence, allowed/denied login acceptance, blueprint-apply evidence and tested recovery before switching the canonical route.
- Preserve Kanidm Unix/PAM/SSH capability, state, release-family binding and restore guarantees until a separately accepted host-auth transition. Decouple its endpoint from the active application OIDC provider before any route switch. This change does not select an Authentik host-auth replacement.

## Capabilities

### New Capabilities

- `authentik-identity`: Version-coherent Authentik runtime, shared-policy and native-blueprint provisioning, declarative/UI ownership, recovery and gated application-SSO cutover.

### Modified Capabilities

- `provider-owned-oidc-uris`: Extend the intrinsic endpoint projection into a provider-neutral client contract, with explicit two-sided policy consumption and no reverse registration.
- `kanidm-identity`: Retain Kanidm as a migration/host-auth compatibility provider rather than requiring it to remain the canonical application IdP; preserve its state and operational safeguards while selected.
- `host-unix-auth`: Bind retained Kanidm host login to its own policy-resolved endpoint rather than the active application's OIDC provider URL.

## Impact

- Identity contributors/helpers, `policy/identity.json` and its replacement, web-policy identity routes, application OIDC adapters, `modules/hosts/la-admin-1/` and affected consumer-host bindings.
- PostgreSQL and state-backup registrations, identity-scoped secrets/templates and explicit SOPS readership; the operator alone creates or edits encrypted secrets.
- Cloudflare IdP endpoint/claim configuration in `opentofu/cloudflare/`, including the existing runtime-secret rendering/export path; no unrelated OpenTofu changes may be applied.
- `CONVENTIONS.md`, architecture documents, identity runbooks and behavioural contract checks. Remove configuration-inventory snapshots rather than copying them into new expectations.
- Existing requirements are in `openspec/specs/{kanidm-identity,provider-owned-oidc-uris,host-unix-auth}/spec.md`; related `feature-topology` and `internal-service-auth` contracts continue to govern composition and runtime-secret ownership.

### Constraints and boundaries

Planning and implementation do not authorize deployment, DNS/OpenTofu application, user migration or secret manipulation. Stage Authentik alongside Kanidm with separate state and an explicitly approved test identity; keep current production defaults until live acceptance. The final URL remains policy-derived `https://id.shrublab.xyz`, with no Cloudflare Access gate on the IdP itself. Do not switch it until retained Kanidm host authentication has an independently reachable and verified endpoint. No permanent dual-IdP platform, automatic user/password import, LDAP/SSSD/Agent rollout, or telemetry-style identity framework is included.
