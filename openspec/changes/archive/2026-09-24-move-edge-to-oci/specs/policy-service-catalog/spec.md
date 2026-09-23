## ADDED Requirements

### Requirement: Web policy SHALL project provided routes to their provider host

Resolved policy SHALL give a host the routes it provides — those whose origin resolves to that host — with their scheme, port, and declared transport, so provider-side rendering does not read the edge's route table and does not restate the port.

#### Scenario: An origin host sees the routes it provides

- **WHEN** an origin host resolves canonical policy
- **THEN** it receives the services whose origin resolves to that host
- **AND** each entry carries the scheme, port, and exposure mode declared by policy

#### Scenario: The cross-host catalog stays host-free

- **WHEN** any consumer reads the canonical catalog
- **THEN** it still receives no origin host for a published service
- **AND** the provider projection is not visible through the catalog

#### Scenario: A host that provides nothing

- **WHEN** a host provides no route
- **THEN** its provided-route projection is empty and nothing is rendered from it
