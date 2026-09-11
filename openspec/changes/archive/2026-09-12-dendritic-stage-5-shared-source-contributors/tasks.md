## 1. Stage 4 baseline and ownership

- [x] 1.1 Capture the clean deployed Stage 4 baseline at parent `6a824851` before implementation.
  - refs: `flake.nix`, `modules/flake/registry.nix`, `openspec/changes/dendritic-stage-5-shared-source-contributors/design.md`
  - criteria: A clean detached checkout at exactly `6a824851` builds all three host toplevels; deployed generation/store paths and structured observable snapshots are recorded for later comparison, with pre-existing failures identified.
  - delegate: BuildAgent
  - verify: Confirm the checkout commit and clean state; evaluate/build `oci-melb-1`, `la-admin-1`, and `home-forge`; capture baseline `nix diff-closures` inputs and outputs.

- [x] 1.2 Inventory Stage 4 consumers, owners, imports, publications, selections, and protected scope.
  - refs: `modules/shared/`, `modules/storage/`, `modules/flake/`, `modules/hosts/`, `modules/applications/admin/default.nix`, `tests/check-dendritic-scaffold-contract.sh`
  - criteria: The inventory maps every shared/storage leaf to its consumer or proves zero consumers; records current module priorities and host observables; and freezes the scope guard: no changes to `secrets/**`, `.sops.yaml`, `policy/**`, routes/topology, edge-ingress or edge/cockpit/quantum overlays, admin behavior beyond the specified import deletion, music/DJ behavior, or product/service behavior.
  - delegate: CodeScout
  - depends: 1.1
  - verify: Exhaustive import/reference results reconcile with the seven shared leaves, two storage leaves, six filter entries, and the Stage 4 snapshots.

## 2. Remove dead storage

- [x] 2.1 Prove both shared storage templates have zero consumers, then delete only those templates.
  - refs: `modules/storage/disko-root.nix`, `modules/storage/disko-single-disk.nix`, `modules/hosts/oci-melb-1/disko-single-disk-split.nix`, `modules/hosts/home-forge/disko-two-disk.nix`
  - criteria: Zero-consumer proof precedes deletion; both shared templates are deleted; both host-local layouts remain byte-identical; no wrapper or replacement template is added; `_unconverted-nixos-dirs.nix` is not shrunk in this task.
  - delegate: OpenDevopsSpecialist
  - depends: 1.2
  - verify: Exhaustive references contain no consumer of either deleted template, focused storage evaluation is unchanged, and the host-local layout hashes match Stage 4.

## 3. Relocate concern-owned private leaves

- [x] 3.1 Move host recovery beside the base aspect and update its sole owner import.
  - refs: `modules/shared/host-recovery.nix`, `modules/flake/_aspects/base.nix`, `modules/flake/_aspects/host-recovery.nix`
  - criteria: The leaf moves to `_aspects/host-recovery.nix`; `base.nix` imports it locally; its body, option values, merge priorities, service, and timer behavior are preserved; it has no relative repo reads, so no path adjustment is required; no new public aspect is created.
  - delegate: OpenDevopsSpecialist
  - depends: 2.1
  - verify: A content-aware move diff shows only path/import changes, and all three hosts retain both host-recovery units with Stage 4 values.

- [x] 3.2 Move the niks3 leaves and nixbuild SSH leaf beside their existing aspect owners.
  - refs: `modules/shared/niks3-upload-client.nix`, `modules/shared/niks3-post-deploy.nix`, `modules/shared/nixbuild-ssh.nix`, `modules/flake/backups.nix`, `modules/flake/builder-access.nix`
  - criteria: The niks3 leaves move to `modules/flake/_backups/`; nixbuild SSH moves to `modules/flake/_builder-access/nixbuild-ssh.nix`; owner imports use the new private paths; content, defaults, and merge priorities are preserved, except `niks3-upload-client.nix` adjusts its conventional secret read `../../secrets/hosts` -> `../../../secrets/hosts` because the leaf moves one level deeper (`niks3-post-deploy.nix` and `nixbuild-ssh.nix` have no relative repo reads); public aspect names remain unchanged.
  - delegate: OpenDevopsSpecialist
  - depends: 2.1
  - verify: Move-aware diffs show no implementation drift; all hosts retain nixbuild trust plus niks3 upload/post-deploy values, and only OCI retains `services.niks3.enable`.

## 4. Add discovered contributors and explicit selection

- [x] 4.1 Convert web policy into a discovered infrastructure-support contributor and select it on every host.
  - refs: `modules/shared/web-policy.nix`, `modules/flake/web-policy.nix`, `modules/flake/registry.nix`, `modules/hosts/{oci-melb-1,la-admin-1,home-forge}/default.nix`
  - criteria: `modules/flake/web-policy.nix` publishes `flake.modules.nixos.web-policy`; all three registry records select `aspects.web-policy`; all direct host imports of the old leaf are removed; `repo.web` contents/default priorities and notification URL behavior are unchanged; it is not modeled as an edge capability.
  - delegate: OpenDevopsSpecialist
  - depends: 3.1, 3.2
  - verify: Evaluate `config.repo.web` and `services.notification-daemon.ntfy.serverUrl` on all three hosts and compare their structured values with Stage 4.

- [x] 4.2 Create two discovered identity contributors that merge into the same `identity-client` aspect.
  - refs: `modules/shared/identity-oidc.nix`, `modules/shared/kanidm-host-auth.nix`, `modules/flake/identity-oidc.nix`, `modules/flake/kanidm-host-auth.nix`
  - criteria: Two separate top-level contributors each nest their existing option/config body directly inside a `flake.modules.nixos.identity-client` definition; content, semantics, and merge priority are preserved; there are no `_identity-client/` private leaves, no `identity-client.nix` wrapper, no cross-contributor import, `specialArgs`, or compatibility bus; no host or application file imports either contributor directly.
  - delegate: OpenDevopsSpecialist
  - depends: 4.1
  - notes: Execute the code changes for 4.2 and 4.3 as one atomic batch: moving the two leaves without simultaneously selecting the aspect and removing the old imports would leave an invalid intermediate tree. Verify and check off 4.2 before 4.3.
  - verify: Discovery sees exactly two identity contributors and no identity private leaf directory; selecting the one aspect yields both OIDC and host-auth behavior; deleting either contributor removes its own OIDC or host-auth/Kanidm behavior.

- [x] 4.3 Select identity on OCI and LA only and remove every former direct identity import.
  - refs: `modules/flake/registry.nix`, `modules/hosts/{oci-melb-1,la-admin-1,home-forge}/default.nix`, `modules/applications/admin/default.nix`
  - criteria: OCI and LA select `aspects.identity-client`; forge does not; host imports of both former shared leaves and admin's direct OIDC import are removed; provider URLs, clients, host-auth blocks, Kanidm URI, and secret wiring remain unchanged; no admin redesign occurs; no host or application file imports `identity-oidc` or `kanidm-host-auth` outside the discovery tree.
  - delegate: OpenDevopsSpecialist
  - depends: 4.2
  - verify: OCI/LA expose the Stage 4 identity observables (providerUrl `https://id.shrublab.xyz`, clients, hostAuth, Kanidm URI); forge has no `services.identity` (probed via `(services.identity or {})`) or Kanidm client activation; exhaustive imports contain no direct identity-oidc/kanidm-host-auth path.

## 5. Close roots and strengthen the scaffold contract

- [x] 5.1 Delete the exact evacuated roots and shrink the single filter from six entries to four.
  - refs: `modules/shared/`, `modules/storage/`, `modules/flake/_unconverted-nixos-dirs.nix`, `tests/check-dendritic-scaffold-contract.sh`
  - criteria: `modules/shared` and `modules/storage` are absent before the filter edit; the filter then contains exactly `applications`, `hosts`, `providers`, and `services`; no renamed/replacement boundary or shared wrapper exists; only obsolete shared/storage discovery exclusions are removed.
  - delegate: OpenDevopsSpecialist
  - depends: 4.3
  - verify: Root-evacuation checks (`modules/shared` and `modules/storage` must not exist) pass, the filter is an exact four-item set, and the import tree evaluates without either exclusion.

- [x] 5.2 Update positive scaffold assertions around publications, selection, ownership, and observables.
  - refs: `tests/check-dendritic-scaffold-contract.sh`, `modules/flake/registry.nix`, `modules/flake/_aspects/`, `modules/flake/_backups/`, `modules/flake/_builder-access/`
  - criteria: The contract semantically proves 14 publications (support quartet + ten deployment aspects), exact per-host selections (support quartet + eight + `identity-client` on OCI/LA; support quartet + eight + `dj` on forge), all-host web support, OCI/LA-only identity, private-owner non-discovery/non-publication for `_aspects`/`_backups`/`_builder-access`, root evacuation, and unchanged web, identity, recovery, builder, niks3, package, deploy, Tailscale, notify, backups, and secret observables. Concretely it updates: check 1's six-entry filter to four plus `modules/shared`/`modules/storage` absence; `discovered_contributors` exclusions; the 7a publication set and 7b selection sets; the relocated leaf inventory paths and owner-import greps; the `filterPackage`/`config.repo.packages` greps to `_backups/niks3-post-deploy.nix`; the `niks3-auto-upload` check narrowed to the `inputs.niks3.nixosModules.niks3-auto-upload` import so option mentions do not false-positive; and the `host_leaf_imports_of` pattern to the new private paths.
  - delegate: TestEngineer
  - depends: 5.1
  - verify: The focused contract passes against the implementation and reports semantic set/value differences rather than relying on source order.

- [x] 5.3 Add and run semantic negative mutations for the Stage 5 invariants.
  - refs: `tests/check-dendritic-scaffold-contract.sh`, `modules/flake/identity-oidc.nix`, `modules/flake/kanidm-host-auth.nix`, `modules/flake/_unconverted-nixos-dirs.nix`
  - criteria: Mutations reject a surviving evacuated root, fake filter shrink, private-leaf discovery/publication, direct imports of the relocated or identity contributors, identity activation on forge, and deletion of either identity contributor; contributor deletion is detected through the missing OIDC or host-auth/Kanidm observable/eval — not a missing publication (the sibling contributor still defines the aspect) and not merely a required filename. The re-import mutation anchors on a host import line that survives this change and inserts a new private leaf path so `host_leaf_imports_of` is exercised non-vacuously.
  - delegate: TestEngineer
  - depends: 5.2
  - verify: Each mutation fails for its intended semantic reason, the unmodified tree passes, and every mutation is reverted after execution.

## 6. Reconcile current documentation

- [x] 6.1 Record D-051 and reconcile only current canonical documentation with Stage 5.
  - refs: `STRUCTURE.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `openspec/config.yaml`, `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/context-history.md`, `docs/dendritic-transition-analysis.md`
  - criteria: Current docs describe both removed roots, the exact four-entry filter, concern-owned private paths (`_aspects`/`_backups`/`_builder-access`), all-host web-policy support, and the two-contributor inline `identity-client` aspect (no `_identity-client/` leaves); D-051 records the decision, explicitly supersedes only D-050's deferral clause for web-policy and identity-client (music remains deferred), and records the private-path convention so it is not normalized later; `CONVENTIONS.md` and `openspec/config.yaml` reflect the post-change structure; archives remain untouched; active stale artifacts such as `normalize-fleet-boundaries` and `open-webui` are not rewritten.
  - delegate: CoderAgent
  - depends: 5.3
  - verify: Links/path examples match the implemented tree; `openspec/changes/archive/**` and every other active change directory have zero diff.

## 7. Validation and review gates

- [x] 7.1 Run focused checks, formatting, the full check set, no-build flake checks, and all three drv evaluations.
  - refs: `tests/check-dendritic-scaffold-contract.sh`, `treefmt.toml`, `.just/checks.just`, `flake.nix`
  - criteria: The focused scaffold contract, `treefmt --fail-on-change`, `just checks all`, and `nix flake check --no-build` pass; all three host toplevel `drvPath` evaluations succeed; failures are resolved without broadening scope.
  - delegate: BuildAgent
  - depends: 6.1
  - verify: Evaluate `nixosConfigurations.{oci-melb-1,la-admin-1,home-forge}.config.system.build.toplevel.drvPath` and retain command/status evidence for every gate.

- [x] 7.2 Compare structured observables and closures against the clean Stage 4 baseline.
  - refs: `openspec/changes/dendritic-stage-5-shared-source-contributors/design.md`, `flake.nix`, `modules/flake/registry.nix`
  - criteria: Structured captures for all explicit observables equal the `6a824851` snapshots (identity providerUrl pinned to the policy-derived `https://id.shrublab.xyz` on OCI and LA; forge probed via `(services.identity or {})` and confirmed absent). `nix-diff` and `nix diff-closures` evidence is reviewed against the explicit provenance-only allowlist (derivation/store-path renames and source-order/comment changes caused solely by relocating or nesting expressions); any unexplained runtime/observable delta blocks completion.
  - delegate: BuildAgent
  - depends: 7.1
  - verify: Review machine-readable before/after captures plus per-host `nix-diff` and `nix diff-closures` outputs for OCI, LA, and forge against the allowlist.

- [x] 7.3 Obtain independent review and close the strict OpenSpec, checklist, and scope gates.
  - refs: `openspec/changes/dendritic-stage-5-shared-source-contributors/{proposal.md,design.md,specs,tasks.md}`, `.sops.yaml`, `secrets/`, `policy/`
  - criteria: Independent review finds no unresolved high/medium correctness, architecture, security, or rollback issue; strict OpenSpec validation passes; the parent agent alone owns checkbox updates; the final diff contains no secret decryption/edit, `.sops.yaml` change, policy/route/edge/admin/music/product behavior drift, archive rewrite, active-change rewrite, new flake input, deployment, or out-of-scope file.
  - delegate: CodeReviewer
  - depends: 7.2
  - verify: Run `openspec validate dendritic-stage-5-shared-source-contributors --strict`, reconcile every checklist item to evidence, inspect the complete allowlisted diff, and record the independent review result.
