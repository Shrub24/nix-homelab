## MODIFIED Requirements

### Requirement: Selecting an application deployment aspect SHALL provide top-level enablement
A deployment aspect representing an application feature SHALL provide that application’s top-level enablement while leaving independently variable subfeatures and host-specific values explicit. An application deployment aspect MAY be published from a discovered contributor, and its service implementation files SHALL remain private leaves rather than aspects.

#### Scenario: Home-forge selects DJ
- **WHEN** `home-forge` imports the `dj` deployment aspect
- **THEN** `applications.dj.enable` evaluates to true
- **AND** the host does not repeat that assignment
- **AND** Engine DJ enablement, paths, secret inputs, and other host variants remain explicitly configurable

#### Scenario: DJ source is discovered but not selected
- **WHEN** the DJ source contributor is discovered but a host does not import the `dj` deployment aspect
- **THEN** DJ runtime configuration is not activated on that host
- **AND** automatic source discovery alone does not constitute workload placement

#### Scenario: Home-forge selects music
- **WHEN** `home-forge` imports the `music` deployment aspect
- **THEN** `applications.music.enable` evaluates to true
- **AND** the host does not repeat that assignment
- **AND** music and DJ remain independently selected aspects

#### Scenario: Music source is discovered but not selected
- **WHEN** the music source contributor is discovered but a host does not import the `music` deployment aspect
- **THEN** music runtime configuration is not activated on that host
- **AND** automatic source discovery alone does not constitute workload placement

#### Scenario: DJ consumes the music library contract without activating music
- **WHEN** the `dj` deployment aspect is selected and the `music` deployment aspect is not
- **THEN** `applications.dj.engine.sharePath` and `musicStorageRoot` remain `types.str` with safe `""` defaults (never `nullOr` or a missing attribute)
- **AND** DJ consumes an explicit music storage/library contract when one is present
- **AND** a named assertion fires, only when the engine is enabled, unless the contract is present or the host explicitly sets both `sharePath` and `musicStorageRoot` to non-empty strings
- **AND** so DJ without music is permitted only with both explicit values, and otherwise fails the named assertion rather than a null/missing-attribute error
- **AND** music runtime configuration is not activated by DJ selection

### Requirement: Feature-domain service subtrees SHALL preserve option contracts
Leaf service implementation files MAY be grouped under feature-domain directories such as `modules/services/music/` when doing so improves navigability, but such grouping SHALL NOT require a public option namespace migration. Private service leaves SHALL be imported through their discovered concern owner and SHALL NOT be published as deployment aspects.

#### Scenario: Music service files are moved under a feature-domain subtree
- **WHEN** music-owned service module files are mechanically moved under `modules/services/music/`
- **THEN** their existing public option contracts SHALL remain stable unless a separate OpenSpec change explicitly proposes an option migration
- **AND** application and host imports SHALL be updated without reintroducing hidden import-only activation paths

#### Scenario: Private music leaves stay outside the published aspect set
- **WHEN** music service implementation files remain private leaves under `modules/services/music/`
- **THEN** they are imported through the discovered music concern owner
- **AND** they are not published as deployment aspects
- **AND** the four-root top-level discovery boundary remains unchanged
