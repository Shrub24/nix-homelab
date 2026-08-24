## MODIFIED Requirements

### Requirement: Paperless is configured with native SECRET_KEY
The Paperless service and custom Paperless Django maintenance units SHALL source `PAPERLESS_SECRET_KEY` from the sealed SOPS environment file. Paperless SHALL start without manual key generation.

#### Scenario: Paperless service is configured with native SECRET_KEY
- **WHEN** the module is evaluated
- **THEN** the upstream Paperless units source `PAPERLESS_SECRET_KEY` from a sealed SOPS environment file
- **AND** Paperless starts without manual key generation

#### Scenario: OIDC group seeding runs
- **WHEN** the OIDC group-seeding unit runs after Paperless starts
- **THEN** it receives `PAPERLESS_SECRET_KEY` from the same sealed environment file
- **AND** its Django process starts without using Paperless's insecure default key

## ADDED Requirements

### Requirement: Paperless SHALL preserve duplicate rejection across the v3 upgrade
Paperless SHALL reject duplicate documents during consumption, preserving the v2 default rather than accepting additional copies under the v3 default.

#### Scenario: A duplicate document is consumed
- **WHEN** a document matching an existing Paperless document is submitted for consumption
- **THEN** Paperless rejects the duplicate
- **AND** it does not add another document record
