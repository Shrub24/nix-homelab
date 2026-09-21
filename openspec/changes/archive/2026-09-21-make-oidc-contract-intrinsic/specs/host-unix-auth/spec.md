## ADDED Requirements

### Requirement: Kanidm host auth SHALL be an independently selectable capability

Kanidm-backed Unix, PAM, and SSH integration SHALL be provided by a `kanidm-host-auth` deployment aspect that hosts select explicitly, and it SHALL obtain the provider server URI from the intrinsic OIDC contract rather than requiring a projection selection or another host's configuration.

#### Scenario: A host opts into Kanidm Unix integration

- **WHEN** a host selects the `kanidm-host-auth` aspect
- **THEN** `services.identity.hostAuth` wiring evaluates together with the host's declared SSH and PAM policy
- **AND** the Kanidm client package resolves from the same release family as the provider's server package
- **AND** the host does not select any projection aspect to make the server URI available

#### Scenario: A host consumes OIDC without Kanidm Unix integration

- **WHEN** a host runs an OIDC-consuming application and does not select `kanidm-host-auth`
- **THEN** the application resolves its issuer and endpoint values from the canonical OIDC contract
- **AND** no Kanidm client package, unixd integration, or PAM login policy is introduced by that consumption alone
