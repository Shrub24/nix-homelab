## 1. Baseline and ownership

- [x] 1.1 Capture the clean Stage 3 baseline for all three hosts, including toplevel drvPaths, flake output keys, registry composition, publication inventory, DJ enablement, and the existing scaffold/no-build checks; verify the capture is reproducible from the parent JJ change.
  - refs: `design.md` S4-7; `tests/check-dendritic-scaffold-contract.sh`
  - delegate: `BuildAgent`
  - verify: `just checks test-dendritic-scaffold-contract`; `nix flake check --no-build --no-write-lock-file path:.`
- [x] 1.2 Map every definition, import, assertion, package projection, gate, and merge priority in `modules/flake/aspects.nix` to exactly one destination contributor; distinguish the existing `packages.nix` per-system package owner from the new `fleet-packages.nix` NixOS projection, and verify the inventory has no omitted or duplicate definition.
  - refs: `design.md` S4-2, S4-3
  - delegate: `CodeScout`
  - depends: 1.1
  - verify: source-to-destination inventory covers every definition in `modules/flake/aspects.nix` and distinguishes `flake.packages` from `flake.modules.nixos.fleet-packages`

## 2. Distributed source contributors

- [x] 2.1 Extract the support and foundation definitions from `modules/flake/aspects.nix` into independently discovered concern-owned files while preserving their existing `flake.modules.nixos.<name>` attributes and bodies.
  - refs: `design.md` S4-2, S4-3; `specs/repository-structure/spec.md`
  - delegate: `CoderAgent`
  - depends: 1.2
  - verify: all support/foundation publications evaluate under their original names and no host output disappears
- [x] 2.2 Extract the operational definitions into independently discovered concern-owned files, preserve all Stage 3 gates/assertions/priorities, then delete `modules/flake/aspects.nix` after the complete publication inventory matches the baseline.
  - refs: `design.md` S4-2, S4-7; `specs/fleet-infrastructure/spec.md`
  - delegate: `CoderAgent`
  - depends: 2.1
  - verify: publication inventory matches baseline; `modules/flake/aspects.nix` is absent; focused host evaluations succeed

## 3. DJ selection semantics

- [x] 3.1 Make `flake.modules.nixos.dj` set `applications.dj.enable = true` and remove only the redundant top-level enable assignment from home-forge, preserving Engine enablement, paths, share settings, and secret inputs.
  - refs: `design.md` S4-4; `specs/feature-topology/spec.md`
  - delegate: `CoderAgent`
  - depends: 2.2
  - verify: home-forge evaluates `applications.dj.enable == true` through aspect selection and OCI/LA remain unconfigured for DJ

## 4. Semantic contracts

- [x] 4.1 Update `tests/check-dendritic-scaffold-contract.sh` to discover distributed publications, classify support separately from deployment aspects, include DJ, and stop pinning the deleted central file, exact private implementation filenames, or meaningless import order while retaining Stage 1–3 observable probes; if a direct public-aspect import exists, require an adjacent intrinsic-composition justification.
  - refs: `design.md` S4-5, S4-8; repository-structure and fleet-infrastructure deltas
  - delegate: `TestEngineer`
  - depends: 3.1
  - verify: focused scaffold contract passes, fails when a required publication or host selection is removed, and rejects an unjustified direct public-aspect import
- [x] 4.2 Add the minimum negative mutations proving DJ discovery does not activate deployment, DJ selection supplies enablement, and distributed contributor removal is detected; do not add a new test framework or test file.
  - refs: `design.md` S4-1, S4-4, S4-8
  - delegate: `TestEngineer`
  - depends: 4.1
  - verify: each mutation fails for its named reason and the unmodified repository passes

## 5. Canonical model reconciliation

- [x] 5.1 Record D-050 and reconcile canonical documentation with the corrected two-axis source/deployment model: mark the Stage 3 hybrid and six-directory filter as transitional, remove the permanent “80% plain leaves” endpoint, classify the support trio accurately, and replace the universal no-aspect-import rule with the three composition modes.
  - refs: `proposal.md`; `design.md` S4-1, S4-3, S4-5, S4-6
  - delegate: `DocWriter`
  - depends: 3.1
  - verify: `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/context-history.md`, and `docs/dendritic-transition-analysis.md` agree with the delta specs; D-047/D-048/D-049 remain historical with supersession recorded only in new D-050; zero files under `openspec/changes/archive/` change
- [x] 5.2 Reconcile only current-state directive text that directly contradicts the source/aspect model or transitional filter; do not fold unrelated package-baseline, stale-path, general documentation, `nix-fleet`, or topology cleanup into this change.
  - refs: `AGENTS.md`; `openspec/config.yaml`; current-state Dendritic sections only
  - delegate: `DocWriter`
  - depends: 5.1
  - verify: active directives contain no permanent-hybrid or universal no-aspect-import rule; unrelated prose remains outside the diff

## 6. Validation, equivalence, and review

- [x] 6.1 Run focused and repository-wide validation: formatting, scaffold contract, `just checks all`, canonical no-build flake validation, and all three host toplevel evaluations.
  - refs: `design.md` S4-7, S4-8
  - delegate: `BuildAgent`
  - depends: 4.2, 5.2
  - verify: `treefmt --fail-on-change`; focused contract; `just checks all`; `nix flake check --no-build --no-write-lock-file --refresh path:.`; three drvPath evals
- [x] 6.2 Compare Stage 4 against the clean Stage 3 baseline with the same structured option capture and `nix-diff` for every host; permit only explained source/store provenance movement and stop on any runtime, secret, endpoint, topology, recovery, or service delta.
  - refs: `design.md` S4-7
  - delegate: `BuildAgent`
  - depends: 6.1
  - verify: classification artifact reports zero unexplained deltas for all hosts
- [x] 6.3 Review the complete diff for source/aspect independence, accidental activation, preserved support contracts, rollback safety, test overfitting, and scope leakage; remediate at most one low-risk review pass.
  - refs: all change artifacts
  - delegate: `CodeReviewer`
  - depends: 6.2
  - verify: no blocking or high-severity findings remain
- [x] 6.4 Run strict OpenSpec validation and reconcile checklist state only after every preceding task is verified; confirm no secrets were decrypted or edited.
  - refs: `proposal.md`; all delta specs
  - depends: 6.3
  - verify: `openspec validate dendritic-stage-4-source-model-realignment --strict`; all tasks checked; `.sops.yaml` and `secrets/**` unchanged
