# Delta Spec: Operations

## ADDED Requirements

### Requirement: Deployment and CI ordering SHALL consume physical topology metadata or declare explicit mismatch checks
Routine deployment and CI ordering SHALL derive from the canonical physical deployment metadata (`lib/deploy/hosts.nix`) where the platform can evaluate it, and where workflow auditability requires explicit jobs, the workflow SHALL include a check that its job names and order match the canonical metadata.

#### Scenario: Deploy order changes in topology metadata
- **WHEN** `deployOrder` in physical topology metadata is reordered
- **THEN** deployment tooling and CI order reflect the new order without editing duplicated literals
- **AND** any explicit CI job list fails its mismatch check if it diverges from the metadata

#### Scenario: A workflow cannot evaluate the flake
- **WHEN** a workflow platform cannot consume the Nix topology source directly
- **THEN** it SHALL maintain an explicit mismatch check against the canonical metadata instead of an unverified literal copy
- **AND** the check runs on every relevant workflow invocation
