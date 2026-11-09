# Spec Delta

## MODIFIED Requirements

### Requirement: Local flake references SHALL use the Git-tree form

Operator entrypoints that resolve this repository's own flake SHALL use the Git-tree form `.#`, which resolves tracked content only. The `path:` form SHALL NOT be used for local host evaluation because it copies the working directory verbatim and publishes untracked artifacts. Tracked source provenance SHALL remain available without stamping the commit ID into host outputs.

#### Scenario: An operator command evaluates the local configuration

- **WHEN** a deploy, dry-activate, prebuild or evaluation recipe resolves this repository's flake
- **THEN** it resolves the tracked configuration set
- **AND** the published `/etc/nixos-source` contains no untracked working-directory artifact

#### Scenario: The bootstrap projection is inspected

- **WHEN** `flake.bootstrap.nodes.<host>.flake` is read
- **THEN** it carries the Git-tree form for that host
- **AND** a reimage transfers tracked source rather than the working directory

#### Scenario: Revision provenance is available

- **WHEN** a host build is attributed to its source revision
- **THEN** CI build metadata records the commit
- **AND** `/etc/nixos-source` preserves the tracked source without stamping the commit into host outputs

#### Scenario: Equal trees cross a merge boundary

- **WHEN** two different commits contain identical tracked source trees
- **THEN** their host derivations and published source paths are identical
- **AND** this repository does not stamp either commit ID into `system.configurationRevision`
- **AND** commit attribution remains available in CI build metadata
