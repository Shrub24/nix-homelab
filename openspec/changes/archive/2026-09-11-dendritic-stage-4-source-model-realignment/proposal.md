## Why

Stages 1–3 established sound Dendritic mechanics, but the documented endpoint still conflates two independent concerns: top-level source modules express feature ownership, while deferred NixOS aspects express deployment variability. That conflation has produced a central `modules/flake/aspects.nix`, a misleading permanent-hybrid narrative, and a `dj` selection that does not itself enable DJ.

**Core Value:** Make the source model genuinely feature-oriented without changing the deployed Stage 1–3 host behavior or multiplying the public deployment surface.

## What Changes

- Replace the central `modules/flake/aspects.nix` with auto-discovered, feature-owned flake-parts source modules while preserving every existing `flake.modules.nixos.<name>` contract.
- Distinguish infrastructure support modules (`provenance`, `oci-images`, `fleet-packages`) from host-selected deployment aspects.
- Make selection of the `dj` deployment aspect enable `applications.dj`; keep Engine DJ variants, paths, and secret inputs host-configurable.
- Replace the blanket prohibition on aspect composition with explicit rules for intrinsic composition, policy co-selection, and optional integration.
- Reframe conventional application/service leaves and the enumerated import-tree filter as transitional, while retaining genuinely private lower-level modules as justified exceptions.
- Relax migration tests that pin one central source file or meaningless import order while preserving evaluated behavior, discovery, activation, and negative-mutation checks.
- Correct canonical decisions, specifications, conventions, architecture, plan, context history, and transition analysis before product conversion continues.
- Preserve the typed host registry, flake-parts/import-tree scaffold, public aspect names, host selections, bootstrap/deploy topology, secret policy, and runtime behavior.

### Constraints

- No edits to `.sops.yaml`, `secrets/**`, service endpoints, deployment targets/order, bootstrap contracts, or CI deployment behavior.
- No `specialArgs`, generic compatibility bus, blanket import root, or new dependency.
- Stage 3 is the deployed comparison baseline; unexplained evaluated or runtime differences are blocking.
- This stage corrects the source/aspect model only; it does not convert the remaining application/service trees or redesign established product capabilities.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `repository-structure`: Separate auto-discovered source-feature ownership from explicit deployment-aspect activation and define private lower-level modules as justified exceptions rather than the default endpoint.
- `fleet-infrastructure`: Classify support modules separately from deployment aspects and replace the universal no-aspect-import rule with relationship-specific composition rules.
- `feature-topology`: Require selection of an application deployment aspect to provide top-level application enablement, beginning with DJ.

## Impact

- Primary code: `modules/flake/aspects.nix`, new feature-owned contributors under `modules/flake/`, `modules/flake/dj.nix`, and the redundant DJ enable assignment in `modules/hosts/home-forge/default.nix`.
- Contracts: `tests/check-dendritic-scaffold-contract.sh` and the three modified canonical capabilities.
- Documentation: root architecture/structure/conventions plus `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/context-history.md`, and `docs/dendritic-transition-analysis.md`.
- No new flake inputs, packages, runtime services, secrets, routes, or deploy targets.
