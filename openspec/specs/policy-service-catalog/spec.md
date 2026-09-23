# policy-service-catalog Specification

## Purpose
Define the resolved service catalog as the canonical way to address a service across hosts: one entry per stable service ID, so no consumer has to name a physical edge or identity host.

## Requirements

### Requirement: Web policy SHALL expose a canonical service catalog
Canonical web policy SHALL derive one resolved service catalog keyed by stable service ID across all policy owners, and cross-host consumers SHALL use that catalog rather than a physical edge or identity hostname lookup.

#### Scenario: Cross-host consumer resolves Kanidm metadata
- **WHEN** an OCI-hosted service requires Kanidm URL or access metadata
- **THEN** it resolves the `kanidm-admin` service from the policy catalog
- **AND** it does not reference the current identity host name

#### Scenario: Catalog service IDs are unique
- **WHEN** policy owners define services with duplicate catalog keys
- **THEN** policy evaluation fails before generated route or consumer configuration can become ambiguous

### Requirement: Catalog consumers SHALL not use edge-local origins as cross-host addresses
The catalog SHALL expose canonical public URL, access, and health metadata for cross-host consumption, while edge-local origin transport remains owned by the host-local policy resolution path.

#### Scenario: OCI consumes public service metadata
- **WHEN** OCI resolves OIDC enablement or an identity public URL
- **THEN** it reads public/access metadata from the catalog
- **AND** it does not treat a loopback or edge-local origin as a cross-host address

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
