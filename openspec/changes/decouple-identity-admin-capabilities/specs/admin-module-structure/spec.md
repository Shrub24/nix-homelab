## MODIFIED Requirements

### Requirement: Admin modules SHALL follow capability-owned boundaries

Admin configuration SHALL keep policy data under `policy/`, policy transformation logic under `lib/`, and service-owned behavior in concern-owned implementations. Independently portable admin workloads SHALL be published as self-contained deployment aspects. A multi-service admin composition SHALL exist only where shared implementation or aggregation behavior is intrinsic, and SHALL NOT own identity-provider runtime, state, provisioning, or secrets.

#### Scenario: Admin module tree is reviewed

- **WHEN** operators inspect admin-related repository paths
- **THEN** Kanidm server/provisioning composition and secrets are owned only by identity-provider
- **AND** independently portable Termix, Vaultwarden, Quantum, Cockpit, and other admin workloads have self-contained concern owners
- **AND** Homepage, Gatus, Beszel hub, or Webhook remain composed together only where an explicit shared behavior justifies it
- **AND** host-local admin configuration contains only genuine machine/placement bindings and explicit security-relevant secret sources
- **AND** no admin composition writes identity-provider internals
- **AND** policy data and transforms are not embedded in service or host files

### Requirement: Admin OIDC consumers SHALL depend directionally on identity contracts

Admin workloads that use OIDC SHALL consume canonical identity-client endpoint metadata and their own credential inputs without configuring the identity provider.

#### Scenario: Admin workload uses OIDC

- **WHEN** Termix, Quantum, or another admin workload enables OIDC
- **THEN** its issuer and endpoint values come from the identity-client contract
- **AND** selecting the workload does not enable or configure Kanidm
- **AND** a missing required identity contract fails through a named assertion rather than a missing option namespace
