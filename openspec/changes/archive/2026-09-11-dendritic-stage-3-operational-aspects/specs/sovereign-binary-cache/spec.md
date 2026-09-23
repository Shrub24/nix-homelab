# Delta Spec: Sovereign Binary Cache

## ADDED Requirements

### Requirement: Post-deploy cache push SHALL be composed by the backups aspect
The post-deploy cache push SHALL be composed by the backups aspect for hosts that select it, without changing the activation trigger, the filtered closure push behavior, or the classified upstream post-build-hook suppression.

#### Scenario: Host with backups enabled activates a new generation
- **WHEN** a host selects the backups aspect and activates a new system generation
- **THEN** the post-deploy push unit SHALL run after activation with the same trigger as before the ownership change
- **AND** the pushed closure SHALL exclude paths signed only by the configured public cache keys

#### Scenario: Upstream post-build-hook suppression is preserved
- **WHEN** the niks3 upload client is evaluated under the backups aspect
- **THEN** the automatic Nix post-build-hook remains disabled as the classified compatibility constraint of upstream `niks3-auto-upload`
- **AND** the daemon/socket required by post-deploy upload remains available
- **AND** no additional override or relocated suppression is introduced

#### Scenario: Host-specific upload variants are preserved
- **WHEN** a host that owns the cache server selects the backups aspect
- **THEN** the host's niks3 token ownership override and loopback cache endpoint are preserved
- **AND** upload-client defaults remain overridable per host

#### Scenario: Post-deploy filter package is injected by the backups aspect
- **WHEN** the post-deploy leaf is evaluated under the backups aspect
- **THEN** the required `services.niks3-post-deploy.filterPackage` option is set per system by the aspect via `withSystem`
- **AND** the leaf does not read `config.repo.packages`, so the aspect has no hidden `fleet-packages` dependency