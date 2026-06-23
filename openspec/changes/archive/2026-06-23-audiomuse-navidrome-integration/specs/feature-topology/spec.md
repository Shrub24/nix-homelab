# Delta Spec: Feature Topology

## MODIFIED Requirements

### Requirement: Application modules SHALL be composition roots rather than taxonomy wrappers
Application modules SHALL own shared paths, shared assertions, composition-level secret inputs, optional feature toggles, and multi-service wiring, while singleton services SHALL remain leaf services until real composition needs exist.

#### Scenario: Application composition is evaluated
- **WHEN** an application module such as `applications.music` or `applications.admin` is rendered
- **THEN** it composes multiple dependent services and shared feature behavior behind one operator-facing toggle
- **AND** optional application-scoped features such as AudioMuse-backed Navidrome similarity may be controlled through explicit application-layer toggles
- **AND** shared feature wiring is not duplicated in host files

#### Scenario: Singleton service remains a leaf
- **WHEN** a service such as Karakeep has no current cross-service composition needs
- **THEN** it remains a leaf service module
- **AND** future application wrapping is deferred until real composition value exists

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

## ADDED Requirements

### Requirement: Feature-domain service subtrees SHALL preserve option contracts
Leaf service implementation files MAY be grouped under feature-domain directories such as `modules/services/music/` when doing so improves navigability, but such grouping SHALL NOT require a public option namespace migration.

#### Scenario: Music service files are moved under a feature-domain subtree
- **WHEN** music-owned service module files are mechanically moved under `modules/services/music/`
- **THEN** their existing public option contracts SHALL remain stable unless a separate OpenSpec change explicitly proposes an option migration
- **AND** application and host imports SHALL be updated without reintroducing hidden import-only activation paths
