# Spec Delta

## MODIFIED Requirements

### Requirement: Canonical identity contract SHALL own and emit OIDC endpoint URIs

OIDC-1: The canonical identity contract SHALL derive each approved client's OIDC endpoint URIs and supported client-facing settings from explicit registration policy, the selected provider's conventions and the provider public URL resolved by web policy. Derived values SHALL be read-only. The contract SHALL be intrinsic, imported by participants rather than selected as a deployment capability. It SHALL NOT require provider runtime options or another host's evaluated configuration, and neither the provider nor consumers SHALL independently reconstruct or mutate endpoint URIs.

#### Scenario: Kanidm OIDC outputs are resolved

- **WHEN** Kanidm remains selected and a participant imports the intrinsic contract with its canonical route available
- **THEN** its read-only endpoint outputs resolve according to Kanidm conventions without a server selection on that host
- **AND** neither runtime nor consumer writes the other's namespace

#### Scenario: Selected provider's client outputs are resolved

- **WHEN** an identity participant imports the canonical OIDC contract and the selected provider's route and approved client policy are available
- **THEN** client ID, issuer, discovery, authorization, token and userinfo outputs resolve according to that provider's protocol conventions
- **AND** requested scopes and claim conventions resolve where required by the application
- **AND** no server runtime or host-auth capability is selected to obtain those outputs

#### Scenario: Provider identity changes through policy

- **WHEN** the approved staging provider URL changes in web policy
- **THEN** all derived endpoints use that URL without editing consumer implementation strings
- **AND** stable application provider identifiers and callback paths change only through explicit migration policy

### Requirement: OIDC consumers SHALL reference canonical identity outputs

OIDC-2: Services and host configuration requiring OIDC settings SHALL consume the intrinsic contract rather than construct provider-specific URIs or scopes themselves. Application-specific adapters MAY translate the resolved shape into native application settings and runtime secret handoffs. Missing or disabled approved client policy SHALL fail with a named error identifying the consumer. Stable application identifiers SHALL NOT be renamed merely to match the new provider's display name.

#### Scenario: Admin application services consume SSOT OIDC issuer

- **WHEN** an enabled admin application's OIDC settings are evaluated
- **THEN** its issuer comes from the canonical client output rather than independently constructed provider URLs

#### Scenario: Host-level OIDC env templates consume SSOT endpoints

- **WHEN** a host renders an enabled application's OIDC environment template
- **THEN** required endpoints come from the intrinsic client outputs without host-local URL construction

#### Scenario: Karakeep OIDC wellknown URL uses provider-owned endpoint

- **WHEN** Karakeep's OIDC discovery settings are evaluated on OCI
- **THEN** the discovery URL comes from the active provider's canonical client output without a duplicated endpoint literal

#### Scenario: Remote OIDC consumer resolves endpoints

- **WHEN** Karakeep or Paperless evaluates on a host without identity-provider
- **THEN** its issuer and other required settings come from the intrinsic contract
- **AND** no provider implementation options or provider-specific package are required locally

#### Scenario: Consumer requires a client the policy does not enable

- **WHEN** an OIDC consumer is enabled while its named registration is absent or disabled in identity policy
- **THEN** evaluation fails with an error naming the client and policy problem
- **AND** an unrelated missing-option exception does not satisfy the failure contract

#### Scenario: Application retains a provider identifier used in account linkage

- **WHEN** the provider implementation changes but the application requires a stable configured provider slug for existing account linkage
- **THEN** its adapter preserves that slug unless an explicit account migration replaces it
- **AND** the slug is not inferred from the provider display name

## ADDED Requirements

### Requirement: Client configuration and server registration SHALL be independent projections of policy

OIDC-3: Approved identity policy SHALL be the sole registration authority consumed independently by the OIDC client projection and server provisioning. Importing or configuring the client contract SHALL NOT register a client on the server. The server SHALL NOT enumerate evaluated consumer hosts to discover registrations. An approved registration MAY exist without a selected application aspect or managed local consumer.

#### Scenario: Client contract is imported in isolation

- **WHEN** a host imports the client contract without selecting a provider runtime
- **THEN** only declared client facts are realized on that host
- **AND** no server registration side effect or server unit is introduced

#### Scenario: Deselected application's approved registration remains

- **WHEN** an application aspect is deselected but its registration remains explicitly approved in identity policy
- **THEN** provider provisioning retains the registration
- **AND** removal requires a separate explicit policy decision

### Requirement: Identity facts and credential bindings SHALL have one authority

OIDC-4: Each identity fact SHALL have one authority: web/fleet policy for placement and URLs, registration policy for callbacks/access/claims, and explicit bindings for credential delivery. Provider extensions SHALL NOT silently override common intent. Client outputs SHALL contain no plaintext credentials. Workload placement SHALL NOT infer or widen secret readership.

#### Scenario: Callback and provider endpoints are rendered on different hosts

- **WHEN** the server renders an approved client's redirect allowlist and a remote application renders its identity settings
- **THEN** both consume the same registration identity and canonical URL facts
- **AND** neither reads the other's evaluated runtime options or repeats its URL literals

#### Scenario: Provider cannot represent approved policy

- **WHEN** selected-provider translation encounters unsupported authorization or claim semantics
- **THEN** evaluation or provisioning fails with a named unsupported-policy error
- **AND** the integration does not silently broaden access or omit required claims
