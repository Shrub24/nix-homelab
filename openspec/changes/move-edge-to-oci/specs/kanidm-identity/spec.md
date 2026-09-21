## ADDED Requirements

### Requirement: Kanidm SHALL own its host-local TLS material

The identity provider SHALL serve its own certificate so that provider readiness does not depend on the public edge's certificate lifecycle, on an edge-only reader group, or on a reverse proxy co-located with it. The public identity the service publishes SHALL remain the canonical provider URL.

#### Scenario: Provider starts on a host that is not the edge

- **WHEN** the identity provider starts on a host that does not serve the edge role
- **THEN** its TLS chain and key resolve to provider-owned paths under its state directory
- **AND** its unit requires no group created only by the edge role
- **AND** its unit orders after no reverse proxy that the host does not run

#### Scenario: A provider-owned certificate exists after first start

- **WHEN** the provider's certificate material is absent
- **THEN** the host generates a pair owned by the service user before the server starts
- **AND** the generation is idempotent across restarts

#### Scenario: Provider bind matches the published route port

- **WHEN** the provider's configured bind port differs from the published upstream port of its route
- **THEN** evaluation fails with both values named

#### Scenario: Certificate paths stay overridable

- **WHEN** a host supplies its own certificate and key paths
- **THEN** the provider serves those instead of the generated pair, and the generated pair is not required
