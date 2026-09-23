## ADDED Requirements

### Requirement: Identity provider SHALL own its complete runtime and provisioning contract

The identity-provider capability SHALL own Kanidm runtime enablement, provider state paths, bootstrap and provisioning inputs, identity secret sources, and OIDC-client provisioning secret sources. It SHALL NOT read an admin workload namespace or require an admin capability to write Kanidm internals.

#### Scenario: Identity provider is selected without admin workloads

- **WHEN** a host selects identity-provider with its required policy and secret inputs but selects no admin workload aspect
- **THEN** Kanidm runtime and provisioning options evaluate successfully
- **AND** no `applications.admin` option namespace is required

#### Scenario: OIDC provisioning secret sources are configured

- **WHEN** the provider provisions registered OIDC clients
- **THEN** an explicit provider-owned map supplies each security-relevant credential source
- **AND** its keys are validated against canonical enabled client metadata
- **AND** credential storage paths are not inferred from logical client metadata

### Requirement: Identity provider and client SHALL consume one canonical provider URL

The identity provider and identity-client contracts SHALL independently consume the canonical Kanidm public URL from resolved web policy. The provider SHALL NOT write configuration into the identity-client namespace.

#### Scenario: Provider and remote client evaluate

- **WHEN** the provider host and a remote identity-client host evaluate
- **THEN** both resolve the same canonical provider URL
- **AND** neither requires the other capability to mutate its option namespace
