# Delta Spec: Provider Owned OIDC URIs

## ADDED Requirements

### Requirement: OIDC client secret-file maps SHALL derive from identity metadata
Host-level OIDC client secret-file maps SHALL be derived from the identity policy's client registry rather than hand-maintained per host, so adding or removing a client updates one registry and derived maps stay consistent.

#### Scenario: A client is added to identity policy
- **WHEN** a new OAuth2 client is declared in identity policy
- **THEN** derived host secret-file maps include the client's scoped secret path without manual host edits
- **AND** a consistency check verifies no declared client is missing from the derived maps

#### Scenario: A client is removed from identity policy
- **WHEN** a client is removed from identity policy
- **THEN** derived maps drop the client
- **AND** tests verify no orphan references remain in host or application configuration
