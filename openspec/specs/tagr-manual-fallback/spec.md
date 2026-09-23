# tagr-manual-fallback Specification

## Purpose
Define the operator-invoked fallback for manual metadata and album-art correction: a Tagr service that writes against the canonical library and quarantine paths and requires host-scoped credentials.
## Requirements
### Requirement: Tagr manual metadata fallback service is available on oci-melb-1
The system SHALL provide a Tagr web service on `oci-melb-1` as an operator-invoked fallback for manual metadata and album-art correction on canonical music files.

#### Scenario: Tagr service module is enabled via music composition
- **WHEN** `applications.music.enable` is configured on `oci-melb-1`
- **THEN** the host renders a Tagr service configuration with explicit data and media path wiring suitable for manual edits

### Requirement: Tagr writes metadata against canonical library and quarantine paths
Tagr SHALL operate only on the canonical library and quarantine paths under `/srv/media` and SHALL keep application state under `/srv/data/tagr`.

#### Scenario: Tagr container runtime is rendered
- **WHEN** Tagr container mounts are evaluated
- **THEN** metadata edit operations target files under `/srv/media/library` and `/srv/media/quarantine`
- **AND** Tagr does not scan unrelated subdirectories under `/srv/media`
- **AND** Tagr state and database assets are persisted under `/srv/data/tagr`

#### Scenario: Tagr edits existing media files
- **WHEN** Tagr writes updated metadata or cover art into canonical library or quarantine files
- **THEN** the canonical music library and quarantine roots provide persistent group-write/default-ACL policy compatible with the Tagr runtime
- **AND** newly added files inherit write-capable group access without relying on Tagr-specific recurring permission reconciliation
- **AND** the container runtime identity is explicitly aligned to host `music-ingest`/`media` group IDs so host ACL checks succeed predictably

#### Scenario: Syncthing version archives are masked from Tagr scans
- **WHEN** Syncthing versioning directories exist under library or quarantine paths
- **THEN** Syncthing stores version archives in media-local paths outside the library and quarantine trees
- **AND** Tagr does not scan `.stversions` content as editable music folders

### Requirement: Tagr access requires host-scoped credentials
Tagr authentication/session values SHALL be sourced from host-scoped secrets/templates and SHALL NOT require shared secret scope.

#### Scenario: Tagr auth template is rendered
- **WHEN** `oci-melb-1` host secrets are present
- **THEN** Tagr receives `AUTH_SECRET`, `AUTH_USER`, and `AUTH_PASSWORD` from host-scoped secret-backed templates

