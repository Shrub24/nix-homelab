# Delta Spec: Repository Structure

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

#### Scenario: Relocated private implementations remain owned by their aspect
- **WHEN** a private implementation leaf moves out of a removed shared root
- **THEN** it is relocated beside its aspect owner under an underscore-prefixed private path (for example `_aspects/`, `_backups/`, or `_builder-access/`)
- **AND** it remains reachable through the owning aspect's imports and is not presented as an independently selectable deployment capability
- **AND** relocating an existing private leaf does not convert it into a public aspect

#### Scenario: A shared storage root is removed without a wrapper
- **WHEN** a zero-consumer evaluator-class storage root is deleted
- **THEN** host-local disk layouts remain host-private under `modules/hosts/<host>/`
- **AND** no shared storage wrapper, template re-export, or composition replaces the deleted root
- **AND** removing the shared root changes neither host storage evaluation nor per-host disk layout

### Requirement: Converted compatibility roots SHALL leave the temporary import-tree exclusion boundary
Once every file under a temporary evaluator-class root — for example `modules/core/`, `modules/profiles/`, `modules/shared/`, or `modules/storage/` — has become a Dendritic aspect contributor, has been relocated beside its aspect owner, or has been deleted, that directory SHALL be removed from the single temporary import-tree exclusion boundary; the boundary SHALL continue to enumerate only directories that still contain non-contributing leaves, and no second permanent module discovery root SHALL be introduced.

#### Scenario: A converted legacy root leaves the boundary
- **WHEN** all leaves under an excluded directory have become aspect contributors, have been relocated beside their aspect owner, or have been deleted
- **THEN** the directory is removed from the temporary boundary and the boundary shrinks exactly by the number of converted entries
- **AND** an entry is removed only when its directory is genuinely empty of unconverted leaves, never by renaming it into a replacement boundary entry
- **AND** remaining exclusions stay enumerable and removable within the same single explicit boundary

#### Scenario: Shared and storage roots are removed in stage 5
- **WHEN** `modules/shared/` and `modules/storage/` no longer contain unconverted leaves after the stage-5 conversion
- **THEN** the temporary boundary shrinks from six entries to four, with only `applications`, `hosts`, `providers`, and `services` remaining
- **AND** the shrink reflects converted, relocated, or deleted leaves rather than an underscore-prefixed rename of `shared` or `storage`

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

#### Scenario: A shared feature leaf becomes a discovered top-level contributor
- **WHEN** a normal feature file leaves an excluded legacy root and moves into the top-level discovery tree
- **THEN** it is converted into a discovered source contributor that defines or extends a `flake.modules.nixos.<aspect>` value directly
- **AND** several such contributors merge into the same deployment aspect without a central aggregator wrapper, and discovery alone does not activate that aspect on any host
- **AND** the converted file is not re-excluded through a renamed boundary entry

#### Scenario: A discovered contributor nests its deployment module inline
- **WHEN** a converted feature file becomes a discovered top-level contributor
- **THEN** its NixOS options/config body may be nested directly inside its `flake.modules.nixos.<aspect>` definition
- **AND** it does not require a separate underscore-private implementation leaf, wrapper module, or cross-contributor import
- **AND** two such contributors may both define the same aspect, with flake-parts merging their bodies and no direct import of either contributor outside the discovery tree