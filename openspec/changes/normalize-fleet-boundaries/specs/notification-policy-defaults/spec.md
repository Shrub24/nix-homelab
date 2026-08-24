# Delta Spec: Notification Policy Defaults

## ADDED Requirements

### Requirement: Ntfy publisher identity SHALL be one typed contract owned by the ntfy module
Ntfy publisher identities (the bare-hostname publisher users, their publish tokens, and write-only ACL subjects) SHALL be defined once as a typed contract owned by the ntfy service module. Host config, secret templates, and contract tests SHALL derive from that contract rather than mirroring the identities independently, and secret values SHALL remain outside the Nix store with committed content carrying only placeholders and non-secret metadata.

#### Scenario: A new host becomes an ntfy publisher
- **WHEN** a host opts into ntfy publishing
- **THEN** its publisher user, token reference, and ACL entry are derived from the typed contract in one place
- **AND** host config, secret template, and scope test do not each restate the identity independently

#### Scenario: Publisher set changes
- **WHEN** a publisher is added or removed from the typed contract
- **THEN** the change is expressed once in the contract
- **AND** a regression check verifies generated config, template placeholders, and test expectations stay consistent

#### Scenario: Secrets stay out of the Nix store
- **WHEN** the typed contract renders ntfy configuration
- **THEN** bcrypt hashes and publish tokens remain in encrypted secret material referenced by the contract
- **AND** committed config and templates contain only placeholders and non-secret metadata

#### Scenario: A publisher is granted an explicit exception
- **WHEN** a publisher needs access beyond the contract's default write-only posture
- **THEN** the exception is declared explicitly in the contract or host assembly
- **AND** the exception is visible in rendered policy and covered by the regression check
