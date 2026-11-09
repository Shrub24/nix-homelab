# Spec Delta

## Purpose

Make a registered systemd failure event mean that automatic recovery ended, and keep the
per-attempt record in the journal and the telemetry pipelines.

## ADDED Requirements

### Requirement: A registered failure event SHALL report exhausted recovery
A unit registered under `services.notify.events` that automatically restarts SHALL run in
`RestartMode=direct`, so that systemd does not expose an intermediate failed state — and therefore
does not start the `OnFailure=` handler — for the attempts it is about to retry. The handler SHALL
be started when the retries end.

#### Scenario: A monitored unit crashes and recovers
- **WHEN** a monitored unit fails and systemd retries it within its start limit
- **THEN** the failure handler is not started for that attempt
- **AND** the invocation remains in the journal and in the log pipeline

#### Scenario: A monitored unit exhausts its retries
- **WHEN** a monitored unit fails often enough to reach its start limit
- **THEN** the unit enters the failed state
- **AND** its `OnFailure=` notification handler is started once

#### Scenario: A unit nobody monitors keeps its own policy
- **WHEN** a restarting unit is not registered under `services.notify.events`
- **THEN** it carries no `RestartMode` from the notification policy
- **AND** a notification mode found on such a unit fails the contract check

### Requirement: A monitored restarting unit SHALL have a finite start limit
A registered unit that automatically restarts SHALL declare a finite
`StartLimitIntervalSec`/`StartLimitBurst`; the notification policy supplies five starts an hour
unless the unit's owner sets its own. Registration on a unit that disables its start limit SHALL
fail evaluation with a named `notify:` error, because no ending would exist for the event to
report.

#### Scenario: The owner sets no budget
- **WHEN** a monitored restarting unit declares no start limit
- **THEN** the rendered unit carries the policy's finite window

#### Scenario: The owner sets a budget
- **WHEN** a monitored restarting unit declares its own start limit
- **THEN** the owner's value is rendered and the policy's default does not apply

#### Scenario: The owner disables the limit
- **WHEN** a registered unit sets `StartLimitIntervalSec=0` or `infinity`
- **THEN** evaluation fails with a `notify:` message naming the unit

### Requirement: The contract SHALL be proven non-vacuous
The repository contract check SHALL evaluate every host and SHALL fail when a rule stops detecting
a violation. It SHALL exercise at least: a forced `normal` restart mode on a monitored unit, a
forced `direct` mode on an unmonitored unit, and a disabled start limit on a monitored unit.

#### Scenario: A rule stops working
- **WHEN** the rendered unit files no longer match the contract and the mutation of the same field
  is also accepted
- **THEN** the check fails with the mutation it could not detect
