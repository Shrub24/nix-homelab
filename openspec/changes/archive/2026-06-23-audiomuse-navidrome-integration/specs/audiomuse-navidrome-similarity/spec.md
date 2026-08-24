# Delta Spec: AudioMuse Navidrome Similarity

## ADDED Requirements

### Requirement: AudioMuseAI SHALL extend Navidrome similarity behavior for Symfonium
The system SHALL integrate AudioMuseAI as a Navidrome-facing music intelligence extension so Symfonium can use similar-track and radio behavior through the existing Navidrome listening path.

#### Scenario: Symfonium requests similar or radio tracks
- **WHEN** Symfonium uses Navidrome/OpenSubsonic similarity or radio behavior against the deployed music stack
- **THEN** Navidrome SHALL have the AudioMuse plugin runtime path available
- **AND** the plugin SHALL be able to reach the AudioMuse core API after operator bootstrap is complete
- **AND** the end-user validation target SHALL be actual Symfonium similar/radio behavior, not only container health

### Requirement: AudioMuseAI SHALL be explicitly enabled from the music composition root
AudioMuseAI SHALL be an optional feature under `applications.music` rather than an implicit always-on dependency of the base music stack.

#### Scenario: AudioMuse is enabled for a host
- **WHEN** the music application enables AudioMuseAI for a host
- **THEN** the host SHALL compose the AudioMuse core service and Navidrome plugin wiring from the application layer
- **AND** host assembly SHALL remain focused on feature enablement and secret source binding rather than service-internal wiring

#### Scenario: AudioMuse is not enabled for a host
- **WHEN** `applications.music` is enabled without the AudioMuse feature
- **THEN** the existing Navidrome/Syncthing/Beets/Tagr music flow SHALL remain deployable without AudioMuse containers or plugin requirements

### Requirement: AudioMuse bootstrap SHALL be declarative where practical and operator-finished where necessary
The repository SHALL own declarative AudioMuse service topology, images, bootstrap secrets, plugin package inclusion (`pkgs.navidromePlugins.audiomuseai`), and Navidrome runtime flags where stable interfaces exist. Remaining upstream setup steps SHALL be documented as operator actions.

#### Scenario: AudioMuse foundation is deployed before UI bootstrap
- **WHEN** the host deploys with AudioMuse enabled but the upstream setup wizard or Navidrome plugin UI has not been completed
- **THEN** the system SHALL remain deployable
- **AND** operator documentation SHALL identify the remaining setup work before Symfonium validation can pass

### Requirement: AudioMuse secrets SHALL use the music host secret contract
AudioMuseAI SHALL register semantic secret keys through its leaf module while receiving its secret source from the existing music application host secret file.

#### Scenario: AudioMuse secret contract is evaluated
- **WHEN** the AudioMuse service module is enabled
- **THEN** it SHALL register required bootstrap and database secrets through SOPS-backed semantic keys
- **AND** the music secret template SHALL document those keys
- **AND** implementation SHALL NOT manually decrypt or edit encrypted secret payloads
