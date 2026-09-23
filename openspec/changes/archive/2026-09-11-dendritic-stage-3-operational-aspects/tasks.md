## 1. Baseline and ownership

- [x] 1.1 Capture a clean Stage 2 baseline for all three hosts, including toplevel drvPaths and the operational options, secrets, units, packages, SSH configuration, and backup contracts affected by this change; verify the capture completes before implementation.
  - refs: `design.md` OPS-10; `modules/hosts/*/default.nix`
  - delegate: BuildAgent
  - verify: Evaluate and save the same structured option set for `oci-melb-1`, `la-admin-1`, and `home-forge` from Stage 2 and confirm `nix flake check --no-build --no-write-lock-file` succeeds.
- [x] 1.2 Confirm the five deferred leaves' complete responsibility and override map against the Stage 2 baseline; verify every current host declaration has an explicit Stage 3 owner and no secret or deployment topology edit is required.
  - refs: `design.md` OPS-2 through OPS-8; `modules/shared/{niks3-post-deploy,niks3-upload-client,nixbuild-ssh}.nix`; `modules/services/{state-backups,beszel-agent-auth}.nix`
  - delegate: CodeScout
  - verify: Produce a responsibility-to-aspect/host matrix covering backup paths, bucket/staging variants, niks3 token ownership and endpoint, builder trust, Beszel bootstrap gating, and notify dependency.

## 2. Publish operational aspects

- [x] 2.1 Publish exactly `backups`, `builder-access`, and `observability-agent` as thin NixOS aspects over the five existing leaves; verify no aspect imports another aspect and no compatibility wrapper or generic composition bus is introduced.
  - refs: `design.md` OPS-1, OPS-3, OPS-7, OPS-8; `specs/fleet-infrastructure/spec.md`
  - delegate: CoderAgent
  - verify: Evaluate the three `flake.modules.nixos` attributes and inspect their import closures.
- [x] 2.2 Make aspect selection the existing enablement: derive the default backup bucket from `networking.hostName`, retain host-specific backup and cache variants, assert notification monitoring for enabled backups, and preserve niks3/Beszel secret bootstrap precedence; verify missing notification composition fails with the named assertion while all current hosts evaluate.
  - refs: `design.md` OPS-3 through OPS-6, OPS-8; `specs/state-backups/spec.md`; `specs/sovereign-binary-cache/spec.md`; `specs/internal-service-auth/spec.md`
  - delegate: CoderAgent
  - depends: 2.1
  - verify: Run targeted positive/negative Nix evaluations for bucket derivation, notify assertion, OCI token owner/loopback endpoint, absent-secret gates, and the single classified post-build-hook suppression.

## 3. Convert host composition

- [x] 3.1 Select all three operational aspects in every host registry record, delete the repeated five-leaf import block and superseded enablement from host modules, and retain only real per-host values; verify all three hosts preserve their Stage 2 operational option values.
  - refs: `design.md` OPS-2 and host migration table; `modules/flake/registry.nix`; `modules/hosts/*/default.nix`
  - delegate: CoderAgent
  - depends: 2.2
  - verify: Compare targeted host evaluations to task 1.1 and confirm builder access remains selected on `home-forge`.
- [x] 3.2 Keep `modules/services/niks3.nix`, the Beszel hub, and all other product leaves outside these aspects, and leave the exact import-tree exclusion list unchanged; verify `services/` and `shared/` remain excluded for their surviving plain leaves.
  - refs: `design.md` OPS-7 through OPS-9; `modules/flake/_unconverted-nixos-dirs.nix`
  - delegate: CoderAgent
  - depends: 3.1
  - verify: The exclusion inventory remains byte-equivalent and targeted checks confirm the niks3 server is OCI-only and the Beszel hub remains admin-owned.

## 4. Contracts and documentation

- [x] 4.1 Rewrite the scaffold contract's publication/selection and retained-leaf assertions for Stage 3, add the smallest negative checks for notify dependency and host secret bootstrap behavior, and verify existing backup-surface and secret-scope contracts remain green.
  - refs: `tests/check-dendritic-scaffold-contract.sh`; `tests/check-backup-surface-contract.sh`; `tests/check-secret-scope.sh`; all Stage 3 delta specs
  - delegate: TestEngineer
  - depends: 3.2
  - verify: Run the focused contract scripts and demonstrate the new contract fails against the Stage 2 shape or equivalent controlled mutations.
- [x] 4.2 Reconcile current architecture, conventions, decisions, plan, migration history, backup runbooks, and OpenSpec project context with the shipped operational-aspect structure; verify no current document presents the five leaves as host imports or uses the stale `niks3-push.nix`/deleted core-profile paths.
  - refs: `ARCHITECTURE.md`; `STRUCTURE.md`; `CONVENTIONS.md`; `docs/{architecture,decisions,plan,context-history,dendritic-transition-analysis}.md`; `docs/runbooks/`; `openspec/config.yaml`
  - delegate: DocWriter
  - depends: 3.2
  - verify: Targeted literal searches find no stale current-state references; historical/archive text is preserved and D-049 records the completed boundary.

## 5. Validation and review

- [x] 5.1 Run formatting, focused contracts, `just checks all`, canonical no-build flake validation, and all three host drvPath evaluations; verify every command passes and forbidden secret/deploy paths are untouched.
  - refs: `proposal.md` constraints; `design.md` OPS-10
  - delegate: BuildAgent
  - depends: 4.1, 4.2
  - verify: `treefmt --fail-on-change`; `just checks all`; `nix flake check --no-build --no-write-lock-file --refresh path:.`; three host toplevel evaluations; diff scope audit.
- [x] 5.2 Compare Stage 3 to the clean Stage 2 baseline for all three hosts with structured option comparison and `nix-diff`; verify every delta is explained by source provenance or the specified composition refactor and stop on any runtime, recovery, secret, SSH, or unit delta.
  - refs: `design.md` OPS-10; task 1.1 baseline
  - delegate: BuildAgent
  - depends: 5.1
  - verify: Produce a classified three-host equivalence report with zero unexplained deltas.
- [x] 5.3 Review the complete change for architecture, backup recovery, secret blast radius, Nix merge priority, post-build-hook behavior, hidden dependencies, and rollback correctness; verify all blocking findings are resolved with at most one remediation pass.
  - refs: proposal, design, specs, complete diff
  - delegate: CodeReviewer
  - depends: 5.2
  - verify: Independent findings-first review reports no unresolved blocking or high-severity findings.
- [x] 5.4 Run strict OpenSpec validation, confirm every checklist item is complete, then advance and push `wip/dendritic-transition` without deployment or archival; verify the remote bookmark points at the validated Stage 3 tip.
  - refs: all change artifacts; project workflow rules
  - depends: 5.3
  - verify: `openspec validate dendritic-stage-3-operational-aspects --strict`, `openspec status --change dendritic-stage-3-operational-aspects --json`, and `jj bookmark list wip/dendritic-transition` all report the expected completed state.
