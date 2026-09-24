# Spec Delta

## Purpose

Define how the homelab consumes the canonical fleet builder and CI contract: authenticated inbound build access, architecture-aware scheduling, signed cache publication, and deployment kept separate from builds.

## ADDED Requirements

### Requirement: FB-1 Builder identity and scheduling policy SHALL have one authority

Builder membership, architecture, host identity, SSH host keys and scheduling weights SHALL derive from nix-fleet's canonical inventory and `ci` profile. The default CI profile SHALL include home-forge, oci-melb-1 and la-admin-1, without opting into a metered external builder.

#### Scenario: Canonical profile is consumed
- **WHEN** the homelab's CI builder profile is rendered
- **THEN** x86_64 work is eligible for home-forge and la-admin-1 and aarch64 work for oci-melb-1
- **AND** LA retains the canonical lower scheduling weight and concurrency
- **AND** local policy does not duplicate host facts or profile members

### Requirement: FB-2 Selected builders SHALL authorize a dedicated build account

Each builder SHALL provide nix-fleet's dispatch account, authorize the canonical coordinator key, and include that account in `nix.settings.trusted-users` for ssh-ng. This is effectively root-level Nix authority despite no sudo. SSH/Tailscale admission SHALL remain limited to the coordinator key. Cache signature and publication policy SHALL remain unchanged.

#### Scenario: Coordinator dispatches a build
- **WHEN** the authorized coordinator contacts a selected builder
- **THEN** host-key verification succeeds against canonical trust and the trusted dispatch account can build through the remote Nix store
- **AND** success is demonstrated by an uncached build, not SSH login alone
- **AND** the evaluated `trusted-users` set contains the account name on all three builders

#### Scenario: Unauthorized client attempts access
- **WHEN** a client presents a key not authorized for the build account
- **THEN** it cannot use that account to dispatch work

### Requirement: FB-3 Distributed scheduling SHALL remain CI-scoped by default

CI SHALL consume the upstream profile's machines artifact. Adopting builder accounts and trust SHALL NOT enable host-daemon distributed scheduling; the hosts' `nix.buildMachines` SHALL remain empty unless a separate explicit change enables outbound offload.

#### Scenario: Builder host is evaluated
- **WHEN** a host selects the build account and builder trust aspects
- **THEN** it can receive authorized inbound build jobs
- **AND** its Nix daemon has no outbound remote build machines

#### Scenario: CI builds across architectures
- **WHEN** CI builds the fleet targets
- **THEN** its scheduling configuration comes from the canonical profile artifact
- **AND** jobs reach builders eligible for their declared systems

### Requirement: FB-4 CI SHALL use the version-matched upstream build and cache workflow

The caller SHALL invoke nix-fleet's reusable workflow at an immutable revision matching its flake dependency, and SHALL build the exact activatable deploy profiles of all three hosts after repository validation.

#### Scenario: Dependency is updated
- **WHEN** the nix-fleet revision changes
- **THEN** the reusable workflow reference is updated and checked against that revision's metadata and inputs
- **AND** the caller does not combine a newer flake contract with an older incompatible workflow tag

#### Scenario: Deployment profile is built
- **WHEN** CI builds a host's deploy profile
- **THEN** it builds the activatable wrapper the deploy tool consumes, not merely the NixOS toplevel
- **AND** the profile is reachable from the flake's standard check output rather than a bespoke aggregate

#### Scenario: Coordinator starts with a cold store
- **WHEN** the CI target set is evaluated where no previously built output is present
- **THEN** every host profile in it evaluates without depending on an unbuilt import-from-derivation result
- **AND** a gate that cannot build is not treated as the acceptance evidence for that target set

#### Scenario: Validation fails
- **WHEN** formatting, repository contracts or flake validation fail
- **THEN** dependent build/publication jobs do not run

### Requirement: FB-9 Coordinator architecture, target systems and builder profile SHALL be independent inputs

The caller SHALL select coordinator architecture, target systems and builder profile separately, and SHALL keep a non-empty canonical profile while both target architectures are selected. The build target input is a single selection, so the caller SHALL select one standard flake output that carries every host profile rather than enumerating per-host targets or inventing a custom aggregate.

#### Scenario: One coordinator builds both architectures
- **WHEN** a CI run selects the canonical profile and both target systems
- **THEN** foreign-architecture work is delegated to compatible builders rather than cross-compiled or expected from the coordinator
- **AND** the cached outputs cover each host's activatable deploy profile

#### Scenario: Local-only selection
- **WHEN** the caller empties the builder profile
- **THEN** remote builders and coordinator key setup are skipped
- **AND** the caller understands that foreign-architecture targets cannot fall back to the coordinator

### Requirement: FB-5 Privileged CI publication SHALL be confined to authorized runs

Pull requests SHALL run validation without fleet credentials or private builder access. Build/cache publication SHALL run after validation on main pushes and manual dispatches on main, with short-lived GitHub OIDC write authorization constrained by repository, owner, ref and reusable workflow identity. The caller SHALL forward only the coordinator SSH key required by the upstream build contract, not a long-lived cache token.

#### Scenario: Fork pull request is validated
- **WHEN** a fork pull request targets main
- **THEN** validation does not join the tailnet or receive builder/cache write credentials

#### Scenario: Branch dispatch is selected
- **WHEN** manual CI dispatch targets a non-main ref
- **THEN** privileged build/publication is not started
- **AND** the main-only cache claim policy is not widened

### Requirement: FB-6 Every build path SHALL publish substitutable outputs

Work realized by a fleet builder SHALL publish through that host's upload mechanism, and work the coordinator realizes locally SHALL publish through the coordinator's OIDC-authorized action hook. Acceptance SHALL demonstrate that uncached work on each architecture reached its intended execution path and that a clean consumer can obtain its signed outputs from the sovereign cache without rebuilding them.

#### Scenario: Remote builder produces an uncached output
- **WHEN** CI dispatches a new test derivation to a fleet builder
- **THEN** builder-side evidence names the output and upload result
- **AND** a clean consumer substitutes the same signed output with local and remote builds disabled

#### Scenario: Coordinator produces an uncached output
- **WHEN** the coordinator realizes a derivation in its own store, including a wrapper the remote builders did not build
- **THEN** that output is published through the action's authorized OIDC identity
- **AND** a clean consumer substitutes it without access to the runner's store

### Requirement: FB-7 Deployment SHALL remain manual and independently authorized

Build/cache publication SHALL NOT activate hosts. Manual deployment SHALL retain deploy-rs rollback protection, LA-before-OCI fail-fast ordering and independent operator/deployment authorization. Deployment workflows SHALL no longer require nixbuild.net prebuild credentials; they SHALL consume the exact cached deploy profile and fail rather than silently cold-build when operating in substitution-only mode.

#### Scenario: Main build completes
- **WHEN** CI publishes main's deploy profiles
- **THEN** no host activation occurs

#### Scenario: Operator starts ordered deployment
- **WHEN** manual fleet deployment is requested
- **THEN** LA is deployed before OCI and its failure prevents the OCI deployment
- **AND** build coordinator authorization is not treated as deployment authorization

### Requirement: FB-8 Shared substitutes SHALL follow the fleet baseline

Active hosts SHALL inherit their substituters and trusted cache keys from nix-fleet's shared baseline. Selecting builder trust or the dispatch account SHALL not independently rewrite that catalog or require cache-reader credentials.

#### Scenario: Host configuration is evaluated
- **WHEN** the three host configurations are inspected
- **THEN** their substitute catalog derives from the same upstream baseline
- **AND** builder access selection does not duplicate or change its provider ordering

## Constraints

No metered profile is selected implicitly, no automatic deployment is introduced, private keys remain outside source control, and cache signing and retention remain governed by `sovereign-binary-cache`. Existing `operations` formatting and `fleet-infrastructure` recovery/provenance requirements remain applicable.
