# nixbuild-build-plane Specification

## Purpose
Defines nixbuild.net as the canonical CI remote build plane and shared substituter contract for fleet hosts and documented local consumers.
## Requirements
### Requirement: CI builds SHALL use nixbuild.net as the primary remote build plane
Repository CI workflows SHALL execute build-heavy Nix validation through `nixbuild.net` rather than depending on GitHub-hosted multi-architecture runners.

#### Scenario: Pull request validation runs
- **WHEN** a pull request targeting `main` triggers CI
- **THEN** Nix validation workflows use `nixbuild.net` as the configured remote build plane
- **AND** CI does not require a dedicated multi-architecture runner matrix to build host outputs

### Requirement: Shared substituter contract SHALL be available for active hosts
Active hosts SHALL support a common substituter/trust baseline that prioritizes `nixbuild.net` as the first substituter and the sovereign S3-backed binary cache as the durable secondary tier, with `cache.nixos.org` as the upstream fallback.

#### Scenario: Host build configuration is evaluated
- **WHEN** `nixosConfigurations.la-admin-1` and `nixosConfigurations.oci-melb-1` are evaluated
- **THEN** both include `ssh://eu.nixbuild.net` as the first substituter
- **AND** both include the sovereign S3 cache as the second substituter
- **AND** both include `https://cache.nixos.org` as the upstream fallback
- **AND** host composition remains module-driven rather than ad hoc host-inline Nix settings

#### Scenario: Sovereign cache is unavailable
- **WHEN** the sovereign S3 cache is unreachable during Nix evaluation or build
- **THEN** Nix falls through to `cache.nixos.org` as the next configured substituter
- **AND** host evaluation does not fail solely due to sovereign cache unavailability

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

