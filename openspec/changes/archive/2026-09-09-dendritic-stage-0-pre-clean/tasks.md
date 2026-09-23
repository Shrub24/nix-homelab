## 1. Baseline And Workflow State

- [x] 1.1 Reverify every cleanup candidate and capture the affected three-host option baselines before editing; verify exhaustive repository search finds no active consumer for each deletion and all host drvPath evaluations succeed.
  - refs: `design.md` PC-1, PC-5
  - delegate: CodeScout, BuildAgent
  - verify: codebase-memory exhaustive searches plus `nix eval --impure .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` for `la-admin-1`, `oci-melb-1`, and `home-forge`
- [x] 1.2 Strictly validate and archive only the completed `normalize-music-storage-topology` change; verify every checkbox is complete before `openspec validate --strict` and `openspec archive` succeed.
  - refs: `design.md` PC-2
  - verify: `openspec validate --strict` and `openspec archive normalize-music-storage-topology --yes`
- [x] 1.3 Mark `normalize-fleet-boundaries` as superseded without completing or archiving its unchecked tasks; verify its artifacts point to this staged transition and its checkbox state is unchanged.
  - refs: `design.md` PC-2
  - verify: compare its task checkbox counts before and after the documentation update

## 2. Proven Structural Cleanup

- [x] 2.1 Remove the unused Paperless application wrapper while preserving the directly imported Paperless service; verify no active import references the wrapper and all three hosts still evaluate.
  - refs: `design.md` PC-1
  - delegate: CoderAgent
  - verify: exhaustive path-reference search plus three-host drvPath evaluation
- [x] 2.2 Remove the orphan `.just/deploy.just` recipe module and verify the root justfile has no import or recipe dependency on it.
  - refs: `design.md` PC-1
  - delegate: CoderAgent
  - verify: exhaustive path-reference search and `just --list`
- [x] 2.3 Remove the unused `mkSimpleSecret` helper and verify all remaining `lib/secrets.nix` exports and callers evaluate.
  - refs: `design.md` PC-1
  - delegate: CoderAgent
  - verify: exhaustive symbol search plus three-host drvPath evaluation
- [x] 2.4 Remove only demonstrably redundant host declarations identified by task 1.1 and correct the Audiomuse credential ownership comments to match D-045; verify affected option values are unchanged and no encrypted secret or `.sops.yaml` content changes.
  - refs: `design.md` PC-1, PC-4
  - delegate: CoderAgent
  - verify: targeted before/after `nix eval`, three-host drvPath evaluation, and `jj diff --summary` showing no secrets-path modifications

## 3. Architecture Reconciliation

- [x] 3.1 Add a decision superseding D-030's plain-flake restriction with the agreed staged Dendritic direction and code-only `nix-fleet` extraction rule; verify topology, web policy, OpenTofu, deployment metadata, and secret ownership remain explicitly local.
  - refs: `proposal.md`, `design.md` PC-3, PC-4
  - delegate: DocWriter
  - verify: decision register contains the supersession, deferred technologies, and local-ownership boundaries
- [x] 3.2 Update `docs/dendritic-transition-analysis.md` with a dated revalidation of current hosts, completed music migration, current argument consumers, settled Stage 1 structure, and corrected import-tree ownership/semantics.
  - refs: `design.md` PC-3
  - delegate: DocWriter
  - verify: stale claims identified during re-exploration are absent or explicitly historical
- [x] 3.3 Reconcile directly affected architecture, plan, and context-history documentation without claiming Stage 1 is implemented; verify current-state and target-state language remain distinct.
  - refs: `proposal.md`, `design.md` PC-3, PC-4
  - delegate: DocWriter
  - verify: documentation search finds no active claim that Dendritic is already implemented or that the completed music move is future work

## 4. Verification And Handoff

- [x] 4.1 Run formatting, repository contract checks, and all three host evaluations; classify every derivation difference and verify only source/provenance changes remain.
  - refs: `design.md` PC-5
  - delegate: BuildAgent
  - verify: `treefmt --fail-on-change`, scoped repository checks, three-host drvPath evaluation, and recorded `nix-diff` classification
- [x] 4.1a Make the Kanidm restore contract's optional 1.10 seed lookup tolerate an empty store glob under `pipefail`; verify the test reaches its intended explicit SKIP branch and `just checks all` passes.
  - refs: `tests/kanidm-restore-contract.sh`
  - verify: `bash tests/kanidm-restore-contract.sh` and `just checks all`
- [x] 4.2 Review the complete Stage 0 diff for accidental behavior, security-boundary, deployment, or soak-residue changes and remediate at most one review pass.
  - refs: `proposal.md`, `design.md` PC-4, Risks / Trade-offs
  - delegate: CodeReviewer
  - verify: review has no unresolved correctness or scope findings
- [x] 4.3 Run strict OpenSpec validation and verify every Stage 0 task is complete before using this change as the Stage 1 parent.
  - refs: `proposal.md`, `design.md`
  - verify: `openspec validate --strict` and `openspec status --change dendritic-stage-0-pre-clean --json`
