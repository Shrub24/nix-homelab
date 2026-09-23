## ADDED Requirements

### Requirement: Extension points SHALL be consumer-registered

A capability that serves multiple unrelated services SHALL expose a typed registry that those services contribute to from their own modules, instead of holding a per-consumer option block or a hand-maintained list of participants inside the capability.

#### Scenario: A capability is extended by a new participant

- **WHEN** a service begins using a shared capability (backups, notification monitoring, a database cluster)
- **THEN** the service's own module SHALL register the requirement with the capability
- **AND** the capability's module SHALL NOT be edited to accommodate the new participant
- **AND** the capability SHALL name no participant
- **AND** where only the capability's provider host can create the registration (a database role must be created where the cluster runs), that host's configuration SHALL carry it and the consuming service SHALL read the capability's resolved endpoint

#### Scenario: A registration does not correspond to reality

- **WHEN** a registration references something that does not exist (an unknown instance, a phantom systemd unit, a missing credential)
- **THEN** evaluation SHALL fail with a named error identifying the registration and the reason
- **AND** the failure SHALL occur before activation rather than surfacing as a silent no-op

#### Scenario: Existing registries are reviewed

- **WHEN** the fleet's shared capabilities are inspected
- **THEN** `services.state-backups.services.<name>`, `services.notification-daemon.monitor.units.<unit>`, and the PostgreSQL consumer registry SHALL all follow this pattern
- **AND** a capability that instead holds a participant list SHALL be recorded as debt rather than left unspecified
