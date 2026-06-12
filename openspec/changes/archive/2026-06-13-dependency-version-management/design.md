## Context

The repository already has two different dependency-management realities: Renovate updates flake inputs and GitHub Actions, while OCI image references and non-flake package sources still live as manual literals spread across service modules and package definitions. That makes ownership unclear, creates review noise in unrelated files, and leaves no canonical refresh path for source hashes that Nix derivations depend on.

This change is cross-cutting because it touches repository structure, service module defaults, package-source plumbing, and CI automation. It also needs a stable contract before implementation because the chosen layout will become the dependency source-of-truth pattern for future hosts and services.

Constraints that matter here:
- The repository should stay easy to navigate and low-complexity for a small homelab fleet.
- OCI image references should remain simple to consume from NixOS modules.
- Generated artifacts may be committed, but ownership boundaries must stay obvious.
- Automation should create reviewable PRs rather than mutating `main` directly.
- Multi-host growth means dependency metadata must live in reusable repo-level surfaces, not host-local files.

## Goals / Non-Goals

**Goals:**
- Establish one explicit ownership split: Renovate for flake inputs and OCI image refs; nvfetcher for non-flake package sources.
- Centralize OCI image metadata in one canonical manifest and fully migrate existing service modules to consume it.
- Adopt digest-pinned OCI references from the first rollout so remote image pulls are reproducible.
- Introduce a conventional committed nvfetcher output layout for version/hash-driven package sources.
- Add a scheduled CI workflow that refreshes nvfetcher outputs and opens or updates a PR when generated files change.
- Keep the resulting architecture understandable enough that adding a new image or non-flake source is routine.

**Non-Goals:**
- Replacing Renovate for flake input management.
- Using nvfetcher to manage OCI container tags or OCI pull strings.
- Introducing a new deployment orchestrator or changing host deployment topology.
- Refactoring unrelated service options beyond the dependency-source migration needed to consume the new manifest.
- Solving every possible third-party ecosystem update problem beyond flake inputs, OCI images, and current non-flake derivation sources.

## Decisions

### Decision DVM-1: Split ownership by dependency type

**Chosen:**
- Renovate owns `flake.lock`/flake inputs and OCI image references.
- nvfetcher owns non-flake upstream package sources and their generated version/hash metadata.

**Rationale:** Renovate is strongest when it can update human-authored dependency references in place and open reviewable PRs with upstream changelog context. nvfetcher is strongest when Nix needs generated version/hash/source metadata for custom derivations. Splitting by dependency type avoids overlapping automation and keeps each source of truth unambiguous.

**Alternative considered:** Let nvfetcher own OCI and non-flake sources together. Rejected because OCI image refs already fit Renovate's PR/update model better, and dual ownership of OCI versions plus generated OCI metadata would increase cognitive overhead.

### Decision DVM-2: Centralize OCI refs in a repo-level manifest

**Chosen:** Move canonical OCI image references into a dedicated repo-level manifest consumed by service modules.

**Rationale:** The current scattered `image = "...";` defaults make updates hard to inventory and hard to review. A central manifest gives one place for Renovate targeting, one place for digest-pinning policy, and one place to audit third-party container use across the fleet.

**Alternative considered:** Leave image strings inline in each module and use Renovate regex managers across all service files. Rejected because it keeps ownership diffuse and makes future auditing and bulk migrations harder.

### Decision DVM-3: Use tag-plus-digest OCI references from the initial rollout

**Chosen:** Canonical OCI references will be stored in `image:tag@sha256:...` form and managed by Renovate from the start.

**Rationale:** This repo values reproducibility and recoverability. Digest-pinned image refs reduce ambiguity during rebuilds and make drift easier to reason about when remote registries mutate tags or publish re-tagged images.

**Alternative considered:** Start with tags only and add digests later. Rejected because the migration already touches every OCI reference, so delaying digests would create a second churn window later.

### Decision DVM-4: Use conventional committed nvfetcher `_sources` outputs

**Chosen:** nvfetcher will generate committed source metadata in a conventional `_sources`-style layout that package code can import directly.

**Rationale:** Conventional layout reduces surprise, aligns with common Nix packaging patterns, and makes future package additions easier. Committing the outputs keeps CI and developer environments aligned and allows reviews to inspect version/hash changes directly.

**Alternative considered:** A custom repo-specific generated layout. Rejected because it adds local convention without clear benefit.

### Decision DVM-5: nvfetcher automation runs as scheduled CI that opens PRs

**Chosen:** GitHub Actions will run nvfetcher on a schedule, regenerate committed outputs, and open or update a pull request when changes are detected.

**Rationale:** PR-based automation preserves reviewability, fits the existing GitHub workflow, and keeps generated-source refreshes off the critical path for manual operators. It also mirrors Renovate's review model without requiring direct pushes to `main`.

**Alternative considered:** Manual-only nvfetcher refreshes. Rejected because hash/version drift would accumulate and the workflow would rely on human memory.

### Decision DVM-6: Service modules consume projections, not raw dependency literals

**Chosen:** Service modules and custom derivations will consume dependency projections from canonical manifests/generated sources rather than redefining raw upstream literals.

**Rationale:** This is consistent with the repository's existing SSOT direction: policy/config locations own metadata, and downstream modules consume resolved projections. It lowers duplication and makes dependency ownership inspectable.

**Alternative considered:** Allow ad-hoc exceptions for module-local literals. Rejected for the baseline because it reintroduces drift immediately.

## Risks / Trade-offs

- **Manifest migration churn** → Full OCI migration will touch many service modules in one change; mitigate by centralizing with mechanical edits and validating every affected module path.
- **Digest-pin noise** → Initial Renovate pinning may create large diff lines; mitigate by centralizing refs so the noise stays in one manifest instead of many modules.
- **Generated file review fatigue** → nvfetcher PRs may produce machine-generated diffs; mitigate by keeping `_sources` layout conventional and scoping nvfetcher strictly to non-flake sources.
- **CI credential or rate-limit failures** → Scheduled nvfetcher refreshes may need registry/API credentials for some sources; mitigate by designing the workflow around explicit secrets and clear failure visibility.
- **Over-centralization concerns** → A central OCI manifest adds one extra lookup hop for operators; mitigate by keeping names service-aligned and colocating documentation with repository structure contracts.

## Migration Plan

1. Introduce the canonical OCI manifest and wire Renovate to manage its refs, including digest pinning.
2. Migrate all existing OCI-backed modules to consume the manifest instead of hardcoded image literals.
3. Introduce nvfetcher config plus committed `_sources` outputs for current non-flake package sources.
4. Update affected package code to consume generated nvfetcher metadata.
5. Add scheduled CI workflow and PR automation for nvfetcher refreshes.
6. Validate formatting/check flows and confirm operators have one documented path for each dependency class.

**Rollback strategy:**
- OCI migration can be reverted by restoring prior module-local image literals and removing the centralized manifest.
- nvfetcher rollout can be reverted by removing generated source consumption and restoring manually pinned source definitions.
- CI automation can be disabled independently without changing the dependency ownership model.

## Open Questions

- Which existing non-flake package definitions should be migrated in this first change versus merely prepared for future nvfetcher adoption?
- Should Renovate grouping policy keep all OCI manifest updates together, or split by service criticality/registry to reduce PR blast radius?
- Does any targeted registry require credentials or throttling exceptions for digest refresh behavior in CI?
