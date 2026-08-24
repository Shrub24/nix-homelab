# Spec: Host Storage Hygiene

## Purpose

Define declarative host storage hygiene contracts that bound root filesystem growth while preserving rollback-safe operations.
## Requirements
### Requirement: Host storage hygiene SHALL be declarative
`oci-melb-1` SHALL declare a repo-managed storage-hygiene policy for root-backed operational state instead of relying on manual cleanup alone.

#### Scenario: Host baseline is evaluated
- **WHEN** `nixosConfigurations.oci-melb-1` is evaluated
- **THEN** the rendered host configuration includes declarative storage-hygiene settings for Nix retention, journald retention, and Podman artifact cleanup

### Requirement: Nix retention SHALL reclaim stale store state automatically
The host SHALL automatically optimise the Nix store and garbage-collect stale paths on a recurring schedule while preserving a bounded rollback window.

#### Scenario: Automatic Nix cleanup runs
- **WHEN** the configured Nix garbage-collection schedule triggers
- **THEN** stale store paths older than the configured retention window are eligible for deletion
- **AND** store optimisation remains enabled

### Requirement: Journald retention SHALL be bounded for small root filesystems
The host SHALL cap persistent journald disk usage and retention so logs cannot grow without limit on the root filesystem.

#### Scenario: Persistent logs accumulate over time
- **WHEN** journald writes persistent logs on `oci-melb-1`
- **THEN** total journal usage is constrained by explicit repo-managed limits
- **AND** old logs are expired automatically according to the configured retention policy

### Requirement: Podman artifact cleanup SHALL run automatically
The host SHALL prune unused Podman artifacts on a recurring schedule so stopped containers, stale images, and unused volumes do not accumulate indefinitely on the root filesystem.

#### Scenario: Podman cleanup timer triggers
- **WHEN** the configured Podman cleanup timer runs
- **THEN** the host executes repo-managed Podman prune commands against unused artifacts
- **AND** active running services remain unaffected by the cleanup policy

### Requirement: Active hosts SHALL declare recurring Nix retention policy
Each active host SHALL declare automatic Nix retention and garbage-collection policy so store growth remains bounded under shared substitute usage.

#### Scenario: Active host Nix retention baseline is evaluated
- **WHEN** `nixosConfigurations.la-admin-1` and `nixosConfigurations.oci-melb-1` are evaluated
- **THEN** both include recurring Nix GC and bounded retention settings
- **AND** rollback-friendly retention windows remain explicitly configured

### Requirement: Storage hygiene expansion SHALL preserve break-glass recoverability
When storage hygiene is extended beyond one host, configured retention policies SHALL preserve an explicit rollback and recovery posture.

#### Scenario: Retention policy is reviewed for operational safety
- **WHEN** storage hygiene settings are inspected for both active hosts
- **THEN** retention choices bound stale store growth
- **AND** they do not remove documented rollback safety expectations from the operations baseline

