## MODIFIED Requirements

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
