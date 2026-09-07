## MODIFIED Requirements

### Requirement: Music application composes the media stack
The system SHALL compose Syncthing, Navidrome, slskd, Beets, Tagr, optional SoulSync wiring, and optional AudioMuseAI/Navidrome similarity wiring from the music application composition root and SHALL define required collaboration groups for media operations.

For this change scope, role permissions SHALL be explicit: `music-ingest` is the write-capable ingest role for ingest/promotion paths, while `media` is a read-focused consumer role.

#### Scenario: Music composition is enabled
- **WHEN** `applications.music.enable` is configured on a host
- **THEN** the host includes Syncthing, Navidrome, slskd, and Tagr with shared group boundaries (`music-ingest`, `media`)
- **AND** AudioMuseAI may be explicitly enabled as a Navidrome similarity extension without moving music-stack wiring back into the host layer
- **AND** SoulSync may be left disabled without breaking the composed manual-fallback media flow
- **AND** ingest/promotion paths use `music-ingest` write access with `media` read-oriented access

#### Scenario: Home-forge uses the canonical media root
- **WHEN** the music application is enabled on `home-forge`
- **THEN** `applications.music.storageRoot` is the host-selected `/srv/storage/media/music` with no physical music path in fleet policy
- **AND** the application derives sibling `library/`, `playlists/`, `inbox/`, `quarantine/`, and `.versions/` subtrees beneath it
- **AND** Navidrome and Syncthing use the derived `library/` path, while Engine `M:` shares the whole music storage root
- **AND** Engine DJ's library is a real `Engine Library` directory at `storageRoot/Engine Library`, with no separate share, mount tag, or guest junction

#### Scenario: Traktor sync is removed
- **WHEN** `applications.music` is evaluated after this change
- **THEN** no Traktor-specific playlist model or automatic Traktor workflow is composed by the music application
- **AND** the temporary M3U-to-iTunes worker remains independently host-composed pending its separately scoped replacement

#### Scenario: AudioMuse compute composed on home-forge over remote OCI Postgres
- **WHEN** `applications.music` composes AudioMuse after this change
- **THEN** AudioMuse web, worker, and local Redis run on `home-forge`
- **AND** AudioMuse's PostgreSQL database is remote in OCI's shared Postgres over Tailscale (tailnet-only + SCRAM), matching the existing accepted Arch-workstation pattern
- **AND** the database-side role password is read by OCI Postgres from `secrets/services/postgres-shared.yaml` at `roles/audiomuse/password` (OCI-only file), while home-forge AudioMuse reads the client-side password from `secrets/applications/music.yaml` at `audiomuse/postgres_password` with the existing value preserved

#### Scenario: Navidrome runs stock with cache-preserving plugin integration
- **WHEN** `services.navidrome` is configured on `home-forge` with AudioMuseAI support
- **THEN** no `services.navidrome.plugins = [ pkgs.navidromePlugins.audiomuseai ]` rebuild path is used
- **AND** the packaged WASM `.ndp` is symlinked into `${dataDir}/plugins` declaratively via tmpfiles and bind-mounted into nixpkgs' fixed plugin folder only for Navidrome, with `Plugins.Enabled/AutoReload/Agents` set, keeping stock cache-substitutable Navidrome

### Requirement: Shared media roots are app-owned and created via tmpfiles
The system SHALL require each host to select the physical storage root for the music application. The music application SHALL derive and create its `library`, `playlists`, `inbox`, `quarantine`, and `.versions` subtrees via `systemd.tmpfiles.rules`; fleet policy and leaf services SHALL NOT select a physical shared-media root.

#### Scenario: Shared music paths are reconciled
- **WHEN** the music application is enabled with a host-selected storage root
- **THEN** its conventional shared subtrees are present beneath that root with declared ownership and modes
- **AND** enabled leaf services receive their required paths from the application composition

### Requirement: Application injects shared media directories
`modules/applications/music/` SHALL derive shared directories from the host-supplied application storage root and pass them to dependent services rather than relying on service-local hardcoded shared paths.

#### Scenario: Shared directory paths are provided by the application layer
- **WHEN** a host configures the music application's required storage root
- **THEN** Syncthing, Navidrome, Beets, slskd, Tagr, and other enabled music leaves consume explicitly injected paths
- **AND** a missing required leaf path fails evaluation instead of falling back to a hardcoded filesystem location

### Requirement: Media-stack service backups SHALL declare service state coverage and media policy
Stateful media-stack services SHALL support backup coverage for their mutable service state. Coverage for music payloads beneath the host-selected application storage root SHALL be controlled by host backup policy.

#### Scenario: Music-stack backup scope is reviewed
- **WHEN** backup coverage is inspected for the music application stack
- **THEN** service configuration, databases, and runtime state can be included beneath managed service-state roots
- **AND** music library and inbox payloads follow the host's declared storage and backup scope

## ADDED Requirements

### Requirement: Engine DJ consumes one bounded music share
The Engine DJ guest SHALL receive the host-selected music application root as one writable `M:` share. The guest-visible root SHALL contain sibling `library`, `playlists`, `inbox`, `quarantine`, and `Engine Library` paths, where `Engine Library` is a real directory beneath the music root (no separate share, mount tag, or guest junction).

#### Scenario: Engine DJ music share is evaluated
- **WHEN** Engine DJ is enabled on a host with the music application
- **THEN** the guest share is rooted at that host's music application storage root
- **AND** unrelated future media categories outside the music root are not exposed to the guest
- **AND** Engine database backup coverage rides the music storage root (deduplicated with the media backup)
