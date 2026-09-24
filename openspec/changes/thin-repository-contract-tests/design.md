# Design

## Context

See `proposal.md` for motivation and scope. The local battery in `.just/checks.just` invokes both focused contracts and broad scaffold/identity suites. The latter contain repeated host/aspect inventories, exact source-line assertions, and copied-tree mutations used to prove the source scanners work. Some mutations also establish real capability independence and must survive.

The repository's production boundary is its evaluated flake outputs and rendered NixOS configuration. Executable helpers provide a second boundary for restore, backup, bootstrap, and secret-management outcomes. Canonical host records already validate identity, aspect selection, and materialization; tests should not duplicate those mechanisms by checking indentation or import spelling.

## Goals / Non-Goals

**Goals:** reduce coupling to implementation text while retaining current observable contracts; give each retained invariant one test owner; make the regular battery stop reporting completed migration work as pending.

**Non-Goals:** no wholesale testing framework, runtime feature changes, dependency re-testing, new end-to-end service matrix, spec synchronization of unrelated historical architecture, or resolution of the separate recipient/privacy coverage defects.

## Decisions

### TT-1: Delete source-restatement checks rather than replace their scanner

Remove assertions over code text for exact imports, option assignments, literal descriptions, inventory lists, removed names, and rendering implementation. Also remove cases that solely mutate code to demonstrate those text predicates detect a change. Switching grep to Python, AST matching, or another parser would preserve the same weak oracle and is rejected.

Directory existence, Git tracking, and committed generated-artifact freshness are different: their artifacts are the contract itself. Keep these checks where a current consumer exists. Grep over process diagnostics is also valid when it distinguishes the intended rejection from an unrelated failure.

### TT-2: Keep one evaluated boundary for placement and composition

Preserve evaluated relationships among host identity, selected capabilities, provider/client endpoints, runtime units, and secret registrations. Drop repeated complete inventories from the identity and LA suites where the scaffold or a focused contract already owns them. Keep meaningful deselection cases that demonstrate provider-only or contract-only evaluation, but remove mutations proving only a deleted spelling predicate.

Use existing module evaluation/probes rather than a new copied implementation table. Preserve all three fleet hosts where the contract is fleet-wide. Existing schema rejection is sufficient for facts the registry itself already asserts; do not add a mutation for every spelling of invalid state.

### TT-3: Exercise restore behaviour without parsing Nix source

Keep stopped-service, invalid-artifact, verifier-failure, contradictory-success, ownership-gating, and cleanup-failure cases. Resolve the restore helper from evaluated unit wiring and execute that production script with temporary paths and stubs at external command boundaries. Do not reconstruct the script by regex-extracting a `writeShellScript` block and replacing Nix expressions. Prefer evaluation overrides for scratch paths and command dependencies where the existing module seam permits them; if executing the evaluated helper cannot be done faithfully without production changes, stop and surface that narrow blocker rather than keep a fake rendering or silently remove recovery coverage.

Delete the old real-binary migration branch, including the store search for a 1.10 seed and its skip output. The archived upgrade already records acceptance; routinely rebuilding that migration does not protect a new consumer. The separate real-binary review obligation for future restore-helper changes remains intact.

### TT-4: Remove unused phase entrypoints, not just their failing statements

The `phase-02-03`/`phase-03-*`/`phase-04*` scripts outside the standard battery contain completed migration probes and discarded boolean results. Transfer only a unique current invariant, if one exists, to its focused owner and delete the obsolete file. Do not edit archived OpenSpec evidence to erase historical references. Update active runner recipes and current documentation if an entrypoint is removed.

### TT-5: Validate retained meaning, not a reduction quota

After each implementation slice, run its focused contract. Review the deleted blocks against the surviving boundary to ensure unique security/recovery behaviour remains covered. Use a small targeted negative case when it demonstrates a realistic lost invariant; do not add a broad mutation framework or a replacement test for every deleted line. The parent runs the scaffold and full battery once at the stable checkpoint, followed by formatting and strict change validation.

## Risks / Trade-offs

- Removing a source check may remove the only evidence for a current contract → classify its invariant before deleting; retain one faithful evaluated or executed check where necessary.
- A smaller battery may stop enforcing old architectural names → intentional; runtime and canonical-record contracts remain, while historical naming is not current behaviour.
- Kanidm evaluation may expose no injectable execution seam → treat as a blocker for that task, not permission to weaken fail-closed cases or redesign production modules.
- Copy-based mutation fixtures may still need narrow source edits to vary a host selection → permitted as fixture construction, not as the oracle; the assertion must observe evaluated behaviour.
- Deferred recipient/privacy defects remain → name them in closeout and do not claim this thinning fixes them.

## Migration Plan

Apply one test slice at a time through the repository's writer lineage. Preserve the current working stack and make no host or secret changes. No deployment is necessary. Run focused checks after each slice, then the parent's full gates and a fresh read-only review. Rollback restores only this change's test and runner edits; archived acceptance records remain untouched.
