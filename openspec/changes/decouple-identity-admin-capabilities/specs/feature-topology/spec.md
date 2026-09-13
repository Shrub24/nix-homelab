## ADDED Requirements

### Requirement: Independently portable aspects SHALL NOT communicate through sibling implementation namespaces

Independently placeable capabilities SHALL expose directional typed contracts and SHALL NOT require mutual reads or writes across sibling implementation option namespaces merely because current host policy co-selects them.

#### Scenario: Capability subset is evaluated

- **WHEN** an independently meaningful capability is selected without its currently colocated siblings
- **THEN** its option declarations and intrinsic implementation evaluate independently
- **AND** any real external dependency fails through a named contract assertion
- **AND** evaluation does not fail because a sibling-owned namespace is absent

#### Scenario: Current colocation changes

- **WHEN** one capability moves to another host
- **THEN** its implementation, state contract, and secrets move with its own aspect
- **AND** colocated sibling aspects require no internal rewiring unless they explicitly consume its public contract
