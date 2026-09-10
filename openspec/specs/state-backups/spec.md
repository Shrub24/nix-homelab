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

### Requirement: Backups aspect SHALL own state backup and cache-upload composition
The backups aspect SHALL compose host-scoped restic state backups, the niks3 upload client, and post-deploy closure upload for hosts that select it, and selecting the aspect SHALL be its enablement without hidden transitive imports. The aspect SHALL import the upstream `niks3-auto-upload` module itself and SHALL inject the required post-deploy filter package through a typed option, so it has no hidden `fleet-packages` dependency.

#### Scenario: Host selects the backups aspect
- **WHEN** a host selects the backups aspect
- **THEN** the host-scoped restic state backup definition, the niks3 upload client, and the post-deploy closure upload are composed by the aspect
- **AND** the host assembly does not repeat the state-backups, niks3-upload-client, or niks3-post-deploy leaf imports or enablement
- **AND** the host registry does not import the `niks3-auto-upload` upstream module (the aspect owns that import)

#### Scenario: Backup bucket convention is derived from the host name
- **WHEN** the backups aspect is evaluated for a host
- **THEN** the restic repository target derives the existing `shrublab-backup-${hostName}` bucket convention from the host name
- **AND** host-specific staging roots and path variants remain configurable per host

#### Scenario: Post-deploy filter package is injected by the aspect
- **WHEN** the post-deploy leaf is evaluated under the backups aspect
- **THEN** the required typed `services.niks3-post-deploy.filterPackage` option is set per system by the aspect via `withSystem`
- **AND** the leaf does not read `config.repo.packages`, so the aspect has no hidden `fleet-packages` dependency

### Requirement: Backups aspect SHALL derive the conventional host secret path and gate on its existence
The backups aspect SHALL derive the conventional host secret path `secrets/hosts/${hostName}/system.yaml`, SHALL default `services.state-backups.secretFile` to it, and SHALL enable state-backups, the niks3 client, and post-deploy only when that file exists, preserving two-step secret bootstrap on every host.

#### Scenario: Host has host secrets present
- **WHEN** the conventional host secret file exists for a host
- **THEN** state-backups, the niks3 client, and post-deploy are enabled with the derived secret path
- **AND** the host assembly does not repeat the `secretFile` binding

#### Scenario: Host is bootstrapped before host secrets exist
- **WHEN** a host is evaluated before its `secrets/hosts/<host>/system.yaml` file has been added
- **THEN** state-backups, the niks3 client, and post-deploy stay disabled without failing the base activation
- **AND** they activate once the host secret exists, preserving the two-step secret bootstrap behavior

### Requirement: Backups aspect SHALL require notification monitoring without importing it
A host that enables the backups aspect SHALL also select the notification aspect, enforced by an explicit evaluation assertion on the actual monitor option (`services.notification-daemon.monitor.enable`), and the backups aspect SHALL NOT import the notification aspect. The notification aspect SHALL own monitor composition (canonical apprise contract); the state-backups leaf SHALL NOT set the monitor enable default.

#### Scenario: Backups is enabled without notifications
- **WHEN** a host enables the backups aspect without selecting the notification aspect
- **THEN** evaluation fails with an explicit assertion naming the missing notification monitor composition

#### Scenario: Backups is enabled with notifications
- **WHEN** a host enables the backups aspect and selects the notification aspect
- **THEN** evaluation succeeds
- **AND** backup service failures continue to route through the fleet notification pipeline

### Requirement: Derived backup bucket name SHALL be a valid S3 bucket name
The backups aspect SHALL assert that the derived `shrublab-backup-${hostName}` bucket name is a valid S3 bucket name: 3–63 characters, lowercase alphanumerics and hyphens only.

#### Scenario: Derived bucket name is valid
- **WHEN** the backups aspect derives the bucket name for a host
- **THEN** the name matches the 3–63 lowercase alnum/hyphen rule and evaluation succeeds

#### Scenario: Derived bucket name is invalid
- **WHEN** a host name would produce a bucket name outside the 3–63 lowercase alnum/hyphen rule
- **THEN** evaluation fails with an explicit assertion naming the bucket-name rule
