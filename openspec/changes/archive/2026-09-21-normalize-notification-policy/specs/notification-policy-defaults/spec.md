## ADDED Requirements

### Requirement: Policy SHALL define canonical notification publishers

The repository notification policy SHALL define authorized ntfy publishers by canonical fleet host ID and role. The host running the ntfy server SHALL consume this policy and SHALL NOT independently maintain a fleet publisher list.

#### Scenario: Publisher ACLs are rendered

- **WHEN** the push-server capability evaluates
- **THEN** its ntfy ACL subjects derive from canonical publisher policy
- **AND** every publisher ID resolves to a canonical host
- **AND** moving the push server does not change publisher membership

#### Scenario: Publisher contract is inconsistent

- **WHEN** a publisher is present in policy but absent from the required runtime secret/template contract, or vice versa
- **THEN** validation fails and names the mismatched publisher
- **AND** no secret value is generated or exposed

### Requirement: Notification policy SHALL remain separate from generic mechanics

Fleet publisher membership, routing topics, and backend destinations SHALL remain policy inputs to the notification implementation rather than built-in assumptions of the daemon, CLI, or systemd hook mechanism.

#### Scenario: Generic notification component is reused

- **WHEN** the daemon and hook module are composed with another valid policy
- **THEN** they consume typed routing and publisher inputs
- **AND** they contain no hard-coded homelab host identities or recipient values
