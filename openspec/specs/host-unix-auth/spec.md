# host-unix-auth Specification

## Purpose
Define host-level UNIX authentication against the fleet identity provider: native Kanidm client and unixd integration on hosts that opt in after OIDC parity, with SSH and PAM policy kept explicit and host-safe.

## Requirements

### Requirement: Fleet hosts SHALL support Kanidm client and unixd integration
Fleet hosts SHALL support Kanidm client and unixd integration through native nixpkgs client/unix modules after OIDC parity is established.

#### Scenario: Host enables Kanidm unix integration
- **WHEN** a host opts into the host-auth phase of this migration
- **THEN** native `services.kanidm.client` and `services.kanidm.unix` wiring is enabled on that host
- **AND** the host consumes the canonical Kanidm server URI rather than a duplicated local literal

### Requirement: SSH and PAM policy SHALL remain explicit and host-safe
Kanidm-backed SSH and PAM login behavior SHALL be enabled only through explicit host policy, including declarative allowlists for permitted login groups, and hosts MAY declare a separate host-scoped console break-glass rescue account outside the normal identity-backed login flow.

#### Scenario: Host enables sshIntegration
- **WHEN** a host enables Kanidm SSH integration
- **THEN** SSH key lookup behavior is declared through `services.kanidm.unix.sshIntegration`
- **AND** PAM login eligibility is constrained by explicitly declared allowed login groups

#### Scenario: Host enables a rescue account
- **WHEN** a host declares break-glass rescue-user access
- **THEN** that account is configured explicitly as a host-scoped exception rather than an implicit fleet-wide normal login path
- **AND** its console login and sudo posture remains declarative and auditable

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
