## ADDED Requirements

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
