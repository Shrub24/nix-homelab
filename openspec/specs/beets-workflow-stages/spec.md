# beets-workflow-stages Specification

## Purpose
TBD - created by archiving change refactor-beets-automated-workflow. Update Purpose after archive.
## Requirements
### Requirement: Stage-specific Beets workflows MUST be explicitly defined
The system SHALL define distinct Beets processing stages with explicit behavior contracts for inbox automation, quarantine manual review, approved promotion, and reconcile/convert maintenance.

#### Scenario: Stage contracts are rendered
- **WHEN** Beets runners/configs are generated
- **THEN** each stage has explicit invocation path and behavior semantics

### Requirement: Stage instantiation MUST be application-owned
The system SHALL keep concrete Beets stage instantiation under the music application layer rather than embedding it as fixed behavior in the generic Beets service framework.

#### Scenario: Stage runners are declared
- **WHEN** the music application composes Beets workflow stages
- **THEN** it declares which runner instances exist, which configs they use, and which timers or manual invocation paths apply
- **AND** Beets config assets are owned under `modules/services/music/beets/files/`

### Requirement: Beets service structure MUST stay internally cohesive
The system SHALL keep reusable Beets service implementation under a dedicated `modules/services/beets/` folder rather than scattering Beets framework files across the broader services directory.

#### Scenario: Service framework files are organized
- **WHEN** reusable Beets service code is introduced or refactored
- **THEN** it lives under `modules/services/beets/` with clear internal module boundaries

### Requirement: Quarantine review MUST support interactive SSH TTY operation
The system SHALL provide a manual quarantine/untagged workflow that runs interactively over SSH TTY without headless/quiet import flags.

#### Scenario: Operator runs quarantine review
- **WHEN** operator invokes the quarantine interactive runner on a quarantine path
- **THEN** Beets prompts are presented interactively for manual import decisions

### Requirement: Inbox stage MUST remain headless and deterministic
The automated inbox workflow SHALL run non-interactively with deterministic duplicate handling suitable for unattended execution.

#### Scenario: Inbox automation processes duplicate candidates
- **WHEN** duplicate candidates are encountered during automated inbox import
- **THEN** configured non-interactive duplicate policy is applied without user prompts

