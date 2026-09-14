# notification-daemon Specification

## Purpose

Unified notification dispatch service: a FastAPI daemon with dual-backend support (apprise for Telegram, ntfy for UnifiedPush). Each host enables the daemon directly; there is no application-level wiring layer. The daemon and all notification tooling are contained in `services/notification-daemon/`.

## Architecture

```
services/notification-daemon/
    ├─ default.nix               NixOS module (secrets, systemd, CLI, monitor)
    ├─ notification_api/
    │    └─ main.py              FastAPI app dispatches to ALL configured backends:
    │                                1. apprise Python API → Telegram (if configured)
    │                                2. HTTP POST → ntfy server (if configured)
    └─ pyproject.toml            Python package build
```

## Requirements

### Requirement: Single service module owns the full notification stack

The `services.notification-daemon` module SHALL own the daemon systemd service, secrets, CLI, systemd monitor, and all routing configuration. Hosts SHALL only set `enable` and `secretFiles.host`.

#### Scenario: Host enables notification daemon

- **WHEN** a host declares `services.notification-daemon.enable = true` with `secretFiles.host`
- **THEN** the daemon service starts after sops-nix
- **AND** the daemon reads config from `/etc/notification-daemon/config.json`
- **AND** secrets from `/run/secrets/notification-daemon/telegram_bot_token`
- **AND** if `ntfy.enable = true`, reads `/run/secrets/notification-daemon/ntfy_token`

### Requirement: Daemon provides generic HTTP endpoint with multi-backend dispatch

The notification-daemon SHALL run a FastAPI daemon on `127.0.0.1:5555` that accepts notification requests via HTTP. The daemon SHALL dispatch to ALL configured backends for every notification — currently apprise (Telegram) and ntfy (UnifiedPush). Backend-agnostic: new backends can be added without changing the module interface.

#### Scenario: Daemon accepts valid notification

- **WHEN** `POST /notify` receives `{"tier":"info","title":"Test","message":"body","type":"test","topic":"system"}`
- **THEN** the daemon returns HTTP 200
- **AND** dispatches via apprise to the Telegram topic mapped to the `info` tier
- **AND** also POSTs to the ntfy topic specified by `topic` (default maps from tier)

#### Scenario: Daemon rejects unknown tier

- **WHEN** `POST /notify` receives `{"tier":"unknown_tier","title":"Test"}`
- **THEN** the daemon returns HTTP 400
- **AND** the JSON error body lists the known tiers from the config

#### Scenario: Daemon health check

- **WHEN** `GET /health`
- **THEN** the daemon returns HTTP 200 with `{"status":"ok"}`

#### Scenario: Daemon handles partial backend failure

- **WHEN** ntfy is unreachable but Telegram is available
- **THEN** the daemon SHALL still dispatch via apprise
- **AND** SHALL log the ntfy error
- **AND** return HTTP 200 if at least one backend succeeded, or HTTP 500 if all backends failed

### Requirement: Daemon supports ntfy dual-dispatch with semantic topics

When `ntfy.enable = true`, the daemon SHALL POST notifications to the configured ntfy server in addition to the apprise dispatch. Notifications are sent to semantic ntfy topics (e.g. `system`, `services`, `web`, `music`) with priority (1-5) mapped from the notification type.

#### Scenario: Host enables ntfy dispatch

- **WHEN** a host sets `services.notification-daemon.ntfy.enable = true` and `serverUrl`
- **THEN** `/etc/notification-daemon/config.json` contains an `ntfy` block with `server_url`, semantic `topics`, and `token_file`
- **AND** the daemon POSTs each notification to `<server_url>/<topic>` with the message body, title header, and priority mapped from the notification type
- **AND** the daemon accepts an optional `topic` field in the POST body for overriding the tier-based default

#### Scenario: ntfy uses bearer token auth

- **WHEN** `ntfy_token` is present in the SOPS secret file
- **THEN** the daemon reads it at `/run/secrets/notification-daemon/ntfy_token`
- **AND** includes `Authorization: Bearer <token>` in the ntfy POST

### Requirement: CLI provides testable notification contract via daemon

The module SHALL install a `notify` CLI that accepts a tier, title, optional type, optional topic, and optional message body (from stdin), then POSTs to the daemon. The CLI is a thin Python script with no standalone routing logic.

#### Scenario: CLI sends notification successfully

- **WHEN** `notify info "Test title"` with `"test body"` piped on stdin
- **THEN** the CLI POSTs `{"tier":"info","title":"Test title","message":"test body","type":"info"}` to the daemon
- **AND** returns the daemon's HTTP status code

#### Scenario: CLI sends with topic override

- **WHEN** `notify warning "Build failed" failure music`
- **THEN** the CLI POSTs `{"tier":"warning","title":"Build failed","type":"failure","topic":"music"}` to the daemon

#### Scenario: CLI handles daemon down

- **WHEN** the daemon is not running and a user calls `notify info "test"`
- **THEN** the CLI prints a clear connection-refused error to stderr
- **AND** exits with non-zero status

### Requirement: Secrets follow feature-topology contract

The module SHALL register its SOPS secrets internally and accept only a `secretFiles.host` path from host configuration, following the established feature-topology secret-contract pattern. The secret file SHALL contain `telegram_bot_token` and optionally `ntfy_token`.

#### Scenario: Host enables notification with secret file

- **WHEN** a host declares `services.notification-daemon.enable = true` with `secretFiles.host`
- **THEN** the module registers `sops.secrets."notification-daemon/telegram_bot_token"` with path `/run/secrets/notification-daemon/telegram_bot_token`
- **AND** the secret is owned by `root:root` with mode `0440`
- **AND** if `ntfy.enable = true`, `sops.secrets."notification-daemon/ntfy_token"` is registered similarly

#### Scenario: Host omits secret file or disables

- **WHEN** `services.notification-daemon.enable = true` and `secretFiles.host` is null
- **THEN** evaluation fails with an assertion error naming `secretFiles.host`

### Requirement: Daemon has proper systemd integration

The daemon SHALL run as a systemd service with correct dependency ordering for secret availability.

#### Scenario: Daemon starts after secrets are available

- **WHEN** the system boots
- **THEN** `notification-daemon.service` starts after `sops-nix.service` finishes
- **AND** the daemon can read `/run/secrets/notification-daemon/telegram_bot_token` and `/run/secrets/notification-daemon/ntfy_token` at startup

#### Scenario: Daemon auto-restarts on crash

- **WHEN** the daemon process exits unexpectedly
- **THEN** systemd restarts it (`Restart=on-failure`)
- **AND** the maximum restart rate prevents infinite restart loops

### Requirement: Monitor injects notification hooks into systemd services

The module SHALL support typed, additive per-unit monitoring contributions that inject only the requested `OnFailure`, `ExecStartPost`, and `ExecStopPost` hooks into systemd services with real implementations. The `svc-monitor@.service` template SHALL capture journal output on failure and POST it to the notification daemon. Evaluation SHALL fail when an enabled monitor contribution names a service with no implementation.

#### Scenario: Service failure triggers notification

- **WHEN** an owning capability enables failure monitoring for one of its implemented systemd services
- **THEN** systemd triggers `svc-monitor@<service>.service` when that service fails
- **AND** the monitor captures the last 50 journal lines from that service
- **AND** existing owner-defined `OnFailure` units remain present
- **AND** the daemon dispatches the failure notification to configured backends

#### Scenario: Service start sends info notification

- **WHEN** an owning capability enables start monitoring for an implemented service and it starts successfully
- **THEN** systemd appends an `ExecStartPost` hook that calls `svc-monitor <service> onStart`
- **AND** existing owner-defined `ExecStartPost` commands remain present and ordered deterministically
- **AND** the daemon dispatches the info notification to configured backends

#### Scenario: Selected stop event is composed

- **WHEN** an owning capability enables stop monitoring for an implemented service
- **THEN** systemd appends an `ExecStopPost` hook that calls `svc-monitor <service> onSuccess`
- **AND** existing owner-defined `ExecStopPost` commands remain present and ordered deterministically

#### Scenario: Phantom monitor target is rejected

- **WHEN** an enabled monitor contribution names a systemd service that has no real service implementation
- **THEN** evaluation fails with an assertion naming that unit
- **AND** monitor-generated hooks do not satisfy the implementation check

#### Scenario: Beets monitoring follows music placement

- **WHEN** home-forge selects the music capability and OCI does not
- **THEN** the real home-forge Beets units receive their declared generic monitor hooks
- **AND** their Beets-owned retry and failure hooks remain present
- **AND** OCI evaluates no synthetic Beets service fragments

### Requirement: Notification aspect SHALL guarantee daemon composition for fleet consumers
The notification foundation aspect SHALL own daemon availability by composing the notification-daemon module, so fleet consumers such as backup monitoring can rely on the daemon wherever the aspect is enabled without each host or consumer importing the module leaf separately.

#### Scenario: Backup monitoring relies on the notification aspect
- **WHEN** a host enables the notification foundation aspect and runs backup monitoring
- **THEN** the notification-daemon module is composed and available to the monitor
- **AND** the monitor does not need its own notification-daemon module import

#### Scenario: Host configuration remains host-specific
- **WHEN** a host enables the notification aspect
- **THEN** the host still provides only host-specific inputs through the module's established secret contract
- **AND** the aspect guarantees the daemon, CLI, and monitor composition
