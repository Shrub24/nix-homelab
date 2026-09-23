## MODIFIED Requirements

### Requirement: Media services remain mount-aware and permission-reconciling
Media services SHALL declare mount prerequisites and SHALL reconcile permissions after promotion/sync operations where required. Permission reconciliation SHALL run as root via a standalone service, decoupled from the beets runner framework. The permission-reconcile implementation body and its tmpfiles ACL rules SHALL be owned by the media-owning leaf service, while the observable reconciliation behavior, unit name, and permissions SHALL remain unchanged.

#### Scenario: Service units enforce mount and permission integrity
- **WHEN** media service units are evaluated
- **THEN** required mounts are declared and permission reconciliation hooks remain part of operational flow

#### Scenario: Permission reconciliation runs as root
- **WHEN** permission reconciliation is triggered (manually or via `OnSuccess=` from a media service)
- **THEN** the `media-permission-reconcile.service` runs as root
- **AND** it applies `chgrp music-ingest`, `chmod 2775/0664`, and `setfacl` rules to library, quarantine, untagged, and approved directories
- **AND** the service is not coupled to the beets runner framework

#### Scenario: Beets services trigger permission reconciliation and Navidrome scan via OnSuccess
- **WHEN** any beets runner service completes successfully
- **THEN** `media-permission-reconcile.service` and `navidrome-scan.service` are triggered via `OnSuccess=` chaining
- **AND** the `onSuccessUnits` list is a module-level option set by the application composition layer, not hardcoded in the beets framework
- **AND** no `ExecStartPost` with privilege escalation is used

### Requirement: Music application composes the media stack
The system SHALL compose Syncthing, Navidrome, slskd, Beets, Tagr, optional SoulSync wiring, and optional AudioMuseAI/Navidrome similarity wiring from the selected music deployment aspect, and SHALL define required collaboration groups for media operations.

For this change scope, role permissions SHALL be explicit: `music-ingest` is the write-capable ingest role for ingest/promotion paths, while `media` is a read-focused consumer role.

#### Scenario: Music composition is enabled
- **WHEN** `applications.music.enable` is configured on a host
- **THEN** the host includes Syncthing, Navidrome, slskd, and Tagr with shared group boundaries (`music-ingest`, `media`)
- **AND** AudioMuseAI may be explicitly enabled as a Navidrome similarity extension without moving music-stack wiring back into the host layer
- **AND** SoulSync may be left disabled without breaking the composed manual-fallback media flow
- **AND** ingest/promotion paths use `music-ingest` write access with `media` read-oriented access

#### Scenario: Music deployment aspect selection provides application enablement
- **WHEN** a host imports the `music` deployment aspect
- **THEN** `applications.music.enable` evaluates to true
- **AND** the host does not repeat that assignment
- **AND** the aspect remains composed from private music service leaves rather than requiring the host to import them

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

### Requirement: Music service implementation files SHALL be grouped under a coherent music service subtree
Music-owned leaf service modules SHALL live under `modules/services/music/` while preserving existing public option names and application composition semantics. These files SHALL remain private leaves imported through the discovered music concern owner, and SHALL NOT be published as deployment aspects.

#### Scenario: Music service modules are regrouped
- **WHEN** a developer inspects music service implementation files
- **THEN** Navidrome, Beets, slskd, SoulSync, Tagr, and AudioMuse implementation files SHALL be discoverable under `modules/services/music/`
- **AND** existing option namespaces such as `services.navidrome` and `services.beets` SHALL remain stable
- **AND** shared/reusable services such as Syncthing SHALL preserve non-music import compatibility if they are used outside the music stack

#### Scenario: Private music leaves stay outside the published aspect set
- **WHEN** the discovered music concern owner imports its private implementation leaves
- **THEN** those leaves under `modules/services/music/` are not published as deployment aspects
- **AND** the four-root top-level discovery boundary remains unchanged

### Requirement: Application injects shared media directories
The music application composition SHALL derive shared directories from the host-supplied application storage root and pass them to dependent services rather than relying on service-local hardcoded shared paths.

#### Scenario: Shared directory paths are provided by the application layer
- **WHEN** a host configures the music application's required storage root
- **THEN** Syncthing, Navidrome, Beets, slskd, Tagr, and other enabled music leaves consume explicitly injected paths
- **AND** a missing required leaf path fails evaluation instead of falling back to a hardcoded filesystem location
