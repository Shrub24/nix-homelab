# Spec: Media Services

## Purpose

Define media service contracts for mount awareness, permission reconciliation, media composition, and Navidrome integration.

## Requirements

### Requirement: Media services remain mount-aware and permission-reconciling
Media services SHALL declare mount prerequisites and SHALL reconcile permissions after promotion/sync operations where required. Permission reconciliation SHALL run as root via a standalone service, decoupled from the beets runner framework.

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

### Requirement: Navidrome reads composed media paths without owning media root
Navidrome SHALL consume application/service-composed media paths, SHALL not own shared media roots via tmpfiles, and SHALL remain aligned with the repository's existing exposure policy.

For this change scope, Navidrome media scope SHALL include `library` and `quarantine`, SHALL exclude `inbox` from the listening surface, and MAY include nixpkgs-provided plugin packages in the Navidrome plugin directory for similarity extensions.

#### Scenario: Navidrome starts after media prerequisites
- **WHEN** Navidrome service is started
- **THEN** it depends on required mount/service ordering and reads configured media/library paths without creating shared media roots itself
- **AND** inbox content is not included in Navidrome media scope
- **AND** the Navidrome plugin directory is populated from `pkgs.navidromePlugins.audiomuseai` before the daemon starts

### Requirement: Music service implementation files SHALL be grouped under a coherent music service subtree
Music-owned leaf service modules SHALL live under `modules/services/music/` while preserving existing public option names and application composition semantics.

#### Scenario: Music service modules are regrouped
- **WHEN** a developer inspects music service implementation files
- **THEN** Navidrome, Beets, slskd, SoulSync, Tagr, and AudioMuse implementation files SHALL be discoverable under `modules/services/music/`
- **AND** existing option namespaces such as `services.navidrome` and `services.beets` SHALL remain stable
- **AND** shared/reusable services such as Syncthing SHALL preserve non-music import compatibility if they are used outside the music stack

### Requirement: Navidrome similarity extensions SHALL use AudioMuse integration without changing exposure policy
When the music stack enables AudioMuseAI-backed similarity, Navidrome SHALL expose the required plugin runtime posture without redesigning the existing Caddy/Cloudflare mTLS/Tailscale exposure model.

#### Scenario: AudioMuse-backed similarity is enabled
- **WHEN** the music stack enables the AudioMuse Navidrome plugin path
- **THEN** Navidrome SHALL enable plugin runtime support and load the AudioMuse plugin from its service state
- **AND** the AudioMuse core service SHALL be reachable by the plugin through the configured host/internal service path
- **AND** this change SHALL NOT require a new public route unless existing exposure policy explicitly composes one

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

### Requirement: Engine DJ consumes one bounded music share
The Engine DJ guest SHALL receive the host-selected music application root as one writable `M:` share. The guest-visible root SHALL contain sibling `library`, `playlists`, `inbox`, `quarantine`, and `Engine Library` paths, where `Engine Library` is a real directory beneath the music root (no separate share, mount tag, or guest junction).

#### Scenario: Engine DJ music share is evaluated
- **WHEN** Engine DJ is enabled on a host with the music application
- **THEN** the guest share is rooted at that host's music application storage root
- **AND** unrelated future media categories outside the music root are not exposed to the guest
- **AND** Engine database backup coverage rides the music storage root (deduplicated with the media backup)
