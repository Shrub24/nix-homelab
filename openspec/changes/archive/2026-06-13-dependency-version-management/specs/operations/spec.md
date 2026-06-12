## ADDED Requirements

### Requirement: Dependency refresh automation SHALL follow canonical tool boundaries
Operational automation SHALL preserve the canonical boundary where Renovate manages flake-input and OCI-reference updates, and scheduled nvfetcher automation manages non-flake generated source refreshes.

#### Scenario: Dependency automation responsibilities are audited
- **WHEN** operators review automated update workflows
- **THEN** Renovate is configured to update flake inputs and OCI references only
- **AND** nvfetcher refresh automation is configured to update non-flake generated source metadata only
- **AND** the workflows do not compete to update the same dependency class

### Requirement: Scheduled generated-source refreshes SHALL use canonical CI review flow
Scheduled CI refreshes for nvfetcher-managed sources SHALL run through the canonical GitHub workflow surface and SHALL present changes as reviewable pull requests.

#### Scenario: Scheduled source refresh runs in CI
- **WHEN** the scheduled generated-source workflow detects nvfetcher output changes
- **THEN** the workflow commits the regenerated outputs on an automation branch or equivalent PR flow
- **AND** opens or updates a pull request for operator review
- **AND** does not bypass branch review by applying the changes directly to `main`

### Requirement: Operators SHALL have one documented workflow per dependency class
Operations documentation and commands SHALL distinguish the canonical update path for flake inputs, OCI image refs, and nvfetcher-managed non-flake sources.

#### Scenario: Operator needs to refresh a dependency manually
- **WHEN** an operator follows repository runbooks or commands to refresh a dependency
- **THEN** the workflow makes clear whether the dependency is expected to move through Renovate or nvfetcher automation
- **AND** the operator does not need to infer ownership from implementation details scattered across the repo
