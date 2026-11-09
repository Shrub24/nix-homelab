# Spec Delta

## MODIFIED Requirements

### Requirement: CI builds SHALL use the fleet's own builders

Nixbot on home-forge SHALL be nix-homelab's CI coordinator, evaluating and building admitted checks on the fleet's canonical x86 and ARM capacity. All validation SHALL live in checks; nixbot/nix-eval and nixbot/nix-build SHALL be the App-sourced required verdict after observed cutover. Equal source trees SHALL yield reusable host outputs across PR/main revisions. GitHub SHALL own merging. Actions SHALL retain the scheduled update producer and existing deployment tooling, not a parallel CI/candidate build plane.

#### Scenario: Pull request validation runs

- **WHEN** an admitted PR targeting main arrives
- **THEN** nixbot evaluates and builds complete checks for both architectures and publishes outputs
- **AND** no Actions contract/build pipeline provides a second verdict after cutover

#### Scenario: The build path is dispatched

- **WHEN** nixbot schedules an admitted build
- **THEN** it derives builder capacity and verified SSH trust from the canonical ci profile
- **AND** it uses a separate coordinator identity rather than the Actions builder key

#### Scenario: Main receives an already-built tree

- **WHEN** GitHub merges an up-to-date PR with the same tree
- **THEN** commit identity alone does not change host derivations
- **AND** the observed main run reuses the build while running cache reconciliation
