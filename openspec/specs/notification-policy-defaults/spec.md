# notification-policy-defaults Specification

## Purpose
Define the notification defaults a host inherits: fleet-wide routing values, publisher principals and their permissions, and validation of both, held in repository policy and kept separate from the generic dispatch mechanics.

## Requirements

### Requirement: Policy defines notification defaults

The repository policy (`policy/globals.nix`) SHALL define a `notifications` section containing fleet-wide Telegram notification defaults that host configs inherit and may override.

#### Scenario: Host inherits policy defaults
- **WHEN** a host enables `services.notification-daemon.` without specifying `telegram.chatId` or `telegram.topics`

- **THEN** the notification-daemon module uses the values from `policy/globals.nix` as defaults
- **AND** notification routing is consistent across all hosts

#### Scenario: Host overrides specific tier topic

- **WHEN** a host overrides `services.notification-daemon.telegram.topics.warning` to a different topic ID
- **THEN** only the `warning` tier is affected; other tiers inherit from policy defaults

### Requirement: Tier mapping is extensible

The notification policy SHALL support an arbitrary number of named tiers, each mapping to a Telegram topic ID within a shared supergroup.

#### Scenario: New tier is added to policy

- **WHEN** a new tier entry is added to `policy/globals.nix` notifications section
- **THEN** the tier is immediately available to all consumers via `notify <new_tier>`
- **AND** the notification-daemon module assertion requires the tier to have a non-empty topic ID

### Requirement: Defaults are validated

The policy SHALL assert that chat ID and topic mappings are not empty placeholder values at evaluation time.

#### Scenario: Policy contains placeholder values

- **WHEN** `notifications.telegram.chatId` equals `"REPLACE_GROUP_CHAT_ID"` or an empty string
- **THEN** NixOS evaluation fails with an assertion message
- **AND** the operator must set real values before deployment

#### Scenario: Topic mapping is empty

- **WHEN** `notifications.telegram.topics` is an empty attrset
- **THEN** NixOS evaluation fails with an assertion message

### Requirement: Policy SHALL define ntfy publishers as explicit principals

The repository notification policy SHALL declare every authorized ntfy publisher as an explicit principal with a topic-wide permission. A publisher is a credential holder — a managed fleet host, a host from another fleet repository, a CLI, or a script — and not necessarily a canonical host ID of this repository, so publisher membership SHALL NOT be derived from the canonical host registry. The host running the ntfy server SHALL consume this policy, SHALL render `auth-access` from it alone, and SHALL NOT maintain a fleet publisher list of its own.

#### Scenario: Publisher ACLs are rendered

- **WHEN** the push-server capability evaluates
- **THEN** its ntfy ACL subjects derive from the publisher policy
- **AND** the rendered `auth-access` is that policy alone
- **AND** moving the push server does not change publisher membership

#### Scenario: Publisher credentials are inconsistent

- **WHEN** a declared publisher has no `auth-users` or `auth-tokens` entry in the decrypted auth file, or the file carries an `auth-access` key or a malformed `auth-users` entry
- **THEN** activation fails and names the offending publisher or entry
- **AND** no secret value is generated or exposed

#### Scenario: Non-publisher auth users exist

- **WHEN** the auth file provisions a user that is not a declared publisher, such as an administrator or a read-only client
- **THEN** the publisher contract holds and that user keeps its own role and permission

### Requirement: Notification policy SHALL remain separate from generic mechanics

Fleet publisher membership, routing topics, and backend destinations SHALL remain policy inputs to the notification implementation rather than built-in assumptions of the daemon, CLI, or systemd hook mechanism.

#### Scenario: Generic notification component is reused

- **WHEN** the daemon and hook module are composed with another valid policy
- **THEN** they consume typed routing and publisher inputs
- **AND** they contain no hard-coded homelab host identities or recipient values
