# Spec: Feature Topology

## Purpose

Define how feature-owned source modules, application composition, leaf implementation contracts, and host selection combine without coupling public deployment granularity to file layout.

## Requirements

### Requirement: Application modules SHALL be composition roots rather than taxonomy wrappers
Application composition SHALL own shared paths, assertions, composition-level secret inputs, optional variants, and multi-service wiring without requiring a permanent `applications/` evaluator-class root or a second top-level enable assignment. A cohesive application MAY receive contributions from several feature-owned top-level source modules while exposing one deployment aspect, and its private implementation SHALL live beside those concern owners rather than preserving an evaluator-class application directory.

#### Scenario: Application composition is evaluated
- **WHEN** a cohesive application such as music, edge ingress, DJ, or the admin hub is rendered
- **THEN** its feature-owned contributors compose dependent services and shared behavior behind one host-selected deployment aspect
- **AND** selecting that aspect provides the application’s top-level enablement
- **AND** optional application-scoped variants remain controlled through explicit typed options
- **AND** shared feature wiring is not duplicated in host files
- **AND** the application does not require a permanent `modules/applications/` source root

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
Normal first-party feature files SHALL participate in the top-level module system, while several source files MAY contribute to one coherent deployment aspect when they share placement semantics. Every deployed host-facing product or platform capability SHALL have a discovered concern owner and SHALL be placed through explicit host selection rather than a direct host import of its implementation leaf.

#### Scenario: Several source features share one placement boundary
- **WHEN** separate implementation concerns are always deployed as one capability
- **THEN** their top-level source modules may contribute to the same deferred NixOS aspect
- **AND** source decomposition does not create redundant host selections

#### Scenario: Host places a product or platform capability
- **WHEN** a host enables a deployed product or provider-specific capability
- **THEN** its typed host record selects the corresponding discovered deployment aspect
- **AND** the host does not directly import an application, provider, or workload service implementation
- **AND** discovery of the contributor alone does not activate it on another host

### Requirement: Selecting an application deployment aspect SHALL provide top-level enablement
A deployment aspect representing an application or product feature SHALL provide that feature’s top-level enablement while leaving independently variable subfeatures and host-specific values explicit. Application and product aspects SHALL be published from discovered concern owners, and their implementation files SHALL remain private leaves rather than independently selected aspects unless they gain a distinct placement boundary.

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

#### Scenario: Remaining product aspect is selected
- **WHEN** a host selects `edge`, `cockpit`, `push-server`, `identity-provider`, `admin-hub`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, or `omniroute`
- **THEN** selection supplies that capability's existing top-level enablement
- **AND** host-specific paths, secret-source exceptions, and runtime variants remain explicit typed configuration
- **AND** no sibling capability is silently selected unless the relationship is intrinsic and documented

### Requirement: Runtime relationship contributions SHALL be owned by participating capabilities

A capability that owns a runtime unit SHALL also own its additive participation in cross-cutting relationships such as service monitoring. Host configurations and infrastructure providers SHALL NOT maintain reverse indexes of remotely placed workload units.

#### Scenario: Capability moves between hosts

- **WHEN** a capability containing monitored units moves from one host selection to another
- **THEN** its monitoring contributions move with the capability
- **AND** the former host retains no monitor-generated fragments for those units
- **AND** the new host does not require a separate service-name list update

### Requirement: Independently portable aspects SHALL NOT communicate through sibling implementation namespaces

Independently placeable capabilities SHALL expose directional typed contracts and SHALL NOT require mutual reads or writes across sibling implementation option namespaces merely because current host policy co-selects them.

#### Scenario: Capability subset is evaluated

- **WHEN** an independently meaningful capability is selected without its currently colocated siblings
- **THEN** its option declarations and intrinsic implementation evaluate independently
- **AND** any real external dependency fails through a named contract assertion
- **AND** evaluation does not fail because a sibling-owned namespace is absent

#### Scenario: Revised boundary criterion is recorded

- **WHEN** the decision log records the capability-boundary criterion for this change
- **THEN** independent placement is sufficient but not necessary, and security ownership, lifecycle, portability, and independently evaluable contracts justify a boundary with no convenience bundling

#### Scenario: Current colocation changes

- **WHEN** one capability moves to another host
- **THEN** its implementation, state contract, and secrets move with its own aspect
- **AND** colocated sibling aspects require no internal rewiring unless they explicitly consume its public contract
