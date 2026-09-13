## Why

Stage 7 exposed a mutual implementation dependency between `admin-hub` and `identity-provider`: the provider reads admin-owned state while admin composition writes provider internals and owns provisioning secrets. This must be made directional before the pattern is reused or hosts become discovered contributors.

**Core Value:** Identity authority remains portable and self-contained, while admin workloads consume stable identity contracts without configuring Kanidm internals.

## What Changes

- Make `identity-provider` own Kanidm runtime, provisioning, provider data paths, identity secrets, and the explicit per-client OIDC provisioning secret-source map.
- Make `identity-client` derive its canonical provider URL from the existing web-service catalog; the provider consumes the same canonical URL instead of writing client-owned state.
- Remove all reads of `applications.admin` from provider code and all writes to `services.admin.kanidm` from admin composition.
- Decompose independently portable admin workloads into self-contained placement aspects where no substantial shared implementation dependency exists; retain only justified aggregator composition for Homepage/Gatus or other true shared policy.
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
- No `la-admin` mega-aspect or compatibility wrapper is introduced.
- No secret is decrypted, re-encrypted, or manually edited; only typed source-path contracts may move.
- This change precedes host discovery because it removes the current mutual aspect cycle.
