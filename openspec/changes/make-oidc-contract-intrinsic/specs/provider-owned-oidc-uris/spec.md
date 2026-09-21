## MODIFIED Requirements

### Requirement: Canonical identity contract SHALL own and emit OIDC endpoint URIs

The canonical OIDC contract SHALL derive OIDC endpoint URIs from the provider public URL resolved by web policy and SHALL emit them as read-only outputs so providers and consumers do not independently reconstruct or mutate OIDC URIs. The contract SHALL be an intrinsic module imported by the participants that read it; it SHALL NOT be a host-selected deployment capability, and no host SHALL express a placement decision in order to make its options or outputs available.

#### Scenario: Kanidm OIDC outputs are resolved

- **WHEN** an identity participant imports the canonical OIDC contract and the Kanidm web-policy route is available
- **THEN** canonical `oidc.issuerUrl`, `oidc.wellknownUrl`, `oidc.authorizationUrl`, `oidc.tokenUrl`, and `oidc.userinfoUrl` outputs resolve from that route
- **AND** the identity-provider may independently consume the same canonical public URL
- **AND** neither capability writes the other's option namespace
- **AND** the contract's options and outputs exist without any aspect being selected for them

### Requirement: OIDC consumers SHALL reference canonical identity outputs

Service modules and host configurations that require OIDC endpoint URIs SHALL reference the canonical OIDC contract's outputs rather than independently constructing URIs from a base URL, and SHALL obtain the contract by importing it rather than by depending on a placement selection. A missing client entry SHALL fail through a named assertion.

#### Scenario: Admin application services consume SSOT OIDC issuer

- **WHEN** the OIDC wiring of an enabled admin workload is evaluated
- **THEN** issuer values are sourced from the canonical `oidc.issuerUrl` output
- **AND** no independent base URL string interpolation is used to derive the issuer URL

#### Scenario: Host-level OIDC env templates consume SSOT endpoints

- **WHEN** a host-level OIDC env template for an enabled consumer is rendered
- **THEN** OIDC endpoint values are sourced from the canonical `oidc.*` outputs
- **AND** no host-local URL construction is used for endpoint values

#### Scenario: Karakeep OIDC wellknown URL uses provider-owned endpoint

- **WHEN** Karakeep OIDC configuration is evaluated on `oci-melb-1`
- **THEN** the wellknown URL is derived from the canonical OIDC outputs for the active identity provider
- **AND** no hardcoded host-local OIDC endpoint string is used

#### Scenario: Remote OIDC consumer resolves endpoints

- **WHEN** Karakeep or Paperless evaluates on a host without identity-provider
- **THEN** its OIDC endpoints resolve from the same canonical OIDC contract and web policy
- **AND** no provider implementation options are required on the consumer host

#### Scenario: Consumer requires a client the policy does not enable

- **WHEN** an OIDC consumer is enabled while its client entry is absent from resolved policy
- **THEN** evaluation fails with a named assertion naming that consumer's client
- **AND** the failure is not a missing option namespace

### Requirement: mkOidcEndpoints SHALL provide consistent OIDC URI derivation

A shared `mkOidcEndpoints` helper SHALL exist in `lib/policy.nix` that derives the five canonical OIDC endpoint URIs from a single issuer base URL, and the canonical OIDC contract SHALL use it as its only derivation so no call site re-implements the logic.

#### Scenario: Helper is used for OIDC endpoint derivation

- **WHEN** an issuer URL is passed to `mkOidcEndpoints`
- **THEN** the returned attrset contains all five canonical OIDC endpoint URIs
- **AND** the derivation logic is identical across all call sites

#### Scenario: The contract derives per-client endpoints through the helper

- **WHEN** the canonical OIDC contract emits endpoints for an enabled client
- **THEN** it passes that client's issuer base to `mkOidcEndpoints`
- **AND** no local re-derivation of the five URIs exists in the identity domain
