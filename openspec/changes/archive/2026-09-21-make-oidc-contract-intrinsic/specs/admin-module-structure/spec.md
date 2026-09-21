## MODIFIED Requirements

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
