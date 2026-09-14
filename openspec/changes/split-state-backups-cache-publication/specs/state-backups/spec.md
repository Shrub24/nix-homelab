## ADDED Requirements

### Requirement: State-backups aspect SHALL own only mutable state recovery composition

The `state-backups` aspect SHALL compose host-scoped restic backups, mutable-state contributions, consistency/export behavior, retention, restore contracts, and backup monitoring. It SHALL NOT import, enable, configure, or authenticate Nix closure publication.

#### Scenario: Host selects state-backups

- **WHEN** a host selects the `state-backups` aspect
- **THEN** its canonical restic state backup behavior is enabled subject to the existing two-step secret gate
- **AND** no Niks3 upload client or post-deploy closure push is enabled by that selection
- **AND** backup units contribute their own notification monitoring relationship

#### Scenario: Host omits state-backups

- **WHEN** a host selects cache publication but not state-backups
- **THEN** no restic state backup unit, timer, repository, or mutable-state export is introduced

### Requirement: State-backups aspect SHALL derive the conventional host secret path and gate on its existence

The `state-backups` aspect SHALL derive the conventional host secret path `secrets/hosts/${hostName}/system.yaml`, SHALL default `services.state-backups.secretFile` to it, and SHALL enable only state-backup behavior when that file exists.

#### Scenario: Host has host secrets present

- **WHEN** the conventional host secret file exists
- **THEN** state-backups is enabled with the derived secret path
- **AND** the host does not repeat that binding

#### Scenario: Host is bootstrapped before host secrets exist

- **WHEN** the conventional host secret file is absent
- **THEN** state-backups remains disabled without failing base activation
- **AND** cache publication follows its own independent bootstrap gate

## MODIFIED Requirements

### Requirement: Derived backup bucket name SHALL be a valid S3 bucket name

The `state-backups` aspect SHALL derive the existing `shrublab-backup-${hostName}` bucket convention from the host name and SHALL assert that the result is a valid S3 bucket name: 3–63 characters, lowercase alphanumerics and hyphens only.

#### Scenario: Backup bucket convention is derived from the host name

- **WHEN** the `state-backups` aspect is evaluated for a host
- **THEN** the restic repository target derives `shrublab-backup-${hostName}` from that host name
- **AND** host-specific staging roots and path variants remain configurable per host

#### Scenario: Derived bucket name is valid

- **WHEN** the `state-backups` aspect derives the bucket name for a host
- **THEN** the name matches the 3–63 lowercase alnum/hyphen rule and evaluation succeeds

#### Scenario: Derived bucket name is invalid

- **WHEN** a host name would produce a bucket name outside the 3–63 lowercase alnum/hyphen rule
- **THEN** evaluation fails with an explicit assertion naming the bucket-name rule

## REMOVED Requirements

### Requirement: Backups aspect SHALL own state backup and cache-upload composition

**Reason**: Mutable state recovery and immutable closure publication have distinct state, security, and lifecycle boundaries and are replaced by independent placement aspects.

**Migration**: Replace each `backups` selection with explicit `state-backups` and `cache-publisher` selections; the former owns the state-backup behavior and the latter owns Niks3 upload and post-deploy publication.

### Requirement: Backups aspect SHALL derive the conventional host secret path and gate on its existence

**Reason**: The shared gate coupled two independent capabilities.

**Migration**: Each replacement aspect derives the same conventional host secret path and gates only its own behavior.

### Requirement: Backups aspect SHALL require notification monitoring without importing it

**Reason**: Monitoring requirements belong to each independent capability rather than the removed combined aspect.

**Migration**: `state-backups` and `cache-publisher` contribute monitoring for their own units and use explicit notification contracts.
