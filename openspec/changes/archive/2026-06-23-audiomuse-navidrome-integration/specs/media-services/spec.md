# Delta Spec: Media Services

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

### Requirement: Navidrome reads composed media paths without owning media root
Navidrome SHALL consume application/service-composed media paths, SHALL not own shared media roots via tmpfiles, and SHALL remain aligned with the repository's existing exposure policy.

For this change scope, Navidrome media scope SHALL include `library` and `quarantine`, SHALL exclude `inbox` from the listening surface, and MAY include nixpkgs-provided plugin packages in the Navidrome plugin directory for similarity extensions.

#### Scenario: Navidrome starts after media prerequisites
- **WHEN** Navidrome service is started
- **THEN** it depends on required mount/service ordering and reads configured media/library paths without creating shared media roots itself
- **AND** inbox content is not included in Navidrome media scope
- **AND** the Navidrome plugin directory is populated from `pkgs.navidromePlugins.audiomuseai` before the daemon starts

## ADDED Requirements

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
