# Spec: Repository Structure

## Purpose

Define the canonical repository layout contracts: explicit directory boundaries between policy data, transformation helpers, service and application modules, host assembly, and secret scopes; centralized documentation authority; and root-level formatting configuration.

## Requirements

### Requirement: Host and module boundaries are explicit
Repository structure SHALL separate host composition from reusable module domains within one Dendritic discovery tree and SHALL preserve explicit layering between policy data (`policy/`), policy transformation helpers (`lib/`), service-owned modules (`modules/services/`), application composition (`modules/applications/`), host assembly (`modules/hosts/`), and topology-aligned secret scopes (`secrets/`).

#### Scenario: Operator navigates repository
- **WHEN** codebase layout is reviewed
- **THEN** host identity and composition are discoverable under `modules/hosts/<host>/`
- **AND** application composition, leaf service implementation, policy, and secret scopes retain distinct ownership boundaries
- **AND** host-private data or raw NixOS modules that must not contribute at the flake-parts level use underscore-prefixed paths or an explicit enumerated import filter
- **AND** workload activation remains explicit in host composition rather than being caused by blanket imports

#### Scenario: Legacy leaves coexist during migration
- **WHEN** import-tree discovers the Dendritic module tree before all NixOS leaves have become aspect contributors
- **THEN** the unconverted directories are excluded by one explicit temporary boundary
- **AND** exclusions are enumerable and removable as aspects are converted
- **AND** no second permanent module discovery root is introduced

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
