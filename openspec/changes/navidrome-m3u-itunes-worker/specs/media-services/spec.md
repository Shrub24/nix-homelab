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
- **THEN** the engine export writes playlists directly into the Engine library database under `<musicStorageRoot>/Engine Library/Database2`
- **AND** the worker's M3U input and SQLite state remain outside the media library
- **AND** the music application remains free of Traktor/NML composition

#### Scenario: Music deployment aspect selection provides application enablement
- **WHEN** a host imports the `music` deployment aspect
- **THEN** `applications.music.enable` evaluates to true
- **AND** the host does not repeat that assignment
- **AND** the aspect remains composed from private music service leaves rather than requiring the host to import them

#### Scenario: AudioMuse compute composed on home-forge beside its local PostgreSQL
- **WHEN** `applications.music` composes AudioMuse
- **THEN** AudioMuse web, worker, and local Redis run on `home-forge`
- **AND** AudioMuse's database is the host's own PostgreSQL cluster (`services.postgres.instances.forge`), reached over the pinned podman bridge network with SCRAM authentication and an `allowedCIDRs` rule matching that subnet
- **AND** the credential is declared once in the consumer registration (`services.postgres.consumers.audiomuse.password` → `secrets/applications/music.yaml` key `audiomuse/postgres_password`), so the provider provisions the role from the same file the consumer authenticates with
- **AND** the database is written to the host's backup export path, so the existing restic state-backup job covers it

#### Scenario: Navidrome runs stock with cache-preserving plugin integration
- **WHEN** `services.navidrome` is configured on `home-forge` with AudioMuseAI support
- **THEN** no `services.navidrome.plugins = [ pkgs.navidromePlugins.audiomuseai ]` rebuild path is used
- **AND** the packaged WASM `.ndp` is symlinked into `${dataDir}/plugins` declaratively via tmpfiles and bind-mounted into nixpkgs' fixed plugin folder only for Navidrome, with `Plugins.Enabled/AutoReload/Agents` set, keeping stock cache-substitutable Navidrome
