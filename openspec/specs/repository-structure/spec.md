# Spec: Repository Structure

## Purpose

Define repository layout contracts that preserve modular host composition, clear ownership boundaries, and durable documentation authority.
## Requirements
### Requirement: Host and module boundaries are explicit
Repository structure SHALL separate host composition from reusable module domains and SHALL preserve explicit layering between policy data (`policy/`), policy transformation helpers (`lib/`), service-owned modules (`modules/services/`), application composition (`modules/applications/`), host assembly (`hosts/`), and topology-aligned secret scopes (`secrets/`).

#### Scenario: Operator navigates repository
- **WHEN** codebase layout is reviewed
- **THEN** host identity, application composition, leaf service implementation, and secret scopes are clearly separated by directory and ownership boundaries
- **AND** admin/media/service implementation and host-local assembly are not collapsed into one file or one monolithic secret bucket

### Requirement: Provider-specific logic remains isolated
Provider assumptions SHALL be isolated to provider/host layers and not embedded in reusable service modules, including after admin module decomposition.

#### Scenario: Service modules are reused across hosts
- **WHEN** service modules are composed by different hosts/providers
- **THEN** reusable module behavior does not depend on provider-specific inline logic

### Requirement: Flake outputs are canonical host entrypoints
Canonical host build/deploy targets SHALL be represented through flake host outputs.

#### Scenario: Host target is selected for operations
- **WHEN** build/deploy routines resolve host targets
- **THEN** they map to canonical `nixosConfigurations.<host>` outputs

### Requirement: Documentation authority is centralized
Architecture/decision/process documents SHALL remain centralized and referenced by entrypoint docs to avoid drift, including when module and host layout changes are introduced.

#### Scenario: Structure or workflow changes are introduced
- **WHEN** significant layout/workflow updates are made
- **THEN** authoritative docs are updated in the same change window

### Requirement: Canonical docs reflect active package baseline policy
Canonical repository documentation SHALL describe the active package baseline policy and SHALL remain synchronized with flake input behavior.

#### Scenario: Baseline policy changes
- **WHEN** primary package baseline policy is changed in active code
- **THEN** canonical docs (`docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`) are updated in the same change window to reflect the new default policy

### Requirement: SSOT metadata SHALL avoid cross-module literal duplication
Repository structure and module boundaries SHALL keep canonical domain, route subdomain/path, and service endpoint port metadata in authoritative policy/config locations, with consuming modules reading projections instead of redefining equivalent literals.

#### Scenario: Operator audits endpoint metadata ownership
- **WHEN** domain/subdomain/path/port values are inspected across edge, service, and monitoring modules
- **THEN** each value class has one authoritative source-of-truth location
- **AND** downstream modules consume resolved projections rather than duplicating raw literals

### Requirement: Host composition SHALL support thin focused host files
Host composition SHALL support thin, focused host files for identity, facts, networking, and narrow host-only exceptions while keeping reusable feature composition in applications and services.

#### Scenario: Host files are organized
- **WHEN** host composition is reviewed for any active host
- **THEN** `hosts/<host>/default.nix` remains the primary assembly entrypoint
- **AND** any split host files remain narrowly focused rather than owning reusable application/service internals

### Requirement: Secret storage structure SHALL reflect feature ownership
Repository secret layout SHALL distinguish application-scoped, standalone-service-scoped, and host-exception-scoped secret material so the path structure itself communicates ownership and blast radius.

#### Scenario: Secret tree is inspected
- **WHEN** operators review the `secrets/` tree and related host exception paths
- **THEN** application-scoped secrets, standalone-service secrets, and host exception secrets are visibly separated by path
- **AND** monolithic host secret files are not the primary canonical bucket model

### Requirement: Dependency metadata SHALL live in canonical repo-level locations

Repository structure SHALL place canonical OCI image metadata and nvfetcher-generated non-flake source metadata in explicit repo-level locations that are reusable across hosts and services.

#### Scenario: Operator inspects dependency metadata placement

- **WHEN** an operator reviews where OCI image refs and generated non-flake source metadata live
- **THEN** those artifacts are stored in canonical repo-level paths rather than host-local files
- **AND** service and package consumers can import those paths without redefining equivalent literals

### Requirement: `.editorconfig` SHALL be present at repo root

The repository SHALL include an `.editorconfig` file at the repository root declaring baseline editor behavior (charset, indentation style/size, line endings) for all file classes the repository uses.

#### Scenario: Repository structure is audited

- **WHEN** the repository root is inspected
- **THEN** `.editorconfig` is present as a committed file
- **AND** it contains settings for every file class the repository uses day-to-day (.nix, YAML, TOML, Markdown, shell, JSON, Python, and editor-only `.hcl` indentation if needed)
- **AND** it does **not** carry path-specific exclusion sections

### Requirement: `treefmt.toml` SHALL be present at repo root

The repository SHALL include a `treefmt.toml` file at the repository root declaring the canonical cross-language formatter configuration and exclusion patterns.

#### Scenario: Repository structure is audited

- **WHEN** the repository root is inspected
- **THEN** `treefmt.toml` is present as a committed file
- **AND** it declares formatter entries for `.nix`, YAML, TOML, Markdown, shell scripts, JSON, Python, and OpenTofu (`.tf`/`.tfvars` only)
- **AND** its `excludes` list is the sole exclusion SSOT, rather than matching `.editorconfig` at a second reference point

### Requirement: Generated source artifacts SHALL remain safe to commit

Committed generated dependency metadata SHALL be limited to reproducible source information required for evaluation and packaging, without embedding secrets or host-specific runtime state.

#### Scenario: Generated source files are reviewed

- **WHEN** nvfetcher-generated files are committed to the repository
- **THEN** they contain version/source/hash metadata needed by package consumers
- **AND** they do not introduce secrets, host-scoped credentials, or mutable runtime-only state into version control

