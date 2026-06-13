## 1. Dependency inventory and source surfaces

- [x] 1.1 Audit current OCI image references and current non-flake package source definitions, then map them to their target canonical owners.
  - refs: `modules/services/**/*.nix`, `pkgs/**`, `flake.nix`, `renovate.json`
  - criteria: every current OCI reference and every current non-flake source has an explicit migration target
  - verify: produce a reviewed inventory in the implementation diff or supporting notes

- [x] 1.2 Add canonical repo-level dependency source surfaces for centralized OCI references and nvfetcher-generated non-flake sources.
  - refs: new manifest path for OCI refs, `pkgs/_sources/` or equivalent conventional generated-source path
  - criteria: service and package code can import dependency projections from repo-level paths
  - verify: `nix flake check --no-build`

## 2. Renovate-owned OCI and flake dependency wiring

- [x] 2.1 Update `renovate.json` so Renovate remains the owner of flake inputs and also manages OCI image references from the centralized manifest.
  - criteria: OCI refs are discoverable through a Renovate manager/custom manager and are not left to nvfetcher
  - verify: inspect `renovate.json` diff for manager boundaries and digest-pinning behavior

- [x] 2.2 Fully migrate existing OCI-backed service modules to consume the centralized manifest instead of hardcoded upstream image literals.
  - refs: all current OCI-backed service modules under `modules/services/`
  - criteria: no migrated service keeps a duplicate module-local raw image literal for the same dependency
  - verify: `nix flake check --no-build`

- [x] 2.3 Ensure canonical OCI refs use tag-plus-digest form and validate that the manifest structure supports routine review and future additions.
  - criteria: canonical OCI refs are reproducible and reviewable in one place
  - verify: inspect resulting manifest format and evaluation output where applicable

## 3. nvfetcher-owned non-flake source generation

- [x] 3.1 Add nvfetcher configuration for the current non-flake package sources that require generated version/hash metadata.
  - refs: current custom derivations under `pkgs/`
  - criteria: nvfetcher scope excludes flake inputs and OCI refs
  - verify: nvfetcher configuration clearly maps to non-flake source consumers only

- [x] 3.2 Add committed conventional generated outputs for nvfetcher-managed sources and wire affected package code to consume them.
  - refs: `pkgs/_sources/` or equivalent conventional output path, affected derivation files
  - criteria: package code reads generated metadata instead of hand-maintained version/hash pairs
  - verify: `nix flake check --no-build`

## 4. Scheduled refresh and PR automation

- [x] 4.1 Add scheduled CI automation that regenerates nvfetcher outputs and opens or updates a pull request when generated files change.
  - refs: `.github/workflows/`
  - criteria: workflow is scheduled, reviewable, and does not push source updates directly to `main`
  - verify: inspect workflow triggers, branch/PR flow, and generated-file change detection

- [x] 4.2 Document or encode the operator workflow boundaries so manual refresh/debugging makes clear which dependency classes belong to Renovate versus nvfetcher automation.
  - refs: relevant docs or workflow/readme surfaces touched by the implementation
  - criteria: operators have one clear update path per dependency class
  - verify: docs/workflow diff review

## 5. Validation

- [x] 5.1 Run repository formatting and validation checks for the dependency-management rollout.
  - verify: `nix fmt` and `nix flake check --no-build`

- [x] 5.2 Perform targeted sanity checks on the migrated OCI manifest consumers and nvfetcher-generated package consumers.
  - criteria: affected service and package entrypoints evaluate with the new source-of-truth model
  - verify: run the narrowest relevant build/eval checks discovered during implementation
