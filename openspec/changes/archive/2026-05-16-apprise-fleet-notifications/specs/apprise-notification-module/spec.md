# Spec: Apprise Notification Module

## Purpose

Define the notification infrastructure module that owns all routing, token management, and daemon/CLI tooling for fleet-wide apprise-based notifications.

## ADDED Requirements

### Requirement: Module owns notification internals

The apprise module SHALL own all notification routing internals (URL construction, token file path, chat ID, topic mapping) and SHALL NOT expose these to consumer modules. Consumers SHALL interact only via the `apprise-notify` CLI or the daemon HTTP endpoint.

#### Scenario: Consumer module sends notification via CLI

- **WHEN** a consumer module calls `apprise-notify music "Import failure"`
- **THEN** the CLI POSTs `{"tier":"music","title":"Import failure"}` to `http://127.0.0.1:5555/notify`
- **AND** the consumer has zero references to token paths, chat IDs, or apprise URL format

#### Scenario: Consumer sends notification via HTTP

- **WHEN** a consumer POSTs `{"tier":"warning","title":"Disk full","message":"90%"}` to `http://127.0.0.1:5555/notify`
- **THEN** the daemon reads `/etc/apprise/notify.json` for routing configuration
- **AND** dispatches via apprise Python library to the Telegram topic mapped to `warning`

### Requirement: Daemon provides HTTP endpoint

The module SHALL run a FastAPI daemon on `127.0.0.1:5555` that accepts notification requests via HTTP and dispatches via apprise Python API (no shell, no subprocess).

#### Scenario: Daemon accepts valid notification

- **WHEN** `POST /notify` receives `{"tier":"info","title":"Test","message":"body","type":"test"}`
- **THEN** the daemon returns HTTP 200
- **AND** dispatches the message to the Telegram topic mapped to the `info` tier

#### Scenario: Daemon rejects unknown tier

- **WHEN** `POST /notify` receives `{"tier":"unknown_tier","title":"Test"}`
- **THEN** the daemon returns HTTP 400
- **AND** the JSON error body lists the known tiers from the config

#### Scenario: Daemon health check

- **WHEN** `GET /health`
- **THEN** the daemon returns HTTP 200 with `{"status":"ok"}`

#### Scenario: Daemon fails on apprise error

- **WHEN** apprise cannot reach the Telegram API
- **THEN** the daemon returns HTTP 500 with a JSON error body describing the failure

### Requirement: CLI provices testable notification contract via daemon

The module SHALL install an `apprise-notify` CLI that accepts a tier name, title, and optional message body, then POSTs to the daemon. The CLI is a thin wrapper (shell script or Python one-liner) with no standalone routing logic.

#### Scenario: CLI sends notification successfully

- **WHEN** `apprise-notify info "Test title" "test body"`
- **THEN** the CLI POSTs `{"tier":"info","title":"Test title","message":"test body","type":"info"}` to the daemon
- **AND** returns the daemon's HTTP status code

#### Scenario: CLI passes message via stdin

- **WHEN** `echo "stdin body" | apprise-notify info "Title"`
- **THEN** the CLI reads stdin into the `message` field of the POST body
- **AND** the daemon dispatches the message with body "stdin body"

#### Scenario: CLI handles daemon down

- **WHEN** the daemon is not running and a user calls `apprise-notify info "test"`
- **THEN** the CLI prints a clear connection-refused error to stderr
- **AND** exits with non-zero status

### Requirement: Secrets follow feature-topology contract

The module SHALL register its SOPS secret internally and accept only a `secretFiles.host` path from host configuration, following the established feature-topology secret-contract pattern.

#### Scenario: Host enables apprise with secret file

- **WHEN** a host declares `services.apprise.enable = true` with `secretFiles.host = ./secrets/services/apprise.yaml`
- **THEN** the module registers `sops.secrets."apprise/telegram_bot_token"` with path `/run/secrets/apprise/telegram_bot_token`
- **AND** the secret is owned by `root:apprise` with mode `0440`

#### Scenario: Host omits secret file or disables

- **WHEN** `services.apprise.enable = true` and `secretFiles.host` is null
- **THEN** evaluation fails with an assertion error naming `secretFiles.host`

### Requirement: Module creates dedicated access group

The module SHALL create a system group `apprise` and SHALL ensure the Telegram bot token secret is readable only by members of that group.

#### Scenario: Authorized user reads secret

- **WHEN** a user in the `apprise` group runs `apprise-notify info "test"`
- **THEN** the CLI POSTs to the daemon (which reads the token file via root-owned daemon process)
- **AND** the notification is dispatched successfully

#### Scenario: Unauthorized user cannot read secret

- **WHEN** a user NOT in the `apprise` group attempts to run `apprise-notify`
- **THEN** the CLI POSTs to the daemon (daemon runs as root and owns the token)
- **AND** the notification is dispatched successfully (access is via daemon, not secret file ownership—the `apprise` group controls who can install/manage the module, not who can send notifications)

### Requirement: Daemon has proper systemd integration

The daemon SHALL run as a systemd service with correct dependency ordering for secret availability.

#### Scenario: Daemon starts after secrets are available

- **WHEN** the system boots
- **THEN** `apprise-webhook.service` starts after `sops-nix.service` finishes
- **AND** the daemon can read `/run/secrets/apprise/telegram_bot_token` at startup

#### Scenario: Daemon auto-restarts on crash

- **WHEN** the daemon process exits unexpectedly
- **THEN** systemd restarts it (Restart=on-failure)
- **AND** the maximum restart rate prevents infinite restart loops
