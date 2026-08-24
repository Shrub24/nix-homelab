# Delta Spec: Repository Structure

## ADDED Requirements

### Requirement: Dead module and helper removal SHALL be gated by zero-consumer proof
Deleting modules, helpers, or global policy values SHALL require a demonstrated zero-consumer proof recorded with the removal, and unwired OCI contract tests SHALL be restored to the check set or explicitly archived with a reason rather than left silently absent.

#### Scenario: A module appears unused
- **WHEN** a module, helper, or global value is proposed for deletion
- **THEN** the change records zero-consumer proof (code graph traces or exhaustive reference search)
- **AND** removal lands only after repository checks still pass without it

#### Scenario: Unwired OCI contract tests are found
- **WHEN** OCI-specific contract tests are discovered unwired from CI or the local check set
- **THEN** they are restored to the check set or explicitly archived with a documented reason
- **AND** their absence does not silently shrink coverage

### Requirement: Module taxonomy and ownership SHALL be documented after implementation
After boundary normalization, the repository SHALL document the module taxonomy and ownership rules (which layer owns conventional secrets, stable interconnections, typed contracts, and host exceptions) in canonical documentation so future changes can be placed correctly.

#### Scenario: An operator adds a new feature
- **WHEN** a future change introduces a feature
- **THEN** the taxonomy/ownership documentation indicates the owning layer and contract surface
- **AND** the documentation matches the implemented repository structure

#### Scenario: Documentation and structure drift
- **WHEN** repository structure changes after the taxonomy is documented
- **THEN** the documentation is updated in the same change window
- **AND** a consistency review or check flags module placement that violates the documented ownership rules
