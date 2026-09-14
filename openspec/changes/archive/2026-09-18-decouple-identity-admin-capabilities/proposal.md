## Why

Stage 7 exposed a mutual implementation dependency between `admin-hub` and `identity-provider`: the provider reads admin-owned state while admin composition writes provider internals and owns provisioning secrets. This must be made directional before the pattern is reused or hosts become discovered contributors.

**Core Value:** Identity authority remains portable and self-contained, while admin workloads consume stable identity contracts without configuring Kanidm internals.

## What Changes

- Make `identity-provider` own Kanidm runtime, provisioning, provider data paths, identity secrets, and the explicit per-client OIDC provisioning secret-source map.
- Make `identity-client` derive its canonical provider URL from the existing web-service catalog; the provider consumes the same canonical URL instead of writing client-owned state.
- Remove all reads of `applications.admin` from provider code and all writes to `services.admin.kanidm` from admin composition.
- Decompose the enabled independently portable admin workloads — Termix, Vaultwarden, Homepage, Gatus, Beszel hub, and Webhook — into self-contained placement aspects; the remaining services share placement and catalog inputs, not intrinsic composition, so no admin-suite bundle remains.
- Record Quantum as removed from the active module graph and disabled/deferred rather than silently omitted: its service and host modules are deleted, it is not force-disabled in composition, and it is not an extraction or completion gate for this change. Termix extraction is mostly complete and remains in scope, preserving its self-contained aspect and current LA selection/runtime behavior while its focused contract test is finished.
- Preserve the architectural rule that any future Quantum re-enable lands as a self-contained concern/aspect, consumes canonical identity contracts, and does not restore admin-hub coupling.
- Keep logical client metadata in `policy/identity.json`, while keeping security-relevant SOPS source/readership mapping explicit and provider-owned.
- Preserve OIDC callback URLs, client identifiers, claim/scope policy, secret paths/readership, Kanidm state, and runtime behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `kanidm-identity`: Assign Kanidm runtime, provisioning, and OIDC provisioning secret contracts to the identity-provider concern and remove provider-to-client mutation.
- `admin-module-structure`: Replace the coupled admin-hub ownership model with independently selectable admin capabilities and directional identity consumption.
- `feature-topology`: Require independently portable capabilities to remain self-contained and prohibit sibling option namespaces as an implicit selection/dependency mechanism.
- `provider-owned-oidc-uris`: Resolve provider and client URLs from canonical web policy while preserving explicit credential-source ownership.

## Impact

- Affects `modules/flake/{identity-provider,identity-oidc,admin-hub}.nix`, Kanidm and admin service leaves, LA host bindings, registry aspect selections, identity policy checks, and architecture docs.
- Termix and Vaultwarden are the task-3.1 extractions; Quantum remains disabled/deferred.
- No `la-admin` mega-aspect or compatibility wrapper is introduced.
- No enabled service leaf is deleted and no secret ciphertext or `.sops.yaml` rule changes; the dormant Quantum service/host modules are removed as disabled/deferred, with secrets and `.sops.yaml` untouched.
- No secret is decrypted, re-encrypted, or manually edited; only typed source-path contracts may move.
- This change precedes host discovery because it removes the current mutual aspect cycle.
