## RENAMED Requirements

- FROM: `### Requirement: Admin modules SHALL follow layered ownership boundaries`
- TO: `### Requirement: Admin modules SHALL follow capability-owned boundaries`

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Admin OIDC consumers SHALL depend directionally on identity contracts

Admin workloads that use OIDC SHALL consume canonical identity-client endpoint metadata and their own credential inputs without configuring the identity provider.

#### Scenario: A disabled admin workload is re-enabled

- **WHEN** Quantum or another disabled/deferred admin workload is re-enabled
- **THEN** it is selected as a self-contained concern/aspect with its own runtime and secret contracts
- **AND** it consumes the canonical identity-client contract instead of configuring the identity provider
- **AND** no admin-hub or sibling implementation namespace coupling is reintroduced

#### Scenario: Architecture documentation reflects the decomposition

- **WHEN** the change is accepted
- **THEN** live architecture documentation lists no `admin-hub` aspect, no `applications.admin` namespace, and no mandatory admin co-selection
- **AND** the extracted aspects (`termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`) and the Quantum removed-from-active-module-graph/disabled/deferred status are recorded
- **AND** a decision record supersedes D-053's admin-hub clauses while historical decision bodies remain unchanged

#### Scenario: Admin workload uses OIDC

- **WHEN** an enabled admin workload enables OIDC
- **THEN** its issuer and endpoint values come from the identity-client contract
- **AND** selecting the workload does not enable or configure Kanidm
- **AND** a missing required identity contract fails through a named assertion rather than a missing option namespace
