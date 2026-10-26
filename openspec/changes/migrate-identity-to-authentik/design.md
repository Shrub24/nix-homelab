# Design

## Context

See `proposal.md` for motivation and scope. This is a staged application-identity migration, not a replacement of the fleet's Unix identity system.

Observed source boundaries:

- `modules/identity/_oidc.nix:1-77` reads `policy/identity.json`, derives the Kanidm public URL from the web catalog and emits read-only endpoint projections. It already works without a local server, but its URL formulas and enabled-client lookup are Kanidm-shaped.
- `modules/identity/identity-provider.nix:1-64` contributes provider enablement and explicit per-client credential source bindings; `kanidm-runtime.nix:1-507` owns runtime, provisioning, local TLS and recovery. Its runtime currently asserts equality with the active OIDC provider URL, which must be relaxed into provider-specific identity during coexistence.
- `modules/identity/kanidm-host-auth.nix:1-60` imports `_oidc.nix` and uses `services.identity.oidc.providerUrl` as the Unix client URI. That is unsafe once application SSO changes provider.
- `modules/identity/_kanidm-packages.nix:1-11` binds native server/client packages to one release family.
- `policy/identity.json:1-164` contains client metadata, callback conventions and Kanidm scope/claim settings. Provider secret-source bindings live separately in `identity-provider.nix`; application modules contain additional provider names/scopes and runtime delivery.
- `opentofu/cloudflare/config.auto.tfvars:4-8` independently declares the Kanidm authorization, token and key-set URLs. Cloudflare's access rule reads the `groups` claim in `opentofu/cloudflare/main.tf:197-205`.
- `tests/check-identity-contract-directionality.sh:1-190` mixes useful subset/directionality checks with copied credential inventories and fixed configuration assertions. Retain the former behaviour, remove the latter snapshots rather than growing them.
- `CONVENTIONS.md` currently prefers flat contributor siblings. The accepted provider-directory structure is a deliberate, documented refinement, not an import-tree exception. No `context/` directory exists in this checkout; reasoning is recorded here and later in `docs/decisions.md`.

The current `kanidm-identity` spec requires both canonical Kanidm SSO and an encrypted authoritative membership overlay. This change explicitly revises the former and keeps the latter only for retained Kanidm; neither is silently imposed on Authentik. The host-auth spec also needs the explicit endpoint change supplied by this change's delta.

## Goals / Non-Goals

**Goals:** Independently construct client configuration and server registration from explicit policy; keep OIDC consumers provider-neutral; use Authentik-native workflows; preserve access and recoverability while the two implementations coexist.

**Non-Goals:** Consumer-host registration aggregation, a universal identity workflow DSL, permanent multi-IdP routing, migration of password hashes, automatic membership import, Authentik host authentication, broad repository reshuffling, or deployment authority inferred from implementation approval.

## Decisions

### THEME-1 — Own the glass appearance, retain native component behaviour

**Status:** active. **Evidence:** confirmed by the approved theme plan.

Use one tracked stylesheet for the glass surfaces, borders, control rounding, branding and
wallpaper tint. Retain attribution for styling adapted from Glassmorphism. Authentik owns
responsive layout, form states, menu interaction and the dashboard background layer; its
component variables are preferred over replacement layout rules.

The fetched base plus accumulating overrides was rejected because its blanket background
resets, duplicate painters and brand padding repeatedly hid the configured wallpaper and
logo. Vendoring that whole stylesheet would keep those conflicts. Revisit component-specific
rules when an Authentik upgrade changes the relevant markup or exposes a native setting.
Browser validation uses the real frontend with substituted CSS and read-only API fixtures;
production acceptance remains a separate deployment step.

The login refinement uses transparent underlined fields, using Poiret One for fields and light text
with Montserrat Alternates for the button and headings, after Maple Mono italic and Righteous. The font loads from Google Fonts' upstream file at a pinned commit through
jsDelivr, not from a vendored copy or our branding bucket. Labels remain available to assistive technology while placeholders
supply the visible prompts. Only the combined username/password card loses its title; other
flows retain theirs. A CSS variable carries that title state across the card's shadow boundary.
Patching the frontend to move remember-me, shorten the password placeholder or place the
WebAuthn token on the password field was rejected: it rebuilds the whole web bundle per
architecture, outside every public cache, and again on each upgrade. Remember-me stays in place
and is styled as a toggle. Native inputs retain autofill and caret handling; only focus lines
and placeholders transition, with a reduced-motion opt-out. On narrow screens the panel fills
the viewport so the frost is all-or-nothing.

### UX-1 — Native code entry, and passkeys as one required method

Use the native email authenticator setup stage as an address-ownership ceremony, followed by
a policy that consumes its confirmed, current-address proof and activates the enrollment
account. Delete only that verification device after recording, not unrelated MFA devices.
Keeping it would prevent subsequent setup after an address change and unintentionally enroll
email MFA. Link-page polling and custom frontend continuation are superseded: code entry
preserves the initiating plan and destination without a frontend build. The native code stage
has no resend cooldown option; that requirement remains open, not silently satisfied by the
retired link stage's rate limiter. Existing email MFA on the same address is a known native
uniqueness conflict and is not supported by this ceremony yet.

Enable passkey enrollment with discoverability and user verification required, and conditional
passkey login through the identification stage. Enrollment and recovery require a method
(passkey or authenticator code); the second factor is mandatory for every password sign-in, and
email recovery replaces a lost method in one flow (`require-mfa-with-fallback`, D-121). Leave attachment
unrestricted so synced credentials and compatible security keys both work. Retain username,
email and password login plus recovery; mandatory passkeys and automatic registration-time
enrollment need separate acceptance. Revisit the provider/UI choice if more small interaction
changes require frontend patches; ZITADEL remains an option, not an active migration.

### LAYOUT-1 — Provider directories with discovered contributors and private helpers

Use:

```text
modules/identity/
  identity-provider.nix
  _oidc.nix
  kanidm/
    server.nix
    host-auth.nix
    _client.nix
    _packages.nix
  authentik/
    server.nix
    blueprints.nix
    _blueprint.nix
    _client.nix
    _credentials.nix
```

Non-underscore Nix files are discovered flake-parts contributors. Authentik server and blueprint contributors merge into one provider module; they do not import each other's source files. `identity-provider.nix` binds the selected implementation to the existing host-facing aspect and explicit homelab secret conventions. Provider module values may have implementation-specific names without making hosts select each implementation fragment. During coexistence, an explicitly named Kanidm compatibility capability preserves the server independently of the active application provider; it is not an all-purpose provider registry.

Private `_client.nix` files are pure OIDC projections, not Unix client services. `_packages.nix` preserves the existing Kanidm release-family binding. Add no Authentik package helper unless it has a real multi-artifact invariant to express. Flow/template directories contain owned assets. Keep runtime and blueprints in one contributor if the chosen upstream integration makes the split trivial.

Revise the convention to allow cohesive multi-contributor feature directories while preserving flat siblings for concerns where that reads better. No extra discovery filter, directory `default.nix`, wholly private server subtree or one-aspect-per-source-file proliferation is needed.

Rejected: a flat list of provider-prefixed siblings, which obscures provider ownership; `client/_consumer.nix` and a separate declaration layer without a consumer that needs it; a telemetry-sized namespace and routing framework for a single application IdP.

### POLICY-1 — One explicit registration authority, two independent projections

Replace the shared Kanidm-shaped JSON with a single plain-data Nix policy, `policy/identity.nix`, whose common declarations include groups and approved clients. Provider selection and route references are explicit policy, not inferred from deployed modules. The policy derives route-owned facts through an explicit input or a shared resolver; it does not evaluate any host configuration.

Common client intent includes stable client identity, display metadata, route association, exact callback convention/extra redirects, public/confidential posture, authorized groups, required claim intent and credential identity. Keep a callback convention here rather than duplicating it in an application adapter. Application APIs may require the adapter to set a provider slug; that value comes from the same stable integration identity and must not change merely because the IdP display label changes.

Keep authorization, requested scopes and claim release distinct. Do not flatten group-dependent scope rules into a union that broadens access. If current policy has unequal per-group permissions, represent that intent explicitly or retain a narrowly named provider extension until an equivalent mapping is accepted. Unknown groups, conflicting callback definitions and unsupported translations fail by name.

Provider-specific fields live in an explicit extension, not ambiguous shared overrides. A client can be registered while its application is deselected, and Cloudflare can be registered without any local consumer module. Turning off an application is not revoking its registration.

Data flow:

```text
identity policy + canonical web/fleet facts
  ├─ intrinsic OIDC projection → consumer's native application settings
  └─ selected provider projection → provisioning / blueprints
```

Do not aggregate `nixosConfigurations.*`, inspect evaluated aspect bodies, or let client imports mutate the server's registry. This differs intentionally from same-host PostgreSQL and backup consumer registries.

### OIDC-1 — Keep the intrinsic interface; hide provider conventions

Keep `_oidc.nix` as the participant entry point and preserve existing `services.identity.oidc.clients.<name>` consumers where practical. It combines its typed interface with a selected provider's pure client projection. There is no separate `_consumer.nix` unless an actual participant needs declarations without realization.

Read-only per-client facts cover current required endpoint fields and, where used, provider label, requested scopes, group claim convention and signing expectations. Add a JWKS output when consumed by the Cloudflare projection rather than maintaining a second key-set URL formula. Do not export implementation-only path prefixes as an enduring generic interface. Provider selection is independent of whether the server is selected on this host.

Application modules own application mechanics; provider-specific endpoint/scope construction leaves them. Use small identity-owned application adapters only for real native-setting differences. They may contribute to the existing application aspect without introducing another host selection. Do not create a file or adapter registry for every otherwise trivial client. Stable callback slugs such as existing `kanidm` identifiers can survive temporarily for account continuity; document rather than cosmetically rename them.

Rejected: having an application import `authentik/_client.nix` directly, automatic server registration, or a universal renderer for unrelated environment/file/API configuration formats.

### SECRET-1 — Shared logical identity, separate authorized delivery

One client credential association is referenced by provisioning and consumer configuration. Keep explicit provider/consumer delivery bindings where they encode SOPS readership. Resolve files and keys at each deployment boundary; do not infer secret files from route placement or expose another host's `/run/secrets` paths.

Reuse `lib/secrets.nix`. A small helper can return runtime secret declarations, but applications retain their native environment-file, credential-file or template delivery. No decrypted value enters the OIDC shape, evaluation, store or diagnostics. Authentik's stable secret key, database credentials, signing keys and SMTP/bootstrap secrets are separate from application client credentials. Operator-provided material is a prerequisite, not something the implementation agent generates by decrypting or editing existing secrets.

### AUTH-1 — Native runtime with a compatible pinned blueprint implementation

Use the native `nix-community/authentik-nix` integration as the planned runtime on `la-admin-1`. Before using its interface, select and record a concrete supported revision/release and verify its NixOS, PostgreSQL, secret and blueprint interfaces against the current locked nixpkgs. Evaluate the real server/worker units with a minimal database and blueprint, not just a generated YAML parser. If this packaging cannot satisfy the contracts, stop for a runtime decision rather than silently switching to containers.

Consume the existing PostgreSQL substrate on the identity host, registering Authentik's database/role from the provider concern. Do not select a PostgreSQL mechanism implicitly from a remote OIDC consumer. Bind the canonical route's port, preserve ingress ownership of transport, and keep readiness local. Current upstream Authentik removed Redis in 2025.10; do not add a historical Redis service without a concrete selected-release requirement.

Server package, worker and version-sensitive blueprint/client projections move in the same implementation change. Application OIDC libraries remain application-owned; this coupling is not proof of their compatibility. Select asymmetric signing explicitly and preserve application-specific requirements such as Langfuse's ES256 expectation until live acceptance supports a change.

### BLUEPRINT-1 — Common generated objects plus Authentik-native workflows

Generate repetitive group definitions, applications/providers, access bindings and required property mappings from common registration policy. Keep Authentik-native flow/stage/policy definitions as blueprint assets under `authentik/flows/`; keep optional non-sensitive deployment choices in `policy/authentik.nix` only when actual fleet choices need data separate from implementation. Do not invent a generic flow language or require Kanidm to consume Authentik-only policy.

Initial ownership is declarative invitation-required enrollment, authentication/authorization and recovery flow definitions; imperative invitation issuance, people, credentials and memberships. Use the smallest supported upstream flow composition that meets those behaviours. Do not add open self-registration, new federation sources or MFA mandates without an explicit policy decision. Bootstrap one recoverable administrative access path with operator-owned credentials; it is not general declarative person management.

File-based blueprints are watched/discovered. A mounted file is not proof of apply success. Track apply status and verify representative resulting objects. Use explicit blueprint dependencies where required; entry order across independent files is not guaranteed. Blueprint transactions do not make all deployed files one atomic release.

Use stable identifiers. `state: present` owns only specified fields; omit memberships and other UI-owned fields. Avoid collision between generated and handwritten objects. Native assets may reference generated objects through stable identifiers/dependencies; shared intent is not re-declared inside native files. Runtime secret references must be readable by the worker with least-necessary permissions; do not interpolate plaintext into store-generated YAML or logs. The database and backups contain sensitive identity state even when source assets do not.

Removal needs an explicit disable/delete operation and verification. A removed file leaves its created objects behind; retain a reviewed retirement entry until the target's revocation is verified. Treat cascading deletes as an operator-visible action, not incidental cleanup.

### HOST-1 — Retained Kanidm is not the active application provider

Refactor `kanidm/host-auth.nix` to obtain its URI from a separately identified Kanidm route. Decouple the retained server's app URL/assertions from the active OIDC provider. Until an alternate endpoint is explicitly approved and verified, that binding continues to identify the existing Kanidm service and no canonical route switch is permitted.

Changing a policy route is not evidence that Kanidm accepts its new public identity or that Unix clients retain trust. Before cutover, the operator must approve the compatibility identity/transport and verify the server's supported origin/domain/TLS transition, client enrollment/trust, stable UID/GID mapping and login from independent sessions on both affected hosts. Keep a tested break-glass session and rollback. If this cannot be demonstrated, application cutover stays blocked; this change does not improvise an Agent/LDAP replacement.

The retained Kanidm encrypted overlay continues to own its own people/memberships. Authentik's UI state is independent; no automatic bidirectional synchronization is introduced. Retirement and migration scaffolding cleanup wait for separately accepted host-auth removal/replacement.

### RECOVERY-1 — Configuration is not identity state

Register Authentik with PostgreSQL export-first backup and the shared state-backup mechanism for persistent assets. Document recovery of database, uploads/templates where mutable, stable Authentik secret key and required signing material. Identify which upstream defaults generate state so a restore cannot silently replace it. Verify restored user/membership/client and an actual login in an isolated target; prevent that target from sending mail or mutating production consumers. Preserve Kanidm's version-matched portable backup and fail-closed offline verification while retained.

An application migration can change its own account links/database. Back up that state before acceptance and record a supported rollback, rather than claiming an IdP route rollback undoes all consequences.

## Risks / Trade-offs

- **Lockout through endpoint coupling** → Separate host-auth policy; block route switch until independently verified access and break-glass readiness.
- **Duplicate application accounts or wrong privilege** → Per-application linkage/subject/group acceptance; neither email equality nor matching client IDs is proof.
- **Broadened group authorization during translation** → Test allowed and denied users, not just claim presence; reject unsupported policy rather than unioning it.
- **Blueprint drift, failed apply or orphaned clients** → Field ownership, stable IDs, explicit dependencies, status evidence and explicit revocation.
- **Secrets in store or logs / unreadable worker files** → Runtime references with evaluated permissions and a real pinned-runtime acceptance check.
- **Native packaging mismatch** → Bounded compatibility task before runtime implementation; no unannounced container fallback.
- **Two identity databases during transition** → No implicit sync; keep the coexistence window operationally explicit and remove it only after host-auth acceptance.
- **Configured but unaccepted onboarding or recovery** → Distinguish static validation from operator mail/enrollment/recovery/restore evidence.

## Migration Plan

1. Refactor directories and intrinsic projections with Kanidm still selected. Preserve effective policy, secrets, callbacks and host access.
2. Migrate shared policy and client adapters while checking representative existing clients and authorization semantics. Decouple retained host-auth identity before any application-provider switch.
3. Pin/validate the native integration and implement a candidate Authentik runtime, shared/native blueprints and recovery wiring. Keep production defaults unchanged and use explicit test-policy fixtures for candidate evaluation.
4. With separate approval, provision secrets and stage Authentik on LA using separate state and an approved test URL. Test application adapters against that candidate without globally switching all production clients; any temporary per-application test override is explicit migration scaffolding, not a permanent routing framework.
5. Record per-application acceptance: issuer/discovery/JWKS/signing, scopes/group claims, permitted and denied users, existing-account linkage, data/role continuity and application-state rollback. Include UI-managed provider setup where code does not own it. Verify invitation delivery, enrollment restrictions, recovery and isolated restore.
6. Approve and verify retained Kanidm endpoint/domain/client trust separately. If not accepted, stop before canonical cutover.
7. With explicit operator approval, coordinate `id.shrublab.xyz`, application settings and Cloudflare Access federation. Derive Cloudflare endpoints from the same projection rather than retaining static Kanidm URLs; preserve its `groups` access meaning. Apply no unrelated OpenTofu changes. IdP itself remains outside Access. Preserve old configuration and application-state rollback material.
8. Observe and finish acceptance before removing temporary application migration overrides. Keep Kanidm compatibility runtime/host clients and their secrets/backups until separate host-auth retirement; remove obsolete application-only Kanidm wiring when it is no longer needed by rollback.

No step authorizes deployment merely because an implementation task is checked. Operator acceptance tasks remain incomplete until their evidence exists.

## Validation Strategy

Use existing Nix typing/assertions and focused evaluations first. Keep a few behavioural tests at the actual boundaries: intrinsic-client/provider independence; policy-driven remote registrations including an external/deselected client; callback derivation under a changed route; denial rather than widened access; and host-auth URI stability while the application provider changes. Use small fixtures with independent expected outcomes, not copies of the production client inventory.

Validate generated/native blueprints with the selected Authentik runtime, including real apply/reapply and a UI-owned membership change. Test explicit retirement on a disposable client. No new general blueprint test harness is required if an upstream validator plus one composed acceptance environment supplies the evidence. Static YAML validity alone is insufficient.

Parent-owned expensive gates remain `just checks all`, generated-flake freshness, treefmt and flake evaluation/build checks. Implementation children run only focused validation. Delete brittle list snapshots encountered in the touched identity suite; do not update or reproduce them. Live account continuity, mail, PAM/SSH and restore claims require operator evidence and must be reported pending until established.

## Sources and Deferred Operational Inputs

Repository references above are observed; layout, schema and runtime choices are proposed. Upstream behaviour was checked against:

- https://github.com/mightyiam/dendritic — top-level modules, path independence and merged lower-level modules.
- https://github.com/vic/import-tree — recursive discovery and private underscore paths.
- https://docs.goauthentik.io/customize/blueprints/ — discovery, dependency ordering, transactional apply and non-deletion of created objects.
- https://docs.goauthentik.io/customize/blueprints/v1/structure/ — stable lookup, managed fields and create/update/delete states.
- https://docs.goauthentik.io/customize/blueprints/v1/tags/ — runtime references and object relationships.
- https://docs.goauthentik.io/add-secure-apps/providers/oauth2/ — issuer/signing and scope/access distinctions.
- https://docs.goauthentik.io/users-sources/user/invitations/ — invitation enrollment.
- https://docs.goauthentik.io/releases/2025.10/ — Redis removal.

The concrete native release pin is a bounded compatibility verification task, not an assumed validated dependency. Operator inputs before live work are the staging/compatibility identities, credentials and SMTP delivery details, account-linkage decisions for existing users and approval of the cutover window. None is supplied or inferred by these planning artifacts. If an operational choice changes these contracts rather than filling a value, revise the proposal before proceeding.
