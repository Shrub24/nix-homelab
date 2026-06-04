# Spec: Notification Policy Defaults

## Purpose

Define fleet-wide defaults for notification routing, including Telegram chat ID and tier-to-topic mapping, as part of the centralized policy system.

## ADDED Requirements

### Requirement: Policy defines notification defaults

The repository policy (`policy/globals.nix`) SHALL define a `notifications` section containing fleet-wide Telegram notification defaults that host configs inherit and may override.

#### Scenario: Host inherits policy defaults

- **WHEN** a host enables `services.apprise` without specifying `telegram.chatId` or `telegram.topics`
- **THEN** the apprise module uses the values from `policy/globals.nix` as defaults
- **AND** notification routing is consistent across all hosts

#### Scenario: Host overrides specific tier topic

- **WHEN** a host overrides `services.apprise.telegram.topics.critical` to a different topic ID
- **THEN** only the critical tier is affected; other tiers inherit from policy defaults

### Requirement: Tier mapping is extensible

The notification policy SHALL support an arbitrary number of named tiers, each mapping to a Telegram topic ID within a shared supergroup.

#### Scenario: New tier is added to policy

- **WHEN** a new tier entry is added to `policy/globals.nix` notifications section
- **THEN** the tier is immediately available to all consumers via `apprise-notify <new_tier>`
- **AND** the apprise module assertion requires the tier to have a non-empty topic ID

### Requirement: Defaults are validated

The policy SHALL assert that chat ID and topic mappings are not empty placeholder values at evaluation time.

#### Scenario: Policy contains placeholder values

- **WHEN** `notifications.telegram.chatId` equals `"REPLACE_GROUP_CHAT_ID"` or an empty string
- **THEN** NixOS evaluation fails with an assertion message
- **AND** the operator must set real values before deployment

#### Scenario: Topic mapping is empty

- **WHEN** `notifications.telegram.topics` is an empty attrset
- **THEN** NixOS evaluation fails with an assertion message
