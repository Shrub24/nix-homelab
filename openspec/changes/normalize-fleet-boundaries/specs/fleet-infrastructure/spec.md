# Delta Spec: Fleet Infrastructure

## ADDED Requirements

### Requirement: Physical topology metadata SHALL be single-sourced and consistency-checked
Physical host metadata (host identity, system architecture, deploy order, edge designation) SHALL have one canonical source for scripts, tests, and deployment sequencing, and repository/CI consumers SHALL either consume that source or maintain an explicit consistency check against it.

#### Scenario: A nixosConfiguration is added without deploy metadata
- **WHEN** a new `nixosConfigurations.<host>` output is introduced
- **THEN** evaluation or a contract check SHALL fail until the host appears in the physical topology metadata or is explicitly marked as non-deployable
- **AND** the mismatch is reported rather than silently ignored

#### Scenario: Deploy nodes and nixosConfigurations drift apart
- **WHEN** a deploy-rs node references a host absent from `nixosConfigurations` or vice versa
- **THEN** a consistency check fails and names the missing side
- **AND** the check runs as part of repository validation

#### Scenario: CI host lists are audited for topology drift
- **WHEN** CI deploy workflows are reviewed
- **THEN** each physical host job either consumes the canonical topology metadata or is verified by an explicit mismatch check against it
- **AND** duplicated literal host lists in workflows and docs are removed or tied to the canonical source
