# Spec: Repository Structure

## Purpose

Define the canonical repository layout contracts: explicit directory boundaries between policy data, transformation helpers, service and application modules, host assembly, and secret scopes; centralized documentation authority; and root-level formatting configuration.

## Requirements

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

### Requirement: Documentation authority is centralized
Architecture, decision, process, and structural documents SHALL remain centralized and referenced by entrypoint docs to avoid drift, including when module and host layout changes are introduced.

#### Scenario: Structure or workflow changes are introduced
- **WHEN** the Stage 1 host and flake layout changes
- **THEN** factual current-path and operator references are updated in the same change
- **AND** broader target taxonomy documentation may remain staged only when it is explicitly labeled future work rather than current architecture

### Requirement: Repository formatting configuration is explicit
The repository SHALL keep `.editorconfig` and `treefmt.toml` at the repository root. `.editorconfig` SHALL provide editor defaults only, while `treefmt.toml` SHALL define the canonical cross-language formatter configuration and formatting exclusions.

#### Scenario: Repository formatting configuration is audited
- **WHEN** the repository root is inspected
- **THEN** `.editorconfig` covers the repository's source file classes without path-specific exclusions
- **AND** `treefmt.toml` defines the formatter mappings and excludes managed/generated paths, including secrets, generated artifacts, source-generation outputs, and lockfiles

### Requirement: Converted compatibility roots SHALL leave the temporary import-tree exclusion boundary
Once every file under `modules/core/` and `modules/profiles/` has become a Dendritic aspect contributor or has been relocated or deleted, those directories SHALL be removed from the single temporary import-tree exclusion boundary; the boundary SHALL continue to enumerate only directories that still contain non-contributing leaves, and no second permanent module discovery root SHALL be introduced.

#### Scenario: Core and profiles complete conversion
- **WHEN** all leaves under `modules/core/` and `modules/profiles/` contribute through the aspect registry or are removed
- **THEN** the temporary import-tree exclusion boundary no longer lists `core` or `profiles`
- **AND** any remaining exclusions stay enumerable and removable within the same single explicit boundary

#### Scenario: Legacy bundles are decomposed rather than preserved as wrappers
- **WHEN** a legacy profile bundle (`base-server`, `fleet-standard`, or `networking`) or a legacy core wrapper no longer has a unique contribution
- **THEN** it is decomposed into aspect contributors or relocated/deleted rather than preserved as a permanent compatibility aspect
- **AND** the host assemblies no longer reference the removed wrapper

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
