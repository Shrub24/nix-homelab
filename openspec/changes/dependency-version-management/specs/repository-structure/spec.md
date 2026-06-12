## ADDED Requirements

### Requirement: Dependency metadata SHALL live in canonical repo-level locations
Repository structure SHALL place canonical OCI image metadata and nvfetcher-generated non-flake source metadata in explicit repo-level locations that are reusable across hosts and services.

#### Scenario: Operator inspects dependency metadata placement
- **WHEN** an operator reviews where OCI image refs and generated non-flake source metadata live
- **THEN** those artifacts are stored in canonical repo-level paths rather than host-local files
- **AND** service and package consumers can import those paths without redefining equivalent literals

### Requirement: Generated source artifacts SHALL remain safe to commit
Committed generated dependency metadata SHALL be limited to reproducible source information required for evaluation and packaging, without embedding secrets or host-specific runtime state.

#### Scenario: Generated source files are reviewed
- **WHEN** nvfetcher-generated files are committed to the repository
- **THEN** they contain version/source/hash metadata needed by package consumers
- **AND** they do not introduce secrets, host-scoped credentials, or mutable runtime-only state into version control
