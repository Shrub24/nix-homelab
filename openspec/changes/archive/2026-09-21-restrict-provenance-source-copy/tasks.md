## 1. Baseline and index repair

- [x] 1.1 Record the current Git index divergence (`comm -23 <(jj file list -r @) <(git ls-files)`), the current published `/etc/nixos-source` size and content, and the failure of a `.#` evaluation (`nix eval --raw .#deployHosts.edgeHost` refusing to resolve while `path:.#` returns `la-admin-1`).
- [x] 1.2 Repair the index once (`git add -A`) and prove it survives subsequent jj operations (divergence count `0` after `jj status`; `nix eval --raw .#deployHosts.edgeHost` → the edge host).

## 2. Provenance returns to one line

- [x] 2.1 Revert `modules/flake/provenance.nix` to `environment.etc."nixos-source".source = self.outPath` and delete the `cleanSourceWith`/exclusion-list implementation; keep the module's aspect name and `system.configurationRevision`.
- [x] 2.2 Verify the published copy: it is the tracked set (no `.git`, `.jj`, `.qmd`, `.opencode`, `.hp-forge-esp-backup`, `.terraform`, `mTLS.key`, `secrets.auto.tfvars`, `terraform.tfstate` at any depth), it still contains `flake.nix`, `modules/`, `policy/`, `secrets/`, `lib/`, `docs/`, and `opentofu/` configuration, and its size is ~5.5 MB.
- [x] 2.3 Verify `system.configurationRevision` is non-null under the new reference form, and that the three host toplevels still evaluate.
      Instrument note: the stored pre-change observables predate the Stage 8 4.2 Audiomuse migration, so home-forge shows exactly one expected delta (`applications.music.audiomuse` aspect option `oci-melb-1` → `null`; leaf `services.audiomuse.postgresHost` unchanged at `oci-melb-1:5432`). That delta reproduces identically under `path:.` on the current tree, so it is not caused by this change; `oci-melb-1` and `la-admin-1` match the baseline exactly.

## 3. Local flake references use the Git-tree form

- [x] 3.1 Replace `path:.` with `.#` in `justfile` (deploy, dry-activate, prebuild, notify, and the evaluation guards).
- [x] 3.2 Replace `path:.#…` with `.#…` in `.github/workflows/deploy-host.yml`, in `docs/architecture.md`'s operator command, and in the `flake.bootstrap.nodes.<host>.flake` projection (`modules/flake/registry.nix`), updating every test anchor that asserts that value.
- [x] 3.3 Prove the result end to end at evaluation level: `nix eval --raw .#deployHosts.edgeHost`, the deploy/prebuild recipes' evaluation steps, the resolver, and `nix build --dry-run` on the deploy node profile and `host-<host>` — no actual deploy. The `nix flake check --no-build .` leg is parent-owned per the dispatch (that command was explicitly excluded from this run).

## 4. Index-integrity guard

- [x] 4.1 Add `tests/check-flake-source-tracking.sh`: fail when any jj-tracked file is missing from the Git index, with a message naming the repair (`git add -A`) and why it matters (the Git-tree flake form copies tracked content only, so a partial index silently evaluates a partial tree); pass clean on the repaired tree.
- [x] 4.2 Wire the test into `.just/checks.just` so `just checks all` covers it, and prove it fails on a deliberately removed index entry (mutate a copy or use `git rm --cached` in a scratch copy — not in the working repository).

## 5. Documentation and guidance

- [x] 5.1 Refresh `AGENTS.md`: replace the placeholder architecture block; document the `.#` evaluation rule, the index precondition with its forbidden commands (`git reset`, `git checkout`, `git stash`) and the repair, and add the project-owned delegation/apply policy section (task-sized worker, focused validation per task, fresh bounded reviewer at checkpoints, parent owns long gates, rotate a lineage once its context is large).
- [x] 5.2 Record D-057 in `docs/decisions.md` (tracked-only provenance, the reference-form rule, the index precondition) and update `ARCHITECTURE.md`, `STRUCTURE.md`, `docs/architecture.md`, and `CONVENTIONS.md` where they describe provenance or local evaluation.
- [x] 5.3 Refresh the stale project context in `openspec/config.yaml` (it still describes the pre-Stage-2 layout: `modules/applications/`, `modules/providers/`, a four-entry import boundary, the `nixos.configurations` registry).
- [x] 5.4 Update the debt ledger in `docs/plan.md`: retire `TD-19`, record that `configurationRevision` is no longer null, and add the index-precondition dependency as a named operational constraint.

## 6. Verification

- [x] 6.1 Run `treefmt --fail-on-change`, `just checks all`, `nix flake check --no-build .`, and `openspec validate restrict-provenance-source-copy --strict`.
- [x] 6.2 Confirm no secret file, `.sops.yaml` rule, or encrypted value changed; confirm the plaintext credential files are untouched in the working tree and merely excluded from the published copy.
- [x] 6.3 Obtain one independent read-only review of the reference-form change (index precondition, guard non-vacuity, no behaviour change beyond the published source) before closing.
