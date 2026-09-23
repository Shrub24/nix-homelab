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

## REMOVED Requirements

### Requirement: mkOidcEndpoints SHALL provide consistent OIDC URI derivation

**Reason**: The helper was Pocket-ID-shaped and is dead code: `lib/policy.nix` was its only occurrence, with no call site in `lib/`, `modules/`, `tests/`, `scripts/`, or `opentofu/`. Kanidm's authorization and token endpoints are provider-level while discovery and userinfo are client-level, so a single-issuer-base signature cannot express the shape in use; mandating the helper keeps a wrong-shaped derivation in the repository for a future consumer to adopt.

**Migration**: The canonical OIDC contract remains the single derivation site (`modules/identity/_oidc.nix`) and consumers read its read-only outputs, which is the requirement's actual intent. Delete `mkOidcEndpoints` from `lib/policy.nix`; the contract's divergence from it is the reason for removal, not a regression.
