## ADDED Requirements

### Requirement: Canonical host identity SHALL have one typed authority

Each fleet host SHALL be keyed by one stable canonical host ID whose typed record owns its target system, Tailscale identity, and deferred NixOS composition. Network hostname and derived private FQDNs SHALL originate from that record rather than independent literals.

#### Scenario: Host identity is consumed across concerns

- **WHEN** host composition, deployment metadata, web routing, or an internal service contract references a fleet host
- **THEN** the reference resolves against the canonical host ID set
- **AND** target system and Tailscale identity are not independently restated by those consumers

#### Scenario: Metadata names an unknown host

- **WHEN** deployment or host-backed routing metadata references an unknown canonical host ID
- **THEN** validation fails with the referencing concern and host ID

### Requirement: Host contributors SHALL register themselves through discovery

Each host source contributor SHALL declare its own typed host record and deferred NixOS composition through recursive top-level discovery. Generic registry/materialization code SHALL not enumerate concrete host names.

#### Scenario: A host is added

- **WHEN** an operator adds a valid discovered host contributor
- **THEN** the corresponding `nixosConfigurations.<host>` and eligible bootstrap projection are materialized without editing a central concrete-host table
- **AND** workload placement remains explicit in that host's aspect selection
