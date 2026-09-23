## MODIFIED Requirements

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
