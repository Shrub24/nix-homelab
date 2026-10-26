# Spec Delta

## MODIFIED Requirements

### Requirement: Kanidm host auth SHALL be an independently selectable capability

HA-1: Kanidm-backed Unix, PAM and SSH integration SHALL remain a separately selected `kanidm-host-auth` capability. Its server URI SHALL resolve from the explicitly identified Kanidm route in policy, independently of the active application OIDC provider and without evaluating another host's runtime configuration. Its client package SHALL remain bound to the retained Kanidm server release family. Selecting Authentik or consuming OIDC alone SHALL NOT install or retarget host authentication.

#### Scenario: A host opts into Kanidm Unix integration

- **WHEN** a host selects `kanidm-host-auth` with explicit SSH/PAM policy
- **THEN** its client URI resolves from the policy-approved Kanidm identity
- **AND** its client package follows the same release family as the retained Kanidm server
- **AND** no application OIDC provider selection is needed to make that URI available

#### Scenario: Application SSO changes to Authentik

- **WHEN** the active application provider changes from Kanidm to Authentik
- **THEN** retained host-auth clients continue targeting the independently declared Kanidm endpoint
- **AND** their permitted login groups and stable Unix identities are not reset by the application migration

#### Scenario: A host consumes OIDC without Kanidm Unix integration

- **WHEN** a host consumes an approved OIDC client but does not select `kanidm-host-auth`
- **THEN** its OIDC configuration resolves through the intrinsic contract
- **AND** no Kanidm client tooling, unixd, SSH integration or PAM policy is introduced by that consumption

#### Scenario: Compatibility endpoint has not been accepted

- **WHEN** an application-provider cutover would invalidate the endpoint used by retained Kanidm host clients
- **THEN** cutover remains blocked until the operator verifies the replacement Kanidm endpoint and login from an independent session
- **AND** existing break-glass access and Kanidm state remain available
