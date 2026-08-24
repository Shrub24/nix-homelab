## ADDED Requirements

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

## MODIFIED Requirements

### Requirement: Fleet state backups SHALL use host-scoped restic repositories
The fleet SHALL back up mutable host state using NixOS `services.restic.backups` with one dedicated object-storage bucket and one restic repository per host.

#### Scenario: Host backup configuration is rendered
- **WHEN** backup configuration is evaluated for `la-admin-1` or `oci-melb-1`
- **THEN** the host resolves a restic backup definition through the canonical NixOS module surface
- **AND** the repository target is isolated to that host via its dedicated bucket/repository rather than a shared cross-host repository
