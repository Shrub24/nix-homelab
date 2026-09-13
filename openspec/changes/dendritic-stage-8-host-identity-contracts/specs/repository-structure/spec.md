## ADDED Requirements

### Requirement: Host sources SHALL participate in recursive Dendritic discovery

Host contributors SHALL live in the normal recursive discovery tree and host-private NixOS fragments SHALL remain explicitly private. The temporary import-tree exclusion SHALL no longer contain `hosts` after all host contributors are converted.

#### Scenario: Host discovery conversion completes

- **WHEN** all active hosts register their own typed records through discovered contributors
- **THEN** the central registry contains generic schema and materialization only
- **AND** `hosts` is removed from the temporary exclusion boundary
- **AND** only the unconverted `services` root remains excluded
- **AND** existing `nixosConfigurations`, bootstrap, and deploy outputs retain their names

### Requirement: Flake source directory SHALL contain flake materialization concerns

`modules/flake/` SHALL be reserved for contributors whose primary responsibility is flake output materialization, registry schema, packages, development shells, deployment outputs, or equivalent flake-level infrastructure. Feature aspects SHALL move to semantic domain paths as their ownership is settled.

#### Scenario: Repository layout is reviewed after Stage 8

- **WHEN** contributors are inspected
- **THEN** host and touched feature contributors are navigable by semantic domain
- **AND** recursive discovery treats them as top-level flake-parts contributors
- **AND** no flat-directory requirement or class-oriented replacement root is introduced
