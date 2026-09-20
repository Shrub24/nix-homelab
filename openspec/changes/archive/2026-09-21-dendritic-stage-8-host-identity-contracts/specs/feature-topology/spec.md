## ADDED Requirements

### Requirement: Source organization SHALL express feature ownership independently of aspect granularity

Normal first-party contributors SHALL be organized under semantic feature or domain paths while participating uniformly in the top-level module system. Filesystem location SHALL NOT imply deployment selection, and multiple source contributors MAY merge into one explicit deployment aspect.

#### Scenario: Feature contributor is relocated from the flake directory

- **WHEN** a settled identity, notification, cache, admin, music, networking, or host contributor moves to its semantic domain path
- **THEN** recursive discovery continues to evaluate it at the top-level flake-parts layer
- **AND** its public deployment aspect and host selections remain unchanged
- **AND** private implementation leaves remain undiscovered behind explicit private paths

### Requirement: Shared values SHALL have one authoritative owner

Stable host identity, internal transport endpoints, web routes, and feature policy SHALL each have one declared authority. Consumers SHALL reference the corresponding contract rather than restating values in host or sibling feature configuration.

#### Scenario: A provider capability moves hosts

- **WHEN** PostgreSQL or Niks3 server placement changes
- **THEN** consumer endpoints change through the relevant internal contract
- **AND** consumer modules contain no former provider-host literal to update
