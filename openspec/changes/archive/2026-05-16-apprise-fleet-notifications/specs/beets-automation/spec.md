# Delta Spec: Beets Automation (Notification)

## ADDED Requirements

### Requirement: Beets failure notification uses apprise

The Beets automation system SHALL notify operators of runner failures via the apprise notification CLI, using the `music` notification tier.

#### Scenario: Beets runner fails

- **WHEN** a `beets-*` systemd service fails
- **THEN** the `beets-notify-failure@` template unit is triggered via `OnFailure=`
- **AND** the notification script gathers the last 20 log lines from the failed service via `journalctl`
- **AND** pipes the log output to `apprise-notify music "Beets runner beets-$runner failed on $hostname"`
- **AND** if journalctl produces no output, the message body is `(no journal output)`

#### Scenario: Beets notification targets correct Telegram topic

- **WHEN** a beets runner failure notification is dispatched
- **THEN** the notification arrives in the Telegram topic mapped to the `music` tier
- **AND** the notification does NOT appear in system warning or critical topics

### Requirement: Beets notification script has no direct apprise or secret access

The Beets notification script SHALL NOT construct apprise URLs, read token files, or reference chat/topic IDs directly. It SHALL only call `apprise-notify` with a tier and title.

#### Scenario: Notification script is inspected

- **WHEN** an operator reads the generated `beets-notify-failure` script
- **THEN** the script contains no references to `tgram://`, `/run/secrets/apprise/`, or raw apprise flags beyond the `apprise-notify` invocation
- **AND** the script's runtime dependencies are `pkgs.systemd` only (apprise and jq are provided by the apprise module)

### Requirement: Beets notification configuration uses tier abstraction

The Beets notify configuration SHALL expose a single `tier` option that references an apprise notification tier, replacing the previous ntfy-specific options.

#### Scenario: Operator configures beets notifications

- **WHEN** `services.beets.notify.enable = true` and `services.beets.notify.tier = "music"`
- **THEN** all beets failure notifications are routed to the `music` tier
- **AND** no ntfy URL, token, or topic options exist in the beets configuration

#### Scenario: Beets notifications disabled

- **WHEN** `services.beets.notify.enable = false`
- **THEN** no `beets-notify-failure@` systemd unit is generated
- **AND** runner failures are silent (logged only)
