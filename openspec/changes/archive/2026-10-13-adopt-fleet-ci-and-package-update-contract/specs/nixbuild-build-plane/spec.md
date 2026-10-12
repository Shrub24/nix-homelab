# Spec Delta

## Purpose

Defines the canonical CI build plane and the substituter contract for fleet hosts and documented local consumers.

## RENAMED Requirements

- FROM: `### Requirement: CI builds SHALL use nixbuild.net as the primary remote build plane`
- TO: `### Requirement: CI builds SHALL use the fleet's own builders`

## MODIFIED Requirements

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
