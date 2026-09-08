## MODIFIED Requirements

### Requirement: Music application composes the media stack
The system SHALL compose Syncthing, Navidrome, slskd, Beets, Tagr, optional SoulSync wiring, and optional AudioMuseAI/Navidrome similarity wiring from the music application composition root and SHALL define required collaboration groups for media operations.

For this change scope, role permissions SHALL be explicit: `music-ingest` is the write-capable ingest role for ingest/promotion paths, while `media` is a read-focused consumer role.

#### Scenario: Music composition is enabled
- **WHEN** `applications.music.enable` is configured on a host
- **THEN** the host includes Syncthing, Navidrome, slskd, and Tagr with shared group boundaries (`music-ingest`, `media`)
- **AND** ingest/promotion paths use `music-ingest` write access with `media` read-oriented access

#### Scenario: Home-forge uses the canonical media root
- **WHEN** the music application is enabled on `home-forge`
- **THEN** the music application root is `/srv/storage/media/music`
- **AND** Navidrome, Engine `M:`, and Syncthing use `/srv/storage/media/music/library`

#### Scenario: Traktor sync is removed
- **WHEN** the operator enables the Navidrome playlist-sync worker on home-forge
- **THEN** the engine export writes playlists directly into the Engine library database under `/srv/data/engine-dj/library/Database2`
- **AND** the worker's M3U input and SQLite state remain outside the media library
- **AND** the music application remains free of Traktor/NML composition
