## ADDED Requirements

### Requirement: Paperless group seeding SHALL use the sealed service environment
The OIDC group-seeding unit SHALL source `PAPERLESS_SECRET_KEY` from the same sealed SOPS environment file as the Paperless service, so its Django process starts without Paperless's insecure default key.

#### Scenario: OIDC group seeding runs
- **WHEN** the OIDC group-seeding unit runs after Paperless starts
- **THEN** it receives `PAPERLESS_SECRET_KEY` from the same sealed environment file as the service
- **AND** its Django process starts without using Paperless's insecure default key

### Requirement: Paperless SHALL preserve duplicate rejection across the v3 upgrade
Paperless SHALL reject duplicate documents during consumption, preserving the v2 default rather than accepting additional copies under the v3 default.

#### Scenario: A duplicate document is consumed
- **WHEN** a document matching an existing Paperless document is submitted for consumption
- **THEN** Paperless rejects the duplicate
- **AND** it does not add another document record
