## MODIFIED Requirements

### Requirement: OIDC consumers SHALL reference provider-owned outputs
Service modules and host configurations that require OIDC endpoint URIs SHALL reference canonical identity-provider module outputs rather than independently constructing URIs from a base URL.

#### Scenario: Admin application services consume SSOT OIDC issuer
- **WHEN** Termix and Quantum OIDC wiring is evaluated
- **THEN** issuer values are sourced from the provider-owned `oidc.issuerUrl` output
- **AND** no independent base URL string interpolation is used to derive the issuer URL

#### Scenario: Host-level OIDC env templates consume SSOT endpoints
- **WHEN** `la-admin-1` termix-oidc.env template is rendered
- **THEN** OIDC endpoint values are sourced from canonical provider-owned `oidc.*` outputs
- **AND** no host-local URL construction is used for endpoint values

#### Scenario: Karakeep OIDC wellknown URL uses provider-owned endpoint
- **WHEN** Karakeep OIDC configuration is evaluated on `oci-melb-1`
- **THEN** the wellknown URL is derived from the canonical provider-owned OIDC outputs for the active identity provider
- **AND** no hardcoded host-local OIDC endpoint string is used
