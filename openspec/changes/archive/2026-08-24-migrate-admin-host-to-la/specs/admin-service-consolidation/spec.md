## MODIFIED Requirements

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
