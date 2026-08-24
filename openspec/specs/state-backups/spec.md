# state-backups Specification

## Purpose

Define the fleet's declarative state backup architecture: host-scoped restic repositories, explicit consistency classes, consistent export-first recovery artifacts, and a canonical restore path.

## Requirements

### Requirement: Fleet state backups SHALL use host-scoped restic repositories
The fleet SHALL back up mutable host state using NixOS `services.restic.backups` with one dedicated object-storage bucket and one restic repository per host.

#### Scenario: Host backup configuration is rendered
- **WHEN** backup configuration is evaluated for `la-admin-1` or `oci-melb-1`
- **THEN** the host resolves a restic backup definition through the canonical NixOS module surface
- **AND** the repository target is isolated to that host via its dedicated bucket/repository rather than a shared cross-host repository

### Requirement: Initial backup scope SHALL include service state and exclude media payloads
Initial fleet backups SHALL include mutable service state and generated export artifacts, SHALL exclude repo-owned immutable configuration, and SHALL exclude `/srv/media` from required backup coverage in this wave.

#### Scenario: Backup path scope is reviewed
- **WHEN** canonical backup paths and exclusions are inspected
- **THEN** service state paths under declared managed roots such as `/srv/data` are included
- **AND** `/srv/media` is excluded from required backup payload in this change

### Requirement: Backup consistency SHALL use explicit service classes
Each backed-up stateful service SHALL declare or inherit an explicit consistency class of `export`, `quiesce`, or `live` that determines whether the service generates an app-native restorable backup artifact, stabilizes runtime state around the backup window, or allows direct live capture.

#### Scenario: Service backup policy is reviewed
- **WHEN** a stateful service participates in fleet backup coverage
- **THEN** its backup behavior maps to one declared consistency class
- **AND** operators can determine from configuration whether export artifacts, stop/start coordination, or live capture is expected

### Requirement: Export-first services SHALL capture portable artifacts and raw state initially
Services classified as `export` SHALL generate an app-native restorable recovery artifact before backup and SHALL also include raw service state in the initial backup contract unless a later change narrows that policy.

#### Scenario: Export-first service backup runs
- **WHEN** a configured export-first service backup job executes
- **THEN** a portable export artifact is produced before restic capture
- **AND** the backup payload still includes the service’s underlying state directory in this wave

### Requirement: Backup repositories SHALL support recurring integrity and retention policy
The canonical backup architecture SHALL define recurring backup execution, retention pruning, and repository integrity verification expectations for each host.

#### Scenario: Backup operator policy is reviewed
- **WHEN** recurring backup behavior is inspected for a host
- **THEN** the host defines schedule, prune policy, and repository-check behavior declaratively
- **AND** missed scheduled runs can resume through persistent timer behavior or equivalent declarative recovery semantics

### Requirement: AudioMuse backups SHALL prioritize durable database state
AudioMuseAI backup coverage SHALL distinguish durable PostgreSQL state from non-canonical Redis queue/cache and temp working data.

#### Scenario: AudioMuse backup policy is reviewed
- **WHEN** AudioMuseAI participates in host state backup coverage
- **THEN** PostgreSQL-backed AudioMuse state SHALL be included as the primary durable recovery target, noting that this is the **existing shared Postgres instance** (`services.postgres-shared`), not a dedicated AudioMuse-local Postgres volume
- **AND** Redis and temp audio working paths SHALL NOT be treated as canonical backup state unless implementation validation proves they are required for recovery
- **AND** media library payloads under `/srv/media` SHALL remain governed by host media backup policy rather than AudioMuse service policy

### Requirement: Host replacement SHALL verify restored authority before source retirement
When a stateful host is replaced, the replacement host SHALL complete a backup, restore, and service-validation cycle before the source host and its recovery repository are retired.

#### Scenario: LA backup is established after cutover
- **WHEN** `la-admin-1` receives public edge and identity traffic
- **THEN** it creates and verifies a backup in its own host-scoped repository
- **AND** the prior DigitalOcean repository remains available as recovery evidence through the declared retention window

### Requirement: Kanidm backup coverage SHALL capture its portable export
Kanidm backup coverage SHALL capture its built-in portable backup artifacts from `/var/lib/kanidm/backups`; it SHALL NOT claim the unused `/srv/data/kanidm` path is the active server database.

#### Scenario: Kanidm host backup runs
- **WHEN** the shared state backup runs for the identity host
- **THEN** the latest Kanidm portable export is included in the restic payload
- **AND** the declared recovery input is suitable for version-matched offline restore

### Requirement: Database backup coverage SHALL prefer consistent export artifacts
Stateful database services SHALL create declarative, consistent recovery artifacts before restic snapshots them when an upstream logical export is available. Export directories SHALL be created by configuration rather than operator preparation, and raw live database directories SHALL NOT be presented as portable recovery artifacts.

#### Scenario: The shared PostgreSQL backup runs on OCI
- **WHEN** `restic-backups-state.service` prepares the OCI backup payload
- **THEN** it creates a logical PostgreSQL export containing the shared cluster databases and roles
- **AND** restic captures that export instead of the live `/srv/data/postgres` directory
- **AND** the export destination exists on a fresh host without a manual `mkdir`

#### Scenario: The Vaultwarden backup runs on LA
- **WHEN** the Vaultwarden SQLite export command runs
- **THEN** its staging directory already exists declaratively
- **AND** the consistent SQLite export is included in the backup payload

### Requirement: Backup coverage and exclusions SHALL be explicit
Each active host backup contract SHALL name real state or export paths and SHALL document state excluded because it is reproducible, ephemeral, or stored in an external authority. Dynamic-user compatibility symlinks SHALL NOT be used as restic payload roots.

#### Scenario: Fleet backup coverage is reviewed
- **WHEN** the LA and OCI state-backup contracts are evaluated
- **THEN** every included path resolves to the intended data or export directory
- **AND** ntfy, agent caches, ACME state, and external object-storage assets are either covered or listed with their recovery posture
- **AND** backup service failures are routed through the fleet notification pipeline

### Requirement: Restore operations SHALL be staged and documented
The repository SHALL provide one canonical state-restore runbook and a safe operator command that restores a selected snapshot into a staging directory without overwriting live service state. The runbook SHALL define the authoritative artifact, stop/apply/ownership/start sequence, and verification gate for each covered stateful service.

#### Scenario: An operator validates a restic snapshot
- **WHEN** the operator invokes the restore-staging command for a host and snapshot
- **THEN** the payload is restored under a non-live staging root
- **AND** no running service or live state directory is modified
- **AND** the runbook identifies the service-specific command that applies the staged artifact
