## Purpose

Define the narrow private transport contracts through which cross-host PostgreSQL and Niks3-write consumers resolve providers without duplicating machine identity.

## ADDED Requirements

### Requirement: Internal contracts SHALL reference canonical host identities

Each internal service contract SHALL identify its provider by canonical fleet host ID and SHALL derive transport hostnames from that host's canonical Tailscale identity. The contract SHALL NOT independently redefine machine identity or target system.

#### Scenario: PostgreSQL endpoint is resolved

- **WHEN** a consumer resolves the PostgreSQL internal contract
- **THEN** it receives the provider host ID, derived private hostname, and port
- **AND** the provider ID resolves to exactly one canonical host record

#### Scenario: Unknown provider is configured

- **WHEN** an internal contract references a host ID absent from the canonical host registry
- **THEN** evaluation fails with an assertion naming the contract and unknown host ID

### Requirement: Internal contracts SHALL cover only demonstrated private transports

The internal contract surface SHALL define PostgreSQL and the private Niks3 write API. Public cache reads, identity URLs, and ntfy URLs SHALL continue to use their existing canonical policy authorities.

#### Scenario: Niks3 read and write paths are resolved

- **WHEN** cache consumers and publishers evaluate
- **THEN** consumers retain the canonical cache read/substituter contract
- **AND** publishers resolve the private Niks3 write endpoint from `niks3Write`
- **AND** no second identity or ntfy endpoint authority is introduced

### Requirement: Contract providers SHALL provide the declared capability

Each internal contract provider SHALL select the deployment aspect that implements the declared service.

#### Scenario: Provider placement drifts

- **WHEN** PostgreSQL or Niks3-write names a provider host that does not select the matching provider aspect
- **THEN** fleet validation fails and names the missing aspect/provider relationship
- **AND** consumer configuration is not silently redirected
