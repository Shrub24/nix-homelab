## ADDED Requirements

### Requirement: Traktor playlist sync SHALL expose manual export and import jobs
The system SHALL provide manual systemd-triggered Traktor playlist synchronization jobs (`traktor-m3u-sync-export.service` and `traktor-m3u-sync-import.service`) for exporting Traktor `collection.nml` playlists to M3U and importing curated M3U playlists back into a Traktor import sandbox.

#### Scenario: Operator triggers playlist export manually
- **WHEN** the operator starts `traktor-m3u-sync-export.service`
- **THEN** the worker reads the configured `collection.nml`
- **AND** writes generated M3U playlists under the configured export directory
- **AND** does not require any timer or path watcher to run

#### Scenario: Operator triggers playlist import manually
- **WHEN** the operator starts `traktor-m3u-sync-import.service`
- **THEN** the worker reads curated M3U playlists from the configured import directory
- **AND** writes changes only through the upstream import/sandbox behavior
- **AND** relies on upstream backup/validation behavior before replacing `collection.nml`

### Requirement: Traktor playlist sync SHALL keep collection and playlist paths explicit
The system SHALL configure explicit paths for the Syncthing-sourced Traktor collection file, exported playlists, import input playlists, and host-side music root mapping.

#### Scenario: Paths are evaluated for the music host
- **WHEN** the music stack is evaluated for `oci-melb-1`
- **THEN** the Traktor collection path resolves to `/srv/media/traktor/collection.nml`
- **AND** the playlist workspace resolves under `/srv/media/playlists/traktor/`
- **AND** export output and import input paths are distinct
- **AND** the Traktor-side music root mapping remains explicitly configurable

### Requirement: Traktor playlist import SHALL remain non-automated for the initial iteration
The system SHALL NOT automatically run Traktor playlist import from timers, path units, Syncthing hooks, or service restart side effects in the initial deployment.

#### Scenario: The host boots or receives synced playlist files
- **WHEN** the host starts or Syncthing updates the collection or playlist directories
- **THEN** no Traktor import job is started automatically because the upstream oneshot units are not timer/path activated
- **AND** import occurs only when the operator explicitly starts the import unit
