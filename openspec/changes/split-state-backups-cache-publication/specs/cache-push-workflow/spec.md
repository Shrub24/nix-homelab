## ADDED Requirements

### Requirement: Cache-publisher aspect SHALL own closure publication composition

The `cache-publisher` aspect SHALL compose the Niks3 upload client, activation-triggered post-deploy closure publication, closure filtering, cache write authentication, and publication observability. It SHALL NOT enable mutable state backups.

#### Scenario: Host selects cache-publisher

- **WHEN** a host selects `cache-publisher` and its host-scoped publication secret exists
- **THEN** the upload client and post-deploy publication trigger retain their existing behavior
- **AND** no restic backup unit, timer, repository, or mutable-state export is introduced by that selection

#### Scenario: Host omits cache-publisher

- **WHEN** a host selects state-backups but not cache-publisher
- **THEN** state backup behavior remains available
- **AND** no Niks3 upload daemon or post-deploy closure push is enabled

### Requirement: Cache publication SHALL have an independent bootstrap and monitoring contract

The cache-publisher capability SHALL gate itself on its required host-scoped secret inputs and SHALL contribute monitoring for its own units without relying on state-backup selection.

#### Scenario: Publication secret is absent during bootstrap

- **WHEN** a host is evaluated before its cache publication secret is available
- **THEN** cache publication remains disabled without failing base activation
- **AND** state-backup enablement is unaffected

#### Scenario: Publication fails

- **WHEN** the post-deploy upload unit fails
- **THEN** its owning capability emits the configured monitoring signal
- **AND** the failure does not roll back the activated generation
