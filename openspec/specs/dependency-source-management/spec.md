# Spec: Dependency Source Management

## Purpose

Define the canonical ownership model and storage contracts for dependency sources — flake inputs, OCI image references, and the locally owned package outputs the package-updates batch refreshes — so updates are predictable, reviewable, and tool-accountable.

## Requirements

### Requirement: Dependency ownership SHALL be explicit by source type

The repository SHALL maintain one canonical ownership model for dependency updates: flake inputs and OCI image references are Renovate-managed, and locally owned `packages.<system>` outputs are updated through nix-fleet's published package-updates contract, backed by `nix-update` and its update-script path. The repository SHALL register exactly the package outputs it owns, and SHALL NOT run a second update engine for that class.

#### Scenario: Operator audits dependency ownership

- **WHEN** an operator reviews how a dependency class is updated
- **THEN** the repository identifies Renovate as the canonical updater for flake inputs and OCI image references
- **AND** the repository identifies the registered package batch as the canonical updater for locally owned package outputs
- **AND** no dependency class is owned by both tools simultaneously

#### Scenario: Locally owned package pins are refreshed

- **WHEN** the registered package batch runs
- **THEN** it updates only the packages declared in its registry
- **AND** it updates through the importing repository's evaluated `nix-update`, using the update-script path
- **AND** it writes no `flake.lock`

### Requirement: OCI image references SHALL be centralized and consumable

OCI image references used by service modules SHALL live in a centralized canonical manifest and SHALL be consumed by modules as projections rather than redefined as module-local raw literals.

#### Scenario: Service module needs an OCI image reference

- **WHEN** a service module configures an OCI-backed container image
- **THEN** the module reads the reference from the canonical OCI manifest
- **AND** the module does not define a separate hardcoded upstream image literal for the same dependency

### Requirement: Canonical OCI references SHALL be digest-pinned

Canonical OCI image references SHALL include both an updateable tag component and a pinned digest component so image pulls remain reproducible.

#### Scenario: OCI image update is reviewed

- **WHEN** an OCI image reference is updated through the canonical manifest
- **THEN** the stored reference includes the image name, tag, and digest together
- **AND** operators can review both the version movement and the immutable digest in the resulting change

### Requirement: Package-update refreshes SHALL be reviewable

Scheduled refresh SHALL run the registered package batch, evaluate the refreshed tree, and present the result as one pull request. Refresh SHALL NOT be acceptance: the repository's validate gate is the acceptance decision, and the batch SHALL NOT write `flake.lock`, publish, or activate anything.

#### Scenario: Scheduled refresh finds newer releases

- **WHEN** the scheduled refresh runs and the batch changes a package pin
- **THEN** the repository opens or updates one pull request carrying the batch's report
- **AND** the refreshed tree is evaluated before the pull request is opened
- **AND** `flake.lock` is unchanged

#### Scenario: Scheduled refresh finds nothing

- **WHEN** the batch changes no file
- **THEN** the workflow reports the batch outcome and opens no pull request
