## 1. Baseline And Contract Preparation

- [x] 1.1 Capture Stage 0 drvPaths and targeted host/output values for all three hosts, and verify the live `self`/`inputs`/`ociImages` consumer and `hosts/` path-reference inventories before implementation.
  - refs: `design.md` DS-4, DS-7
  - delegate: CodeScout, BuildAgent
  - verify: all three drvPath evaluations succeed; recorded inventories cover every live consumer and path-sensitive reference
- [x] 1.2 Repair only the malformed canonical spec structure for capabilities modified by this change, preserving every existing requirement and scenario, and verify `openspec validate --specs --strict` passes for those capabilities.
  - refs: `specs/repository-structure/spec.md`, `design.md` Migration Plan
  - delegate: DocWriter
  - verify: strict spec validation passes and requirement/scenario counts do not decrease
- [x] 1.3 Add pinned flake-parts and `denful/import-tree` inputs without refreshing unrelated inputs, and verify the lock diff is limited to required dependency nodes.
  - refs: `design.md` DS-1
  - delegate: CoderAgent
  - verify: `nix flake metadata` succeeds and lockfile review finds no unrelated refresh

## 2. Dendritic Scaffold And Host Registry

- [x] 2.1 Replace the hand-written flake output function with a minimal flake-parts entrypoint, import `flakeModules.modules`, and add one named import-tree `filterNot` boundary; verify no plain NixOS leaf is evaluated as a flake-parts module.
  - refs: `design.md` DS-1, DS-3; `specs/repository-structure/spec.md`
  - delegate: CoderAgent
  - verify: flake evaluation succeeds and a contract check enumerates the temporary exclusions
- [x] 2.2 Implement the typed `nixos.configurations.<host>` record and `eval-config.nix` materialization into `flake.nixosConfigurations`; verify all three host names and target systems match Stage 0.
  - refs: `design.md` DS-2; `specs/fleet-infrastructure/spec.md`
  - delegate: CoderAgent
  - verify: registry values and `nixosConfigurations` keys/systems evaluate for `la-admin-1`, `oci-melb-1`, and `home-forge`
- [x] 2.3 Preserve packages, checks, formatter, dev shells, deploy-rs nodes, deploy metadata, and bootstrap projections through flake-parts; verify every Stage 0 flake output path still evaluates.
  - refs: `design.md` DS-2, DS-6; `specs/fleet-infrastructure/spec.md`, `specs/bootstrap-storage/spec.md`
  - delegate: CoderAgent
  - verify: targeted `nix eval` covers each preserved output and `flake.bootstrap.nodes.oci-melb-1` returns the expected typed values

## 3. Argument Ownership And Atomic Host Move

- [x] 3.1 Replace all lower-level `self`, `inputs`, and `ociImages` consumers with lexical aspect ownership, host-matched `withSystem` packages, typed `repo.ociImages` policy, and direct registry wiring; verify exhaustive search finds no prohibited lower-level argument or broad compatibility bus.
  - refs: `design.md` DS-3, DS-4
  - delegate: CoderAgent
  - verify: exhaustive symbol search is clean and targeted provenance/package/image evaluations match Stage 0
- [x] 3.2 Move all three host directories and sole-consumer disko layouts under `modules/hosts/`, rename OCI bootstrap metadata to `_bootstrap-config.nix`, and update relative imports without changing host composition.
  - refs: `design.md` DS-5; all four delta specs
  - delegate: CoderAgent
  - verify: old `hosts/` assembly paths are absent, host-private files are ignored by import-tree, and all three hosts evaluate
- [x] 3.3 Rewire deploy and bootstrap consumers to the registry/materialized outputs while preserving physical metadata in `lib/deploy/hosts.nix`; verify deploy node paths, edge host, deploy order, SSH users, remote-build flags, and bootstrap resolution are unchanged.
  - refs: `design.md` DS-4, DS-6
  - delegate: CoderAgent
  - verify: targeted `nix eval` comparison and bootstrap resolver contract checks pass

## 4. Contracts And Documentation

- [x] 4.1 Update path-sensitive tests and add the smallest contract checks for import-tree exclusions, registry/output consistency, and bootstrap projection; verify the focused tests fail against the old path/shape and pass against Stage 1.
  - refs: `design.md` DS-1, DS-2, DS-6
  - delegate: TestEngineer
  - verify: affected phase/bootstrap checks and new focused contracts pass
- [x] 4.2 Update all current-path operator docs, runbooks, architecture/structure summaries, and active OpenSpec references while preserving historical decision text as history; verify no current instruction points to the removed host assembly path.
  - refs: `specs/repository-structure/spec.md`, `specs/bootstrap-storage/spec.md`, `specs/admin-module-structure/spec.md`
  - delegate: DocWriter
  - verify: exhaustive documentation search classifies every remaining `hosts/` occurrence as secret path, archived history, or intentional historical text

## 5. Equivalence And Review

- [x] 5.1 Run formatting, focused contracts, `just checks all`, and the canonical CI flake-evaluation gate; verify every check passes on the Stage 1 tree and document architecture-specific builds separately.
  - refs: `design.md` DS-7
  - delegate: BuildAgent
  - verify: `treefmt --fail-on-change`, `just checks all`, and `nix flake check --no-build --no-write-lock-file --refresh path:.` succeed; full builds run only where the target architecture is available
- [x] 5.2 Compare each Stage 1 host to its recorded Stage 0 derivation, classify every `nix-diff` result, and verify configuration revision, source link, boot, filesystem, firewall, secret, service, user, package, and deploy surfaces have no unexplained runtime delta.
  - refs: `design.md` DS-7
  - delegate: BuildAgent
  - verify: three-host equivalence report accepts only source/provenance movement and contains no unexplained difference
- [x] 5.3 Review the complete Stage 1 diff for Dendritic correctness, accidental feature activation, cross-system package errors, security/deployment drift, and implicit completion of superseded tasks; remediate at most one safe review pass.
  - refs: `proposal.md`, `design.md` Risks / Trade-offs
  - delegate: CodeReviewer
  - verify: independent review has no unresolved correctness or scope findings
- [x] 5.4 Run strict OpenSpec validation and verify every Stage 1 checkbox is complete before handoff; do not deploy or archive automatically.
  - refs: all change artifacts
  - verify: `openspec validate --strict` and `openspec status --change dendritic-stage-1-scaffold-hosts --json` report valid/all done

## 6. Approved Completion Refinements

- [x] 6.1 Replace the hand-rolled nixpkgs `eval-config.nix` materialization with `inputs.nixpkgs.lib.nixosSystem`, preserving typed records, explicit target systems, and zero `specialArgs`.
  - refs: `design.md` DS-2
  - delegate: CoderAgent
  - verify: all three host derivations differ only through the embedded repository source/provenance path, with targeted outputs unchanged; registry implementation no longer imports `eval-config.nix`
- [x] 6.2 Inline OCI bootstrap metadata into its typed host record, derive `hostName` and `flake` in the bootstrap projection, and delete `_bootstrap-config.nix`.
  - refs: `design.md` DS-5, DS-6; `specs/bootstrap-storage/spec.md`
  - delegate: CoderAgent
  - verify: OCI's seven projected bootstrap values are unchanged; other hosts remain absent; no importer or current-path reference to the deleted file remains
- [x] 6.3 Remove the obsolete bootstrap source-file gate from `deploy.sh`, `scripts/resolve-host-config.sh`, and the root `justfile`, while preserving fail-closed required-value checks before Nix or network work.
  - refs: `design.md` DS-6
  - delegate: CoderAgent
  - verify: bare `./deploy.sh` fails before invoking Nix; resolved target, user, and flake values remain unchanged; no `--host-config` machinery remains
- [x] 6.4 Update focused bootstrap/scaffold contracts and current-state documentation for the standard materializer and inline registry metadata.
  - refs: `design.md` DS-2, DS-5, DS-6; `specs/repository-structure/spec.md`
  - delegate: TestEngineer, DocWriter
  - verify: focused tests fail against the pre-refinement shape and pass against the refined tree; remaining old-form references are historical only
- [x] 6.5 Run formatting, all contracts, the canonical flake evaluation gate, three-host equivalence comparison, independent review, and strict OpenSpec validation.
  - refs: `design.md` DS-7
  - delegate: BuildAgent, CodeReviewer
  - verify: no unexplained host/output delta; review has no unresolved findings; strict validation and status report complete
