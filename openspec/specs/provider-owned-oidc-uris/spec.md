# provider-owned-oidc-uris Specification

## Purpose
TBD - created by archiving change provider-owned-oidc-uris. Update Purpose after archive.
## Requirements
### Requirement: Pocket ID module SHALL own and emit OIDC endpoint URIs
The canonical identity provider service module SHALL derive canonical OIDC endpoint URIs from its own configured issuer/origin and SHALL emit them as read-only outputs so consumers do not independently reconstruct OIDC URIs.

#### Scenario: Kanidm OIDC outputs are resolved
- **WHEN** Kanidm service wiring is enabled and its public origin is configured
- **THEN** the canonical provider-owned `oidc.issuerUrl`, `oidc.wellknownUrl`, `oidc.authorizationUrl`, `oidc.tokenUrl`, and `oidc.userinfoUrl` outputs resolve from that configured origin
- **AND** consumers do not need to reconstruct those endpoint values independently

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

### Requirement: mkOidcEndpoints SHALL provide consistent OIDC URI derivation
A shared `mkOidcEndpoints` helper SHALL exist in `lib/policy.nix` that derives the five canonical OIDC endpoint URIs from a single issuer base URL.

#### Scenario: Helper is used for OIDC endpoint derivation
- **WHEN** an issuer URL is passed to `mkOidcEndpoints`
- **THEN** the returned attrset contains all five canonical OIDC endpoint URIs
- **AND** the derivation logic is identical across all call sites

