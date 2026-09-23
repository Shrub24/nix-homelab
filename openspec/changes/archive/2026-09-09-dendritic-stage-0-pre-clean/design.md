## Context

See `proposal.md` for motivation. The repository still constructs three hosts directly in `flake.nix`, passes `self`, `inputs`, and `ociImages` through `specialArgs`, and mixes reusable modules with host-owned composition. Recent work moved music to `home-forge`, introduced an Engine DJ input consumer, and left several completed, superseded, or operator-gated OpenSpec changes active.

Stage 0 must produce a trustworthy baseline without changing live hosts. It also records the already-agreed Stage 1 direction so cleanup does not optimize for the architecture being retired. Validation may include a minimal test-harness correction when an environmental lookup prevents the established aggregate from reaching its own explicit skip path.

## Goals / Non-Goals

**Goals:**

- **PC-1:** Remove only code and declarations proven unused or redundant.
- **PC-2:** Make current decisions and OpenSpec state accurately describe the repository.
- **PC-3:** Record a deterministic Stage 1 boundary for flake-parts, import-tree, host construction, and argument-bus removal.
- **PC-4:** Preserve host behavior and all security, deployment, and recovery boundaries.

**Non-Goals:**

- Introduce flake-parts, import-tree, flake-file, Den, or flake-aspects.
- Move hosts, convert service modules, or change feature selection.
- Change topology, web publication policy, OpenTofu, deployment ordering, secret recipients, or encrypted files.
- Remove OCI music-cutover residue before its soak is explicitly closed.
- Create `nix-fleet` or extract shared code in this change.

## Decisions

### PC-1 — Cleanup requires structural proof and evaluation

Delete a file or helper only when exhaustive repository search finds no active consumer. Remove a duplicate declaration only when its remaining module owner produces the same evaluated value. Documentation-only corrections must point to an accepted decision or current implementation.

This excludes speculative cleanup such as removing the OCI Litellm database role, changing Tailscale secret ownership, or repairing the notification composition gap. Those choices alter runtime policy or belong naturally to later aspect ownership work.

A validation-script correction is admissible only when it restores an already-designed explicit skip/failure branch and does not weaken a runtime gate. The Kanidm contract's optional 1.10 seed lookup qualifies: `pipefail` currently aborts before its explicit no-seed skip guard.

Alternative considered: resolve every known smell before scaffolding. Rejected because it mixes policy changes with equivalence preparation and makes regressions harder to attribute.

### PC-2 — OpenSpec reconciliation is fail-closed

Archive only a change whose tasks are complete and which passes strict validation. `normalize-music-storage-topology` is eligible for verification. Incomplete operator-gated changes remain active. `normalize-fleet-boundaries` remains active but is documented as superseded; unchecked tasks are not silently treated as complete.

Alternative considered: archive all superseded changes regardless of checkbox state. Rejected because it would falsify canonical completion state.

### PC-3 — Stage 1 architecture is fixed, implementation remains separate

The next change will:

- use flake-parts and `denful/import-tree`;
- publish aspects through `flake.modules.nixos.<aspect>`;
- construct all three hosts atomically through typed `nixos.configurations.<host>` records;
- move host composition to `modules/hosts/<host>/`;
- keep host-private/raw files excluded from auto-import;
- use an explicit temporary `import-tree.filterNot` boundary around unconverted lower-level module directories;
- remove every lower-level `self`, `inputs`, and `ociImages` consumer rather than introducing a compatibility `specialArgs` bridge;
- derive per-host checks on the host system so x86 evaluation does not force local aarch64 builds.

Existing plain NixOS leaves may remain behind that explicit boundary only while their features await conversion. Each later aspect conversion removes part of the boundary. `flake-file` is deferred until explicit input management becomes a demonstrated maintenance problem.

Alternative considered: move the entire current module tree under `_nixos`. Rejected because the path-only rewrite adds risk without validating host construction. A separate auto-import root was also rejected because it would institutionalize multiple discovery trees.

### PC-4 — `nix-fleet` is a future code-only library boundary

Record Tailscale, SSH, builder access, Nix defaults, selected shell defaults, notification dispatch, niks3 post-build/post-deploy integration, and Beszel agent support as candidates—not commitments. Code moves only after both repositories require materially identical behavior and the local aspect has passed equivalence checks.

Concrete topology, web-service policy, OpenTofu, deploy-rs metadata, secret readership, and encrypted values remain in `nix-homelab`. Cross-repository topology SSOT is a separate future decision.

Alternative considered: move shared topology while adopting aspects. Rejected because it combines code organization with authority and deployment-boundary changes.

### PC-5 — Equivalence is measured below repository provenance

Because `/etc/nixos-source` intentionally embeds `self.outPath`, any repository edit changes the host toplevel derivation even when runtime configuration is identical. Validation therefore combines:

1. host-scoped evaluation/checks for every host;
2. `nix-diff` or closure comparison with every difference classified;
3. explicit acceptance only for repository-source/provenance deltas caused by the change; and
4. targeted evaluation of options affected by removed declarations.

Any service, unit, package, firewall, secret, filesystem, user, boot, or deployment difference is a failure unless separately approved and moved into a behavioral change.

## Risks / Trade-offs

- **[Deletion was only apparently dead]** → Require exhaustive search plus host evaluation before checking off the deletion.
- **[Provenance noise conceals runtime drift]** → Classify derivation differences and compare affected evaluated option values directly.
- **[Temporary import-tree exclusions become permanent]** → Stage 1 must enumerate each exclusion and later aspect tasks remove them individually.
- **[Incomplete OpenSpec work is mistaken for obsolete work]** → Preserve unchecked tasks and archive only after strict validation.
- **[Shared-library ambition expands this migration]** → Record candidates only; require a separate cross-repository OpenSpec change.

## Migration Plan

1. Capture current consumers and host evaluation baselines.
2. Reconcile completed and superseded OpenSpec state without altering unfinished tasks.
3. Apply dead-code and redundant-definition cleanup one item at a time, validating the affected surface after each group.
4. Update decisions and the transition analysis with current facts and the settled Stage 1 boundary.
5. Run formatting, scoped checks, host evaluations, and strict OpenSpec validation.
6. Use the verified result as the parent baseline for `dendritic-stage-1-scaffold-hosts`.

Rollback is a normal JJ change rollback; no deployment or state migration occurs.
