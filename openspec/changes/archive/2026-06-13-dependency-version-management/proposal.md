## Why

Dependency ownership is currently split between flake inputs that Renovate can already update and a growing set of non-flake package sources and OCI image references that are still managed by hand. That makes version drift, hash churn, and container update hygiene harder to audit, especially as the fleet grows and more services depend on third-party artifacts.

This change establishes one clear dependency-management architecture now, while the repository is still small enough to migrate cleanly: Renovate owns flake inputs and OCI container references, and nvfetcher owns non-flake source version/hash generation for custom packages.

## What Changes

- Introduce a canonical dependency source architecture that separates ownership between Renovate-managed OCI/flake references and nvfetcher-managed non-flake source metadata.
- Add a centralized OCI image manifest so service modules consume canonical image references instead of repeating hardcoded image literals.
- Fully migrate existing OCI-backed service definitions to the centralized manifest.
- Define Renovate behavior for OCI updates in Nix, including tag updates and digest pinning from the initial rollout.
- Add nvfetcher-managed generated source outputs for non-flake package inputs, with committed generated metadata consumed by custom derivations.
- Add scheduled CI automation that refreshes nvfetcher outputs and opens or updates a pull request when generated sources change.
- Update repository and operational contracts so dependency automation, generated artifacts, and review workflows are documented as canonical.

## Capabilities

### New Capabilities
- `dependency-source-management`: Define the canonical ownership model, generated source layout, and consumption rules for flake inputs, OCI image references, and non-flake package sources.

### Modified Capabilities
- `repository-structure`: Add canonical locations for centralized OCI image metadata and nvfetcher-generated source artifacts so dependency SSOT placement is explicit.
- `operations`: Add canonical automation and operator workflow requirements for Renovate-managed OCI updates and scheduled nvfetcher source-refresh PRs.

## Impact

- **Repository layout**: new canonical dependency metadata surfaces for OCI image references and nvfetcher-generated non-flake sources.
- **Service modules**: OCI-backed modules will stop owning hardcoded image strings directly and will instead consume centralized references.
- **Package infrastructure**: custom derivations will gain a generated source input path for nvfetcher-managed versions and hashes.
- **Automation**: `renovate.json`, CI workflows, and supporting scripts/commands will change to support the new ownership model.
- **Documentation and review flow**: operator docs and OpenSpec contracts will need to describe the new dependency refresh and PR workflow.
