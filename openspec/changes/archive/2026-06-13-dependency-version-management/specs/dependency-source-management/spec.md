## ADDED Requirements

### Requirement: Dependency ownership SHALL be explicit by source type
The repository SHALL maintain one canonical ownership model for dependency updates: flake inputs and OCI image references are Renovate-managed, while non-flake package sources are nvfetcher-managed.

#### Scenario: Operator audits dependency ownership
- **WHEN** an operator reviews how a dependency class is updated
- **THEN** the repository identifies Renovate as the canonical updater for flake inputs and OCI image references
- **AND** the repository identifies nvfetcher as the canonical updater for non-flake package source metadata
- **AND** no dependency class is owned by both tools simultaneously

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

### Requirement: Non-flake package sources SHALL use committed generated metadata
Non-flake upstream package sources that require version/hash materialization for custom derivations SHALL be represented through nvfetcher-generated committed metadata.

#### Scenario: Custom derivation consumes upstream non-flake source
- **WHEN** a package derivation needs an upstream version and hash for a non-flake source
- **THEN** the derivation reads that source metadata from committed nvfetcher-generated outputs
- **AND** operators do not need to hand-edit version and hash pairs in multiple places

### Requirement: Generated source refreshes SHALL be reviewable
The repository SHALL provide an automated workflow that refreshes nvfetcher-managed metadata on a schedule and proposes the resulting changes through a pull request.

#### Scenario: Scheduled nvfetcher refresh finds updates
- **WHEN** scheduled automation regenerates nvfetcher outputs and detects changes
- **THEN** the automation creates or updates a pull request containing the generated metadata changes
- **AND** the refresh does not push dependency updates directly to `main`
