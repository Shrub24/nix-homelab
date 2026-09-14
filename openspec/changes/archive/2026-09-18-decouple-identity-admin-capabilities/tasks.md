## 1. Baseline and ownership inventory

- [x] 1.1 Capture LA/OCI identity and admin aspect subsets, rendered Kanidm provisioning, OIDC outputs, service units, and SOPS registrations; verify current paths/readership and runtime values are recorded without decrypting secrets.
- [x] 1.2 Inventory every `applications.admin` consumer and classify it as identity-provider, independent admin capability, or justified aggregator; verify no consumer remains unclassified before edits.

## 2. Directional identity contracts

- [x] 2.1 Move Kanidm data-root and identity/provisioning secret options into the identity-provider concern; verify paths, keys, modes, and evaluated Kanidm configuration are unchanged.
- [x] 2.2 Add the provider-owned OIDC provisioning secret-source map keyed by canonical clients; verify missing/extra keys fail and all existing source paths remain byte-identical.
- [x] 2.3 Default identity-client provider URL from canonical web policy and make identity-provider consume the same URL; verify neither writes the other's namespace.
- [x] 2.4 Remove all provider reads of `applications.admin` and admin writes of `services.admin.kanidm`; verify synthetic provider-only and client-only compositions evaluate without missing-option errors.

## 3. Admin capability decomposition

- [x] 3.1 Complete the Termix self-contained aspect and its focused contract test, and extract Vaultwarden into a self-contained aspect contributor with its own runtime/secret contracts; verify the Termix and Vaultwarden subsets each evaluate independently. Quantum is removed from the active module graph on `la-admin-1` and deferred: it is not force-disabled in composition and is not an extraction or completion gate. Any future Quantum re-enable must land as a self-contained concern/aspect that consumes canonical identity contracts and does not restore admin-hub coupling.
- [x] 3.2 Extract Homepage, Gatus, Beszel hub, and Webhook as independent placement aspects after confirming their relationships are catalog data or external/manual use rather than intrinsic composition; verify each meaningful subset independently and introduce no admin-suite bundle.
- [x] 3.3 Migrate Cockpit leaves to canonical web policy, move the residual `/srv/data` operator ACL/reconcile unit and Quantum SSH secret registrations to explicit `la-admin-1` host-local configuration, update LA's explicit aspect selections, and remove `applications.admin` once zero consumers remain; verify no convenience bundle or transitive public-aspect import replaces it.

## 4. Security and behavior equivalence

- [x] 4.1 Compare identity policy, OIDC client IDs/callbacks/scopes/claims, SOPS registrations/readership, Kanidm units, and admin service endpoints before/after; verify no unintended delta.
- [x] 4.2 Add dependency-direction and subset-evaluation ratchets; verify reintroducing a sibling namespace dependency fails the tests.
- [x] 4.3 Run `treefmt --fail-on-change`, `just checks all`, all host evaluations, and `openspec validate decouple-identity-admin-capabilities --strict`; obtain independent identity/security and architecture reviews and leave secrets/ciphertext untouched.

## 5. Documentation acceptance

- [x] 5.1 Add decision D-054 to `docs/decisions.md` recording the revised capability-boundary criterion (independent placement is sufficient but not necessary; security ownership, lifecycle, portability, and independently evaluable contracts justify separation; no convenience bundle) and superseding D-053's `admin-hub` aspect, `applications.admin` flag, aspect count, and mandatory co-selection clause while narrowing D-050's policy co-selection interpretation; verify D-054 is append-only and no historical decision body was rewritten.
- [x] 5.2 Update live current-state architecture docs — `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, `docs/dendritic-transition-analysis.md` — to remove `admin-hub`, `applications.admin`, the mandatory co-selection claim, and stale Stage 7 aspect counts/lists; add the extracted aspects (`termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`) and record Quantum as removed from the active module graph and disabled/deferred with its host-local SSH registrations as recorded debt.
- [x] 5.3 Append a dated entry to `docs/context-history.md`; verify no historical decision body or context-history entry was rewritten.
