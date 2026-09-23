## MODIFIED Requirements

### Requirement: Leaf services SHALL own secret and runtime contracts
Leaf service modules SHALL own semantic secret registration, template assembly, runtime wiring, assertions, and restart semantics, and SHALL accept explicit contract inputs such as `secretFiles.*` and `secretKeys.*` instead of requiring callers to mutate raw internal `sops.secrets` definitions.

#### Scenario: Application supplies secrets to a leaf
- **WHEN** an application composes a leaf service that needs secrets
- **THEN** it provides explicit contract inputs to the leaf
- **AND** the leaf remains responsible for the actual `sops.secrets` / `sops.templates` registration and runtime consumption

#### Scenario: Host overrides a secret source
- **WHEN** a host needs to bind a host-specific secret source for an enabled feature
- **THEN** it does so through the exposed contract surface
- **AND** the host does not need to know or mutate the leaf’s internal secret registration names

#### Scenario: Traktor leaf is removed
- **WHEN** home-forge evaluates the Navidrome playlist-sync worker
- **THEN** it imports the upstream worker module and configures only its M3U import / engine export option surface
- **AND** no repository-owned Traktor leaf, NML option, or Traktor collection state is restored

#### Scenario: Application passes resolved OIDC env-file handoff to a leaf
- **WHEN** a composed leaf service owns an OIDC template but expects a resolved env-file path input for runtime wiring
- **THEN** the application composition layer passes the resolved `sops.templates.*.path` through the leaf's explicit contract surface
- **AND** hosts do not own or duplicate that OIDC env-file wiring

#### Scenario: Leaf secret contract cleanup is reviewed after regression fixes
- **WHEN** a leaf service is revisited after the topology migration to close a regression or cleanup pass
- **THEN** it continues to use the canonical helper-based secret contract surface where that pattern is already established in the repo
- **AND** hosts only bind explicit contract inputs rather than reviving ad hoc secret-file wiring shapes
