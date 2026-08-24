# Delta Spec: Host Recovery

## ADDED Requirements

### Requirement: Adopted-host invariants SHALL be reusable across preinstalled-NixOS hosts
Invariants and checks that apply to adopting a preinstalled NixOS host (verified host-key-to-age recipient derivation, provider-console recovery proof, non-destructive first-generation boot, and facter-based hardware capture) SHALL be extracted as reusable contract checks shared by adopted hosts rather than duplicated per host.

#### Scenario: A second preinstalled NixOS host is adopted
- **WHEN** a new adopted host is brought into the fleet
- **THEN** it reuses the shared adopted-host checks and runbook guidance
- **AND** per-host adoption files contain only host-specific facts

#### Scenario: An adopted host lacks a verified recovery path
- **WHEN** an adopted host's recovery checks are evaluated
- **THEN** the shared check set reports the missing provider-console or host-key verification step
- **AND** adoption cannot be declared complete while the check fails
