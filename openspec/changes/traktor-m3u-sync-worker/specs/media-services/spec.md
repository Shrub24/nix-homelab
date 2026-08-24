## ADDED Requirements

### Requirement: Music stack SHALL provide a separate Traktor playlist workspace
When Traktor playlist synchronization is enabled, the music stack SHALL provide a separate media playlist workspace outside service-local state and outside inbox/quarantine processing paths.

#### Scenario: Music stack composes Traktor playlist sync paths
- **WHEN** `applications.music` composes the Traktor playlist sync worker
- **THEN** the Traktor collection input path SHALL be under `/srv/media/traktor/`
- **AND** generated and curated playlist files SHALL be under `/srv/media/playlists/traktor/`
- **AND** the playlist workspace SHALL NOT be treated as a Beets inbox or quarantine path
- **AND** the paths SHALL follow the existing music-stack ACL model: write access through `music-ingest` and read access through `media`

### Requirement: Traktor playlist sync SHALL be optional within the music stack
The music stack SHALL compose Traktor playlist sync as an optional music feature without requiring host files to know upstream implementation details.

#### Scenario: Traktor playlist sync is enabled for a host
- **WHEN** the host enables the Traktor playlist sync feature through the music application or service contract
- **THEN** the worker package, configuration, and manual systemd units SHALL be available on that host
- **AND** existing Navidrome, Beets, Syncthing, and AudioMuse configuration SHALL continue to evaluate without requiring playlist sync
