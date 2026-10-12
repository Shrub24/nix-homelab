# nixbuild-build-plane Specification

## Purpose
Defines the fleet's CI build plane and the shared substituter contract for fleet hosts and documented local consumers: repository CI builds through the fleet's own builders, reached by nix-fleet's reusable workflow and its rendered builder profile, routine validation builds no fleet output, and hosts substitute from nix-fleet's shared baseline plus the fleet's own sovereign cache. (The capability keeps its historical file name.)

## Requirements

### Requirement: CI builds SHALL use the fleet's own builders

Repository CI SHALL build through the fleet's own builders, reached by nix-fleet's reusable build-push-cache workflow and its rendered `ci` builder profile, rather than through a third-party build service or a GitHub-hosted multi-architecture runner matrix. Routine push and pull-request validation SHALL evaluate rather than build fleet outputs; building checks SHALL run only from the separate, manually dispatched build path, which is registered on `main` alone.

#### Scenario: Pull request validation runs

- **WHEN** a pull request targeting `main` triggers CI
- **THEN** validation runs the repository's formatting and evaluation gates
- **AND** it builds no fleet output
- **AND** the fleet build is reachable only through the separate manual dispatch

#### Scenario: The build path is dispatched

- **WHEN** an operator dispatches the fleet build on `main`
- **THEN** the run reaches the fleet's builders through the rendered `ci` profile, with no builder coordinates in the workflow

### Requirement: Shared substituter contract SHALL be available for active hosts

Active hosts SHALL support a common substituter baseline derived from nix-fleet's shared baseline: `cache.nixos.org` for upstream packages, the community caches, and the fleet's own sovereign niks3 cache where CI and hosts publish. nix-fleet's default `ssh-ng://eu.nixbuild.net` entry MAY remain in `trusted-substituters` but SHALL NOT appear in `substituters`, because nothing in this fleet consumes it.

#### Scenario: Host build configuration is evaluated

- **WHEN** a fleet host's configuration is evaluated
- **THEN** its `substituters` resolves to the nix-fleet baseline: `cache.nixos.org`, the community caches, and the fleet's own sovereign cache
- **AND** nix-fleet's `ssh-ng://eu.nixbuild.net` default, if present at all, appears only in `trusted-substituters`
- **AND** host composition remains module-driven rather than host-inline

#### Scenario: Sovereign cache is unavailable

- **WHEN** the sovereign cache is unreachable during Nix evaluation or build
- **THEN** Nix falls through to `cache.nixos.org` as the next configured substituter
- **AND** host evaluation does not fail solely because the sovereign cache is unavailable

### Requirement: Host-side build mode SHALL remain substituter-only in phase 1
Phase-1 host participation in `nixbuild.net` SHALL be limited to substitute consumption and SHALL NOT require host-side remote build offload.

#### Scenario: Host deploy topology is reviewed
- **WHEN** deploy/build wiring is inspected after phase-1 rollout
- **THEN** hosts consume substitutes from `nixbuild.net`
- **AND** existing host-side build topology for deploy-rs is preserved unless an explicit follow-up change introduces offload

### Requirement: Main branch deployment automation SHALL be serial fail-fast
Pushes to `main` SHALL trigger validation and then host deployment in deterministic serial order with fail-fast behavior.

#### Scenario: Main merge deployment is executed
- **WHEN** CI/CD runs on push to `main`
- **THEN** deployment runs `la-admin-1` before `oci-melb-1`
- **AND** failure on the first host stops further deployment for that run

### Requirement: Builder SSH trust SHALL be owned by the builder-access aspect
nixbuild.net SSH trust and host configuration SHALL be owned by the builder-access aspect that hosts select explicitly, while substituter policy SHALL remain in the base aspect.

#### Scenario: Host selects the builder-access aspect
- **WHEN** a host selects the builder-access aspect
- **THEN** the nixbuild.net SSH known-hosts and host configuration are provided by the aspect
- **AND** the host assembly does not repeat the nixbuild SSH leaf import or enablement

#### Scenario: Substituter policy remains base-owned
- **WHEN** a host's substituter configuration is inspected
- **THEN** the nixbuild.net substituter priority and trust remain in the base aspect, unchanged by the builder-access aspect
- **AND** selecting builder-access does not alter the shared substituter/trust baseline
