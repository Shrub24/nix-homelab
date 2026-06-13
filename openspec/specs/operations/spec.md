# Spec: Operations

## Purpose

Define the canonical operator workflows and command contracts for verification, deployment, observability, and break-glass recovery.
## Requirements
### Requirement: Contract verification gates operations

Phase contract checks SHALL exist and SHALL be used to detect configuration drift before deployment, including drift between public edge exposure policy and private-origin upstream policy.

#### Scenario: Ingress policy drift is introduced

- **WHEN** route exposure mode or domain mapping diverges from declared edge policy
- **THEN** verification fails prior to deployment

### Requirement: Deployment flows use canonical repository entrypoints

Day-2 deployment SHALL be performed through repository-defined operator entrypoints and host flake outputs.

#### Scenario: Host deployment is triggered

- **WHEN** an operator runs deploy/activate workflows
- **THEN** deployment targets declared host outputs and follows repository command contracts

#### Scenario: A deployment changes network ownership on a remote host

- **WHEN** activation would stop the currently active network stack or otherwise cut the in-band SSH transport
- **THEN** operators use a boot-time deploy workflow that updates the next generation without live-switching the running network stack
- **AND** the host reboot is performed with break-glass console access available

#### Scenario: A recovery baseline change is rolled out to a remote host

- **WHEN** operators deploy changes that affect rescue-user access or scheduled reboot behavior
- **THEN** the rollout includes an explicit verification step for the new recovery path
- **AND** rollback or prior-generation access remains available until verification completes

### Requirement: Operational status commands are available

The operator surface SHALL provide commands for host status, service logs, and ingress health checks that distinguish public edge reachability from private-origin upstream behavior.

#### Scenario: Ingress health is checked

- **WHEN** edge proxy changes are deployed
- **THEN** operators can verify Caddy edge status, certificate state, and effective route behavior for edge and upstream transport

### Requirement: Break-glass baseline and rollback paths are documented

Operators SHALL capture baseline state before risky changes and SHALL have documented rollback and recovery procedures, including offline rescue rebuilds for storage-related failures.

#### Scenario: Recovery is required

- **WHEN** SSH/Tailscale access degrades after change
- **THEN** break-glass steps and generation rollback commands are available to restore access
- **AND** the workflow includes offline rescue rebuild guidance for restoring `/nix`, mounting the ESP, and reinstalling a bootable generation when live recovery is no longer possible

#### Scenario: Recovery baseline is audited

- **WHEN** operators review host recovery readiness for a remote host
- **THEN** the documented runbook includes how to verify console rescue access, rescue-user access, scheduled reboot cadence, and rollback steps

### Requirement: Host recipient management is operationalized

Host key to age-recipient derivation SHALL be available via operator workflows with preview and update modes.

#### Scenario: A new host recipient is added

- **WHEN** operator derives host recipient material
- **THEN** recipient generation and optional policy update are performed via documented commands

### Requirement: Build/check workflows validate repo integrity

The operator surface SHALL include flake validation and host build checks.

#### Scenario: Pre-deploy validation runs

- **WHEN** operators run check/build commands
- **THEN** flake outputs and host build artifacts are validated prior to apply

### Requirement: Backup and restore workflows SHALL be documented as canonical operator runbooks

Operations documentation SHALL include canonical workflows for backup initialization, on-demand execution, recurring verification, restore preparation, and post-restore validation for host-scoped state backups.

#### Scenario: Operator prepares or audits backup operations

- **WHEN** an operator reviews the repository runbook surface for backups
- **THEN** the steps for initializing repositories, triggering backups, checking repository health, and validating restores are documented
- **AND** the runbook distinguishes routine backup execution from break-glass recovery flows

### Requirement: Backup validation SHALL include restore-oriented checks

The operator contract SHALL require validation beyond successful backup completion, including at least documented or executable checks that confirm critical backups are restorable.

#### Scenario: Backup validation is performed for a critical service

- **WHEN** operators validate backup health for identity or SQLite-backed services
- **THEN** validation includes restore-oriented verification steps rather than only timer/job success status

### Requirement: CI validation workflows SHALL be canonical for branch classes
Operations SHALL provide canonical CI validation behavior that distinguishes pull requests to `main`, pushes to non-`main`, and pushes to `main`.

#### Scenario: Validation-only branch class runs
- **WHEN** CI is triggered by a pull request to `main` or by a push to a non-`main` branch
- **THEN** validation workflows execute canonical repository checks
- **AND** no deployment steps are executed

#### Scenario: Host remote-build validation is scoped to high-signal triggers
- **WHEN** CI is triggered by routine pushes to non-`main` branches
- **THEN** lightweight validation checks MAY run without host toplevel remote-build jobs
- **AND** host toplevel remote-build validation runs on pull requests to `main` and on manual workflow dispatch triggers

#### Scenario: CI jobs use the canonical GitHub environment for secret-backed automation
- **WHEN** validation or deployment jobs need GitHub-hosted secrets or environment protection rules
- **THEN** those jobs are explicitly bound to the canonical GitHub Actions environment for this repository
- **AND** workflow secret consumption does not rely on repository-level secret scope when the environment-specific contract is intended

### Requirement: Main deployment workflow SHALL use canonical deploy entrypoints
Automated deployment on `main` SHALL execute repository-defined deployment entrypoints rather than custom out-of-band commands.

#### Scenario: Automated deployment is triggered
- **WHEN** CI/CD runs deployment for a push to `main`
- **THEN** host deployment uses canonical repository deploy contracts aligned with flake host outputs
- **AND** deployment automation does not bypass declared operator workflow boundaries

#### Scenario: Manual deployment can be dispatched from any branch
- **WHEN** an operator manually triggers the deploy workflow from a non-`main` branch via GitHub Actions `workflow_dispatch`
- **THEN** the workflow MAY run validation and deployment from that selected branch ref
- **AND** the workflow still uses the same canonical deploy entrypoints and explicit serial host ordering

#### Scenario: Deployment uses Tailscale SSH-first authentication
- **WHEN** GitHub Actions deploys to fleet hosts over the tailnet
- **THEN** workflow connectivity uses `tailscale/github-action`
- **AND** deployment auth relies on Tailscale SSH policy rather than a repository-stored deploy SSH private key
- **AND** deploy workflow secrets do not require a dedicated deploy SSH private key

#### Scenario: Deployment workflow stays portable across host changes
- **WHEN** operators add, remove, or reorder deploy targets
- **THEN** workflow structure keeps host-specific deploy logic in a reusable, low-duplication surface
- **AND** serial fail-fast ordering for active `main` deploy targets remains explicit

#### Scenario: Reusable deploy host workflow owns prebuild and deploy steps
- **WHEN** automated deployment runs for an active host target
- **THEN** the reusable host deployment workflow performs the host-specific remote prebuild and deploy steps together
- **AND** the top-level deploy orchestrator keeps only shared validation and explicit serial ordering logic

#### Scenario: deploy-rs SSH relaxations stay inline in workflow commands
- **WHEN** GitHub Actions deploys via `deploy-rs`
- **THEN** any temporary CI-specific SSH client relaxations are passed inline via deploy command options
- **AND** the workflow does not require generating a persistent SSH config file for those CI-specific options

#### Scenario: CI deploys can force host-side realization without changing local defaults
- **WHEN** GitHub Actions deployment should avoid acting as a middleman for store-path transfer
- **THEN** CI MAY pass an inline `deploy-rs` remote-build override for the target host deployment
- **AND** repository-local deploy topology defaults do not need to change for non-CI operator workflows
- **AND** the target host becomes the realization point that fetches directly from its configured substituters

### Requirement: CI SHALL validate OpenTofu posture without applying infrastructure
CI workflows SHALL include OpenTofu validation checks while leaving infrastructure apply as an explicit manual operator action.

#### Scenario: OpenTofu checks run in CI
- **WHEN** CI validation executes for any branch class
- **THEN** OpenTofu formatting and validation checks are run
- **AND** no automated OpenTofu apply is performed

#### Scenario: OpenTofu CI validation is intentionally deferred
- **WHEN** the repository does not yet have a usable CI credential and backend model for OpenTofu validation
- **THEN** CI MAY defer OpenTofu checks temporarily
- **AND** no automated OpenTofu apply is performed
- **AND** the workflow documentation MUST note that OpenTofu CI validation remains out of scope for the current change

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

