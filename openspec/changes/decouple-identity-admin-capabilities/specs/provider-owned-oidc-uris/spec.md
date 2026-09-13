## MODIFIED Requirements

### Requirement: Canonical identity contract SHALL own and emit OIDC endpoint URIs

The canonical identity-client contract SHALL derive OIDC endpoint URIs from the provider public URL resolved by web policy and SHALL emit them as read-only outputs so providers and consumers do not independently reconstruct or mutate OIDC URIs.

#### Scenario: Kanidm OIDC outputs are resolved

- **WHEN** identity-client composition is selected and the Kanidm web-policy route is available
- **THEN** canonical `oidc.issuerUrl`, `oidc.wellknownUrl`, `oidc.authorizationUrl`, `oidc.tokenUrl`, and `oidc.userinfoUrl` outputs resolve from that route
- **AND** the identity-provider may independently consume the same canonical public URL
- **AND** neither capability writes the other's option namespace

### Requirement: OIDC consumers SHALL reference canonical identity outputs

Service modules and host configurations that require OIDC endpoint URIs SHALL reference canonical identity-client outputs rather than independently constructing URIs from a base URL or requiring the runtime provider aspect to be colocated.

#### Scenario: Admin application services consume canonical OIDC issuer

- **WHEN** Termix and Quantum OIDC wiring is evaluated
- **THEN** issuer values are sourced from the canonical identity-client `oidc.issuerUrl` output
- **AND** no independent base URL string interpolation is used to derive the issuer URL

#### Scenario: Remote OIDC consumer resolves endpoints

- **WHEN** Karakeep or Paperless evaluates on a host without identity-provider
- **THEN** its OIDC endpoints resolve from the same identity-client contract and web policy
- **AND** no provider implementation options are required on the consumer host
