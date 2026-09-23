# Delta Spec: Nixbuild Build Plane

## ADDED Requirements

### Requirement: Builder SSH trust SHALL be owned by the builder-access aspect
nixbuild.net SSH trust and host configuration SHALL be owned by the builder-access aspect that hosts select explicitly, while substituter policy SHALL remain in the base aspect.

#### Scenario: Host selects the builder-access aspect
- **WHEN** a host selects the builder-access aspect
- **THEN** the nixbuild.net SSH known-hosts and host configuration are provided by the aspect
- **AND** the host assembly does not repeat the nixbuild SSH leaf import or enablement

#### Scenario: Substituter policy remains base-owned
- **WHEN** a host's substituter configuration is inspected
- **THEN** the nixbuild.net substituter priority and trust remain in the base aspect, unchanged by the builder-access aspect
- **AND** selecting builder-access does not alter the shared substituter/trust baseline