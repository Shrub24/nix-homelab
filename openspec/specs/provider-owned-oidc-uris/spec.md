# provider-owned-oidc-uris Specification

## Purpose
Define one owner for OIDC endpoint URIs: the identity-client contract derives them from the provider public URL, emits them read-only, and consumers reference those outputs instead of reconstructing URIs themselves.

## Requirements

### Requirement: Canonical identity contract SHALL own and emit OIDC endpoint URIs

The canonical identity-client contract SHALL derive OIDC endpoint URIs from the provider public URL resolved by web policy and SHALL emit them as read-only outputs so providers and consumers do not independently reconstruct or mutate OIDC URIs.

#### Scenario: Kanidm OIDC outputs are resolved

- **WHEN** identity-client composition is selected and the Kanidm web-policy route is available
- **THEN** canonical `oidc.issuerUrl`, `oidc.wellknownUrl`, `oidc.authorizationUrl`, `oidc.tokenUrl`, and `oidc.userinfoUrl` outputs resolve from that route
- **AND** the identity-provider may independently consume the same canonical public URL
- **AND** neither capability writes the other's option namespace

### Requirement: OIDC consumers SHALL reference canonical identity outputs

Service modules and host configurations that require OIDC endpoint URIs SHALL reference canonical identity-client outputs rather than independently constructing URIs from a base URL or requiring the runtime provider aspect to be colocated.

#### Scenario: Admin application services consume SSOT OIDC issuer

- **WHEN** the OIDC wiring of an enabled admin workload is evaluated
- **THEN** issuer values are sourced from the canonical identity-client `oidc.issuerUrl` output
- **AND** no independent base URL string interpolation is used to derive the issuer URL

#### Scenario: Host-level OIDC env templates consume SSOT endpoints

- **WHEN** a host-level OIDC env template for an enabled consumer is rendered
- **THEN** OIDC endpoint values are sourced from canonical identity-client `oidc.*` outputs
- **AND** no host-local URL construction is used for endpoint values

#### Scenario: Karakeep OIDC wellknown URL uses provider-owned endpoint

- **WHEN** Karakeep OIDC configuration is evaluated on `oci-melb-1`
- **THEN** the wellknown URL is derived from canonical identity-client OIDC outputs for the active identity provider
- **AND** no hardcoded host-local OIDC endpoint string is used

#### Scenario: Remote OIDC consumer resolves endpoints

- **WHEN** Karakeep or Paperless evaluates on a host without identity-provider
- **THEN** its OIDC endpoints resolve from the same identity-client contract and web policy
- **AND** no provider implementation options are required on the consumer host

### Requirement: mkOidcEndpoints SHALL provide consistent OIDC URI derivation
A shared `mkOidcEndpoints` helper SHALL exist in `lib/policy.nix` that derives the five canonical OIDC endpoint URIs from a single issuer base URL.

#### Scenario: Helper is used for OIDC endpoint derivation
- **WHEN** an issuer URL is passed to `mkOidcEndpoints`
- **THEN** the returned attrset contains all five canonical OIDC endpoint URIs
- **AND** the derivation logic is identical across all call sites
