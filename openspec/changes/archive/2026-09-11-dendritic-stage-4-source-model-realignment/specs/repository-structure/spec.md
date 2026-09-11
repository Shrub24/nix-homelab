## ADDED Requirements

### Requirement: Source discovery and deployment activation SHALL be separate
Normal first-party feature contributors SHALL participate in the top-level module system through automatic discovery, while deployment SHALL remain controlled by explicit host selection of deferred NixOS aspects. Source-file granularity SHALL NOT require one public deployment aspect per source file.

#### Scenario: A source module contributes to a deployment aspect
- **WHEN** import-tree discovers a first-party feature source module
- **THEN** that module may define or extend a `flake.modules.nixos.<aspect>` value
- **AND** several source modules may contribute to the same coherent deployment aspect
- **AND** discovery alone does not activate that aspect on any host

#### Scenario: A lower-level implementation remains private
- **WHEN** a NixOS module is solely an implementation detail, generated input, hardware fragment, or external module
- **THEN** it remains reachable through its owning feature or an explicit private path
- **AND** it is not presented as an independently selectable deployment capability
- **AND** private status is justified by ownership rather than directory convention alone

## MODIFIED Requirements

### Requirement: Host and module boundaries are explicit
Repository structure SHALL separate host composition from reusable feature ownership within one Dendritic discovery tree and SHALL preserve explicit boundaries between policy data (`policy/`), feature contributors (`modules/`), private lower-level implementations, host assembly, and topology-aligned secret scopes (`secrets/`). Legacy evaluator-class roots SHALL remain transitional rather than define the endpoint taxonomy.

#### Scenario: Operator navigates repository
- **WHEN** codebase layout is reviewed
- **THEN** host identity and composition are discoverable under `modules/hosts/<host>/` during migration
- **AND** normal converted source files identify their owned feature and participate in the top-level module system
- **AND** host-private data or genuine lower-level implementation modules use underscore-prefixed or otherwise explicit private paths
- **AND** only unconverted migration leaves remain behind the single enumerated filter, which shrinks as their features convert
- **AND** workload activation remains explicit in host composition rather than being caused by automatic source discovery

#### Scenario: Legacy leaves coexist during migration
- **WHEN** import-tree discovers the Dendritic module tree before all normal first-party feature files have become top-level contributors
- **THEN** unconverted directories are excluded by one explicit temporary boundary
- **AND** exclusions remain enumerable and removable as feature conversions empty or eliminate legacy roots
- **AND** no second permanent discovery root or blanket lower-level import is introduced
