## 1. Baseline and ownership inventory

- [ ] 1.1 Capture LA/OCI identity and admin aspect subsets, rendered Kanidm provisioning, OIDC outputs, service units, and SOPS registrations; verify current paths/readership and runtime values are recorded without decrypting secrets.
- [ ] 1.2 Inventory every `applications.admin` consumer and classify it as identity-provider, independent admin capability, or justified aggregator; verify no consumer remains unclassified before edits.

## 2. Directional identity contracts

- [ ] 2.1 Move Kanidm data-root and identity/provisioning secret options into the identity-provider concern; verify paths, keys, modes, and evaluated Kanidm configuration are unchanged.
- [ ] 2.2 Add the provider-owned OIDC provisioning secret-source map keyed by canonical clients; verify missing/extra keys fail and all existing source paths remain byte-identical.
- [ ] 2.3 Default identity-client provider URL from canonical web policy and make identity-provider consume the same URL; verify neither writes the other's namespace.
- [ ] 2.4 Remove all provider reads of `applications.admin` and admin writes of `services.admin.kanidm`; verify synthetic provider-only and client-only compositions evaluate without missing-option errors.

## 3. Admin capability decomposition

- [ ] 3.1 Extract Termix, Vaultwarden, and Quantum into self-contained aspect contributors with their own runtime/secret contracts; verify each meaningful subset evaluates independently.
- [ ] 3.2 Reassess Homepage, Gatus, Beszel hub, and Webhook against actual shared behavior; keep only documented intrinsic composition and verify no service is grouped solely by LA colocation.
- [ ] 3.3 Update LA's explicit aspect selections and remove `applications.admin` once zero consumers remain; verify no convenience bundle or transitive public-aspect import replaces it.

## 4. Security and behavior equivalence

- [ ] 4.1 Compare identity policy, OIDC client IDs/callbacks/scopes/claims, SOPS registrations/readership, Kanidm units, and admin service endpoints before/after; verify no unintended delta.
- [ ] 4.2 Add dependency-direction and subset-evaluation ratchets; verify reintroducing a sibling namespace dependency fails the tests.
- [ ] 4.3 Run `treefmt --fail-on-change`, `just checks all`, all host evaluations, and `openspec validate decouple-identity-admin-capabilities --strict`; obtain independent identity/security and architecture reviews and leave secrets/ciphertext untouched.
