# Spec: Feature Topology

## Purpose

Define how feature-owned source modules, application composition, leaf implementation contracts, and host selection combine without coupling public deployment granularity to file layout.

## Requirements

### Requirement: Application modules SHALL be composition roots rather than taxonomy wrappers
Application composition SHALL own shared paths, assertions, composition-level secret inputs, optional variants, and multi-service wiring without requiring a permanent `applications/` evaluator-class root or a second top-level enable assignment. A cohesive application MAY receive contributions from several feature-owned top-level source modules while exposing one deployment aspect.

#### Scenario: Application composition is evaluated
- **WHEN** a cohesive application such as music or admin is rendered
- **THEN** its feature-owned contributors compose dependent services and shared behavior behind one host-selected deployment aspect
- **AND** selecting that aspect provides the application’s top-level enablement
- **AND** optional application-scoped variants remain controlled through explicit typed options
- **AND** shared feature wiring is not duplicated in host files

#### Scenario: Singleton service remains a leaf
- **WHEN** an unconverted singleton service has no current cross-service composition needs
- **THEN** it may remain a lower-level service module owned by its current host or future feature contributor
- **AND** that migration exception does not establish a permanent class-oriented source taxonomy

### Requirement: Leaf services SHALL own secret and runtime contracts
Leaf service modules SHALL own semantic secret registration, template assembly, runtime wiring, assertions, and restart semantics, and SHALL accept explicit contract inputs such as `secretFiles.*` and `secretKeys.*` instead of requiring callers to mutate raw internal `sops.secrets` definitions.

#### Scenario: Application supplies secrets to a leaf
- **WHEN** an application composes a leaf service that needs secrets
- **THEN** it provides explicit contract inputs to the leaf
- **AND** the leaf remains responsible for the actual `sops.secrets` / `sops.templates` registration and runtime consumption

#### Scenario: Application passes resolved OIDC env-file handoff to a leaf
- **WHEN** a composed leaf service owns an OIDC template but expects a resolved env-file path input for runtime wiring
- **THEN** the application composition layer passes the resolved `sops.templates.*.path` through the leaf's explicit contract surface
- **AND** hosts do not own or duplicate that OIDC env-file wiring

#### Scenario: Host overrides a secret source
- **WHEN** a host needs to bind a host-specific secret source for an enabled feature
- **THEN** it does so through the exposed contract surface
- **AND** the host does not need to know or mutate the leaf’s internal secret registration names

#### Scenario: Leaf secret contract cleanup is reviewed after regression fixes
- **WHEN** a leaf service is revisited after the topology migration to close a regression or cleanup pass
- **THEN** it continues to use the canonical helper-based secret contract surface where that pattern is already established in the repo
- **AND** hosts only bind explicit contract inputs rather than reviving ad hoc secret-file wiring shapes

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

### Requirement: Feature source ownership SHALL be independent of deployment granularity
Normal first-party feature files SHALL participate in the top-level module system, while several source files MAY contribute to one coherent deployment aspect when they share placement semantics.

#### Scenario: Several source features share one placement boundary
- **WHEN** separate implementation concerns are always deployed as one capability
- **THEN** their top-level source modules may contribute to the same deferred NixOS aspect
- **AND** source decomposition does not create redundant host selections

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
