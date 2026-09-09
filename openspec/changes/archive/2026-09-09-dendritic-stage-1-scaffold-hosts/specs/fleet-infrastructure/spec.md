## MODIFIED Requirements

### Requirement: Host composition is host-centric and modular
The repository SHALL construct fleet hosts from typed `nixos.configurations.<host>` records and SHALL organize host identity separately from reusable aspects and modules so hosts can select feature stacks explicitly without owning service implementation.

#### Scenario: A host is composed from shared modules
- **WHEN** a host configuration is declared under `modules/hosts/<host>/`
- **THEN** a typed registry entry declares its system and explicit composition
- **AND** the flake materializes the same `nixosConfigurations.<host>` output expected by operator and CI workflows
- **AND** the host composes reusable aspects or modules rather than embedding provider or service logic inline
- **AND** workload selection remains explicit rather than arising from accidental import-tree discovery

#### Scenario: Edge role is assigned to one host
- **WHEN** only one host is configured as ingress edge
- **THEN** other hosts can remain private-origin nodes with shared composition patterns

### Requirement: First-host bootstrap is declarative and repeatable
The first host SHALL be bootstrappable from repository state using `nixos-anywhere` and `disko`, and rebuildable from flake outputs whose host metadata is derived from the typed configuration registry.

#### Scenario: Host bootstrap workflow is executed
- **WHEN** operators run bootstrap or deploy workflows
- **THEN** installation and post-install rebuilds derive from declarative flake/module state
- **AND** existing host names and bootstrap-facing flake outputs remain compatible

### Requirement: Fleet package baseline defaults to unstable
Fleet host outputs SHALL consume the primary repository package baseline from `nixos-unstable` unless an explicit documented exception is introduced, independent of the system evaluating the flake.

#### Scenario: Active host outputs are evaluated
- **WHEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` are evaluated
- **THEN** each host resolves packages for its declared target system from the primary unstable baseline input
- **AND** per-host checks do not force an evaluator to build another architecture locally
