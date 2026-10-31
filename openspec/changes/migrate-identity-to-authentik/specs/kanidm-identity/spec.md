# Spec Delta

## REMOVED Requirements

### Requirement: Kanidm SHALL be the canonical declarative identity provider

**Reason:** Application SSO is moving to Authentik; requiring Kanidm to remain the canonical application provider would prohibit the accepted transition.

**Migration:** Retain Kanidm as an explicitly selected compatibility provider for existing application SSO until cutover and for host authentication until separately retired. Preserve its database, provisioning inputs, backups and version binding; do not treat an Authentik database as a Kanidm state restore.

## ADDED Requirements

### Requirement: Retained Kanidm SHALL preserve compatibility state until explicitly retired

KI-1: Kanidm SHALL remain available through explicit provider selection during staged Authentik acceptance and through an explicit compatibility selection while required by host authentication. Authentik selection SHALL NOT delete Kanidm data, consume its database, disable its host clients or merge its encrypted person/membership overlay into Authentik. Retiring Kanidm SHALL require accepted host-auth replacement or removal and explicit operator approval.

#### Scenario: Authentik is staged alongside Kanidm

- **WHEN** the operator approves a staged Authentik deployment with separate state and route
- **THEN** Kanidm's existing authoritative state, runtime secrets and restore capability remain intact
- **AND** existing production clients remain on Kanidm until their approved migration

#### Scenario: Application SSO moves before host authentication

- **WHEN** applications use Authentik but a host still uses Kanidm Unix/PAM/SSH integration
- **THEN** Kanidm remains independently reachable at its approved compatibility endpoint
- **AND** its retained provisioning does not undo host-auth membership changes required for continued operation

## MODIFIED Requirements

### Requirement: Kanidm provisioning SHALL own current OIDC client registration

KI-2: While Kanidm serves application SSO, its provisioning SHALL independently project explicitly approved registration policy into `services.kanidm.provision.systems.oauth2.<name>`. Common registration intent SHALL NOT be stored only as Kanidm-native scope maps; Kanidm-specific exceptions MAY remain explicit extensions. The same approved policy SHALL supply the intrinsic client projection without collecting consumer-host configuration. Runtime secret files SHALL supply confidential credentials.

#### Scenario: Existing app client is provisioned declaratively

- **WHEN** shared registration policy replaces the old Kanidm-shaped document before cutover
- **THEN** the effective client ID, approved callbacks, group/scope permissions and required claims remain equivalent
- **AND** credentials remain runtime-file-backed

#### Scenario: Application is not selected on a managed host

- **WHEN** policy continues to approve that application's Kanidm client
- **THEN** Kanidm continues provisioning it regardless of local application selection

### Requirement: Identity provider SHALL own its complete runtime and provisioning contract

KI-3: Each selected identity provider implementation SHALL own its runtime enablement, state paths, bootstrap/provisioning inputs and authorized credential delivery. The homelab identity-provider composition SHALL bind the active application provider without requiring admin workloads or host authentication. Retained Kanidm compatibility composition SHALL remain independently selectable and SHALL NOT force the active OIDC provider back to Kanidm. Security-relevant credential delivery SHALL remain explicit and validated against the applicable approved registrations.

#### Scenario: Identity provider is selected without admin workloads

- **WHEN** the identity provider is selected with required policy and secret inputs but no admin workload or host-auth capability
- **THEN** its runtime and provisioning evaluate without those namespaces
- **AND** no Unix/PAM/SSH integration is enabled by provider selection alone

#### Scenario: OIDC provisioning secret sources are configured

- **WHEN** the selected provider provisions approved confidential clients
- **THEN** explicit authorized delivery bindings supply their runtime credentials
- **AND** bindings are validated against approved client policy rather than inferred from logical client names

#### Scenario: Kanidm compatibility service is selected after application cutover

- **WHEN** retained host authentication still requires the Kanidm server while the active application provider is Authentik
- **THEN** the Kanidm runtime can be selected independently
- **AND** selecting it does not overwrite the active application's OIDC contract

### Requirement: Identity provider and OIDC contract SHALL consume one canonical provider URL

KI-4: Provider URLs SHALL come from explicit canonical web policy, with the active application provider and retained Kanidm compatibility provider independently identified. When Kanidm is the active application provider, its runtime and OIDC projection SHALL resolve the same public identity. After application cutover, retained Kanidm SHALL consume its own approved route and SHALL NOT be forced to equal Authentik's public URL. Neither provider SHALL write the other's or the intrinsic client contract's option namespace.

#### Scenario: Provider and remote client evaluate

- **WHEN** the Kanidm server and a remote OIDC consumer evaluate before cutover
- **THEN** both use the canonical Kanidm route for their respective provider and client projections
- **AND** neither relies on the other host's evaluated configuration

#### Scenario: Provider evaluates without the host-auth capability

- **WHEN** a host selects identity-provider without kanidm-host-auth
- **THEN** the selected provider's runtime, provisioning and authorized client credentials evaluate successfully
- **AND** no host-auth option namespace or Kanidm Unix/PAM/SSH integration is required or introduced

#### Scenario: Application and host-auth providers differ

- **WHEN** policy selects Authentik for application SSO and retains Kanidm for host authentication
- **THEN** application OIDC outputs derive from the Authentik route
- **AND** Kanidm runtime and host-auth URI derive from the separate approved Kanidm route
- **AND** evaluation rejects an invalid provider/route association rather than silently targeting Authentik for Kanidm operations
