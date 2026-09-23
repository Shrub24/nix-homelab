## Why

The repository's current host and module structure contains dead paths, stale architectural guidance, and duplicated wiring that would obscure a Dendritic migration and make equivalence failures harder to diagnose. Establish a small, behavior-preserving baseline before introducing flake-parts, import-tree, and aspect-based host composition.

**Core Value:** Reduce the Dendritic transition's review surface without changing the configuration or operation of any fleet host.

## What Changes

- Remove repository paths and helpers proven to have no consumers.
- Remove only redundant module declarations whose evaluated host output remains unchanged.
- Correct stale comments and documentation, including the completed music move and the accepted two-file Audiomuse credential model.
- Record that D-030's plain-flake restriction will be superseded by a staged Dendritic transition using `flake.modules`, a typed host registry, and all-host equivalence gates.
- Record `nix-fleet` as a future code-only sharing boundary for proven reusable aspects; topology, web policy, OpenTofu, deployment metadata, and secrets remain owned by `nix-homelab`.
- Reconcile OpenSpec state conservatively: archive only completed changes after strict validation, and leave operator-gated work active.
- Repair the Kanidm restore contract's optional 1.10 seed discovery so an empty store glob reaches the test's explicit skip branch under `pipefail`.
- Preserve OCI music-cutover soak residue and defer all runtime policy, secret-readership, deployment, and topology changes.

Key constraints:

- No host runtime behavior, deployment ordering, secret scope, or service placement may change.
- Agents must not decrypt or edit encrypted secrets.
- Every Nix cleanup must pass host-scoped evaluation and produce no unexplained configuration drift.
- The next scaffold change remains separate and must use flake-parts plus `denful/import-tree`; `flake-file`, Den, and topology extraction remain deferred.

## Capabilities

### New Capabilities

None. This is a preparatory refactor and documentation change.

### Modified Capabilities

None. Existing capability requirements remain unchanged until the Stage 1 scaffold change.

## Impact

- Removes dead application/task-runner/helper code and redundant host declarations.
- Updates `docs/dendritic-transition-analysis.md`, `docs/decisions.md`, and directly affected structural documentation.
- May archive `normalize-music-storage-topology` after its own strict validation succeeds.
- Does not modify `.sops.yaml`, encrypted files, host topology, web policy, OpenTofu, flake inputs, or production services.
