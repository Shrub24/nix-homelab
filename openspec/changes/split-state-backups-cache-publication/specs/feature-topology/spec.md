## ADDED Requirements

### Requirement: Capabilities with distinct state and security lifecycles SHALL use explicit composition

Capabilities with distinct state models, credentials, failure semantics, or plausible independent placement SHALL remain separate deployment aspects even when every current host selects them together. Common deployment policy SHALL be expressed through explicit co-selection rather than merged ownership.

#### Scenario: Current hosts use state backup and cache publication

- **WHEN** the three active hosts require both capabilities
- **THEN** each host explicitly selects `state-backups` and `cache-publisher`
- **AND** neither aspect imports or silently enables the other
- **AND** no compatibility bundle provides a second selection authority
