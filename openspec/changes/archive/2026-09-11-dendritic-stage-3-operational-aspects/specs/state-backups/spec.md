# Delta Spec: State Backups

## ADDED Requirements

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