# admin-service-consolidation Specification

## Purpose
TBD - created by archiving change admin-module-consolidation-refactor. Update Purpose after archive.
## Requirements
### Requirement: Admin-owned services SHALL expose canonical admin namespaces
When a service is treated as admin-owned in this repository, its canonical reusable module SHALL expose configuration through `services.admin.<name>` and SHALL directly own the runtime wiring needed to configure the underlying NixOS or containerized service.

#### Scenario: Kanidm admin wiring is evaluated
- **WHEN** operators inspect the canonical Kanidm module
- **THEN** Kanidm options are exposed under `services.admin.kanidm`
- **AND** the module directly configures the underlying native `services.kanidm` runtime and provisioning behavior
- **AND** a generic passthrough namespace is not required as the canonical implementation path

### Requirement: Portable admin composition SHALL absorb tightly coupled glue
Portable `applications.admin` composition SHALL keep tightly coupled access and identity glue in the reusable application module when those fragments do not justify separate ownership or reuse boundaries.

#### Scenario: Portable admin composition is reviewed
- **WHEN** operators inspect admin application wiring for access and identity behavior
- **THEN** Termix Tailscale Serve exposure and shared OIDC composition are defined in the reusable `modules/applications/admin/` module
- **AND** equivalent host-local duplication is not required

### Requirement: Admin application SHALL source OIDC issuer from Pocket ID module
`applications.admin` composition SHALL source OIDC issuer URLs for Termix and Quantum from the canonical identity provider module outputs rather than deriving them from a local provider base URL variable.

#### Scenario: Termix OIDC issuer is sourced from provider module
- **WHEN** admin application composition is evaluated for `la-admin-1`
- **THEN** `services.admin.termix.oidc.issuerUrl` is set from the canonical identity provider `oidc.issuerUrl` output
- **AND** no local provider base URL variable is used for the Termix issuer derivation

#### Scenario: Quantum OIDC issuer is sourced from provider module
- **WHEN** admin application composition is evaluated for `la-admin-1`
- **THEN** `services.admin.quantum.oidc.issuerUrl` is set from the canonical identity provider `oidc.issuerUrl` output
- **AND** no local provider base URL variable is used for the Quantum issuer derivation

