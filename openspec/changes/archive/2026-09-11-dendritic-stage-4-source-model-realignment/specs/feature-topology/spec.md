## ADDED Requirements

### Requirement: Feature source ownership SHALL be independent of deployment granularity
Normal first-party feature files SHALL participate in the top-level module system, while several source files MAY contribute to one coherent deployment aspect when they share placement semantics.

#### Scenario: Several source features share one placement boundary
- **WHEN** separate implementation concerns are always deployed as one capability
- **THEN** their top-level source modules may contribute to the same deferred NixOS aspect
- **AND** source decomposition does not create redundant host selections

### Requirement: Selecting an application deployment aspect SHALL provide top-level enablement
A deployment aspect representing an application feature SHALL provide that application’s top-level enablement while leaving independently variable subfeatures and host-specific values explicit.

#### Scenario: Home-forge selects DJ
- **WHEN** `home-forge` imports the `dj` deployment aspect
- **THEN** `applications.dj.enable` evaluates to true
- **AND** the host does not repeat that assignment
- **AND** Engine DJ enablement, paths, secret inputs, and other host variants remain explicitly configurable

#### Scenario: DJ source is discovered but not selected
- **WHEN** the DJ source contributor is discovered but a host does not import the `dj` deployment aspect
- **THEN** DJ runtime configuration is not activated on that host
- **AND** automatic source discovery alone does not constitute workload placement

## MODIFIED Requirements

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
