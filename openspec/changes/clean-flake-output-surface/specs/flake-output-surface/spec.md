# Spec Delta

## Purpose

Define the repository's flake output surface: which attributes are published, what
each one holds, and the rule that makes an output a deliberate decision rather
than an accident of a module's defaults.

## ADDED Requirements

### Requirement: The published output set is explicit

The flake SHALL publish only attributes named by a module. A default-deny
allowlist SHALL be the single place that grants publication, so an attribute a
module happens to define does not become part of the interface.

#### Scenario: flake-parts defaults are not published
- **WHEN** the flake is evaluated after this change
- **THEN** `nixosModules`, `overlays` and `legacyPackages.<system>` are absent
  from its outputs
- **AND** `nix flake show` lists only the allowlisted attributes

#### Scenario: an unnamed output does not leak
- **WHEN** a module defines a flake output that the allowlist does not name
- **THEN** that attribute does not appear in the flake's outputs
- **AND** publishing it requires an explicit allowlist entry

### Requirement: Canonical host facts are published once, per host

Every fact about a host SHALL be reachable from one per-host key,
`fleet.hosts.<id>`. The deploy facts and, where the host has reimage metadata, its
`bootstrap` slice SHALL live there together. Fleet-level topology — the edge host
and the deploy order — SHALL live beside `hosts`, not inside a host.

#### Scenario: a reimaged host exposes both slices
- **WHEN** a host's record declares bootstrap metadata
- **THEN** `fleet.hosts.<id>` carries its deploy facts and a `bootstrap` attribute
- **AND** the bootstrap values are those the host record declares

#### Scenario: an adopted host exposes no bootstrap slice
- **WHEN** a host has no reimage metadata
- **THEN** `fleet.hosts.<id>` carries no `bootstrap` attribute
- **AND** deploying that host does not require one

#### Scenario: fleet-level topology is not per-host
- **WHEN** a consumer needs the edge host or the deploy order
- **THEN** it reads `fleet.edgeHost` or `fleet.deployOrder`
- **AND** no host record is required to answer it

### Requirement: `deploy` remains deploy-rs' schema

The `deploy` output SHALL contain only what deploy-rs and its checks read.
Repository metadata SHALL NOT be added to it, and it SHALL NOT be renamed.

#### Scenario: deploy-rs reads its own schema
- **WHEN** `nix run .#deploy-rs` or the deploy checks evaluate `deploy`
- **THEN** they find the unchanged deploy-rs node schema
- **AND** repository topology comes from `fleet` instead

### Requirement: A hidden output has no reader

An attribute SHALL be hidden only when nothing reads it: not this repository's
scripts, workflows and tests, and not an upstream contract or reusable workflow
that consumes this flake by name.

#### Scenario: a workflow-read output stays published
- **WHEN** an inherited package output is read by name by a CI workflow
- **THEN** it remains published
- **AND** hiding it would be recorded as a breaking interface change

#### Scenario: an unconsumed inherited output is hidden
- **WHEN** an inherited package output has no consumer in this repository and
  none in the upstream contract it came from
- **THEN** it may be removed from the published set
- **AND** the removal stays a single allowlist edit, so it is reversible

### Requirement: Consumers of a renamed output change in the same delivery

A rename SHALL NOT land with a consumer still reading the old path. Scripts,
workflows, tests and documentation that resolve an output SHALL be updated
together, and the change SHALL be verified by the contract suites that already
read those paths.

#### Scenario: a shell script fails closed rather than silently
- **WHEN** a script resolves a renamed output that no longer exists
- **THEN** it exits non-zero with a message naming the missing attribute
- **AND** it does not proceed with an empty value

#### Scenario: the contract suite guards the new shape
- **WHEN** the scaffold contract runs after the change
- **THEN** it asserts the allowlisted output list and the `fleet` shape
- **AND** a future rename fails the check rather than a deployment
