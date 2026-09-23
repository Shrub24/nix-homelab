# admin-module-structure Specification

## Purpose

Define the layered ownership boundaries for admin configuration, from policy data and transforms through service-owned modules, portable application composition, and host-local assembly.

## Requirements

### Requirement: Admin modules SHALL follow capability-owned boundaries

Admin configuration SHALL keep policy data under `policy/`, policy transformation logic under `lib/`, and service-owned behavior in concern-owned implementations. Enabled independently portable admin workloads SHALL be published as self-contained deployment aspects; disabled or deferred workloads SHALL be recorded as disabled rather than left implicitly bundled. A multi-service admin composition SHALL exist only where shared implementation or aggregation behavior is intrinsic, and SHALL NOT own identity-provider runtime, state, provisioning, or secrets.

#### Scenario: Admin module tree is reviewed

- **WHEN** operators inspect admin-related repository paths
- **THEN** Kanidm server/provisioning composition and secrets are owned only by identity-provider
- **AND** enabled independently portable admin workloads, including Termix, Vaultwarden, and Cockpit, have self-contained concern owners
- **AND** Quantum remains recorded as disabled/deferred and is not required to own a deployment aspect
- **AND** Homepage, Gatus, Beszel hub, or Webhook remain composed together only where an explicit shared behavior justifies it
- **AND** host-local admin configuration contains only genuine machine/placement bindings and explicit security-relevant secret sources
- **AND** no admin composition writes identity-provider internals
- **AND** policy data and transforms are not embedded in service or host files

### Requirement: Complex admin services SHALL support adjacent data files
Complex admin services with large declarative payloads SHALL support adjacent data/config files within service subdirectories to keep module logic focused and maintainable.

#### Scenario: Homepage and Gatus service modules are evaluated
- **WHEN** service module structure is reviewed
- **THEN** Homepage and Gatus support files are organized as service subdirectories with `default.nix` and adjacent data/helper files

### Requirement: Canonical endpoint values SHALL be consumed via policy projections
Admin modules SHALL consume canonical service endpoint values (including route path and origin port) through policy resolution/projection helpers rather than re-defining those values in multiple module locations.

#### Scenario: Admin consumer wiring is evaluated
- **WHEN** admin service or monitoring modules configure route/endpoint values
- **THEN** path and port values are sourced from resolved policy/projection outputs
- **AND** equivalent literals are not duplicated in unrelated module files

### Requirement: Admin OIDC consumers SHALL depend directionally on identity contracts

Admin workloads that use OIDC SHALL consume the canonical OIDC contract's endpoint metadata and their own credential inputs without configuring the identity provider, obtaining the contract by importing it rather than by depending on a placement selection.

#### Scenario: A disabled admin workload is re-enabled

- **WHEN** a disabled or deferred admin workload is re-enabled
- **THEN** it is selected as a self-contained concern/aspect with its own runtime and secret contracts
- **AND** it consumes the canonical OIDC contract instead of configuring the identity provider
- **AND** no admin-hub or sibling implementation namespace coupling is reintroduced

#### Scenario: Architecture documentation reflects the decomposition

- **WHEN** the change is accepted
- **THEN** live architecture documentation lists no `admin-hub` aspect, no `applications.admin` namespace, and no mandatory admin co-selection
- **AND** the extracted aspects (`termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`) and the removed-from-active-module-graph status of the retired admin workload are recorded
- **AND** a decision record supersedes D-053's admin-hub clauses while historical decision bodies remain unchanged

#### Scenario: Admin workload uses OIDC

- **WHEN** an enabled admin workload enables OIDC
- **THEN** its issuer and endpoint values come from the canonical OIDC contract
- **AND** selecting the workload does not enable or configure Kanidm
- **AND** a missing required identity contract fails through a named assertion rather than a missing option namespace

#### Scenario: OIDC consumption does not require a Kanidm client

- **WHEN** an admin workload is enabled with OIDC and the host does not select `kanidm-host-auth`
- **THEN** its issuer and endpoint values still resolve from the canonical OIDC contract
- **AND** no Kanidm client package or unixd integration is installed by the workload's OIDC consumption
