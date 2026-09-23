## ADDED Requirements

### Requirement: Ntfy publisher authorization SHALL be keyed by canonical host identity

Each authorized ntfy publisher SHALL have an explicit identity, role, and runtime token contract keyed by canonical fleet host ID. ACL generation and contract validation SHALL use that typed policy.

#### Scenario: Active host publishes notifications

- **WHEN** an active host is declared as an ntfy publisher
- **THEN** the push server renders its write-only ACL subject
- **AND** the host's notification client references its own runtime token
- **AND** compromise or removal of one publisher does not alter another publisher's contract

#### Scenario: Encrypted secret policy is reviewed

- **WHEN** publisher membership changes
- **THEN** the repository reports the required plaintext template and operator SOPS updates
- **AND** automation does not decrypt, re-encrypt, or widen `.sops.yaml` readership
