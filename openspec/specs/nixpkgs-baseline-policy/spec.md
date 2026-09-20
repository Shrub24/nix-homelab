# nixpkgs-baseline-policy Specification

## Purpose
Fix the package baseline this repository evaluates against: one primary nixpkgs input tracking nixos-unstable, no pre-provisioned fallback inputs, and unchanged state-version semantics.
## Requirements
### Requirement: Default nixpkgs baseline is unstable
Active fleet code SHALL use a single primary `nixpkgs` flake input pinned to `nixos-unstable` as the default package baseline.

#### Scenario: Flake input baseline is evaluated
- **WHEN** `flake.nix` inputs are reviewed for active host/package outputs
- **THEN** primary `nixpkgs` resolves to `github:NixOS/nixpkgs/nixos-unstable`

### Requirement: Secondary fallback inputs are not pre-provisioned
The repository SHALL NOT keep an unused stable fallback nixpkgs input in active flake wiring; stable exceptions MUST be introduced only when concretely needed.

#### Scenario: No current exception exists
- **WHEN** active flake inputs are evaluated
- **THEN** no unused stable fallback nixpkgs input is present

#### Scenario: Future concrete exception is identified
- **WHEN** a package/module regression requires temporary divergence
- **THEN** a targeted additional nixpkgs input MAY be added with explicit change documentation

### Requirement: Existing state-version semantics remain unchanged
Changing default package baseline MUST NOT implicitly change host `system.stateVersion` values.

#### Scenario: Baseline migration is applied
- **WHEN** host configurations are updated to unstable-default package sourcing
- **THEN** existing `system.stateVersion` values remain unchanged unless explicitly planned in a separate change

