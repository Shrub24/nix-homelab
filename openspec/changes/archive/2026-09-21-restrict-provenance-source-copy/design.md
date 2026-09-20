## Context

`environment.etc."nixos-source".source = self.outPath` is the repository's only provenance mechanism: it makes the deployed configuration readable on the host for debugging and drift inspection. What it publishes is determined by how the flake is referenced, not by the module.

The change adopts the Git-tree reference form for local evaluation, which makes tracking the single filtering authority and restores a meaningful `configurationRevision`.

## Decisions

### PSC-1 — Local evaluation uses the Git-tree form `.#`

Every local reference to this repository's own flake uses `.#` / `.#<output>`: the `justfile` recipes, the deploy workflow, the documented cutover command, and the `flake.bootstrap.nodes.<host>.flake` projection consumed by `nixos-anywhere`.

Measured effect on the published source:

| reference | published content | size |
| --- | --- | --- |
| `path:.` | raw working directory: `.git` 104 MB, `opentofu/` 161 MB (incl. `.terraform` providers), `.hp-forge-esp-backup` 86 MB, `.opencode` 57 MB, `.jj` 20 MB, `.qmd` 8.8 MB, plus `mTLS.key`, `secrets.auto.tfvars`, `terraform.tfstate` | 440 MB |
| `.#` | tracked files only; all of the above absent | 5.5 MB |

`path:` copies the directory verbatim and never consults `.gitignore` — upstream has no equivalent ignore mechanism for non-Git flakes. The Git-tree form copies tracked/staged content, which is exactly the fleet configuration, and it restores `self.rev`/`self.dirtyRev`, so `system.configurationRevision` stops being `null`.

Consequences that follow, and that this change therefore performs:

- `modules/flake/provenance.nix` returns to `source = self.outPath`; the hand-written exclusion list is deleted rather than kept as a second authority over the same rule.
- The plaintext credential files stop being published without being touched in the working tree.

### PSC-2 — The Git index is a precondition, and it is guarded

The Git-tree form reads the repository's Git index. jj keeps that index in sync as part of colocated operation — it stages new files when it first tracks them — so ordinary jj workflows need no extra step. It does **not** repair an entry that an external index command removed: a `git reset` run during Stage 8 removed 19 tracked files from the index (`modules/flake/host-registry.nix`, the underscore host fragments, the archived change documents, `tests/check-internal-contracts.sh`), and evaluation silently used a partial tree until the index was repaired.

Two guards follow:

- A test compares `jj file list -r @` against `git ls-files` and fails when a jj-tracked file is missing from the index, naming the repair (`git add -A`). It runs in `just checks all`.
- The repository guidance states the rule: index-mutating Git commands (`git reset`, `git checkout`, `git stash`) must not be used in this colocated repository; jj operations are the interface.

Rejected alternative: keep `path:.` with a filtered copy (`lib.cleanSourceWith` with an explicit name set). It is robust to index state, but it copies the entire 440 MB working directory into the store on every evaluation, requires a second, hand-maintained filtering authority that duplicates what tracking already encodes, and leaves `configurationRevision` null. It remains the fallback if the index precondition is ever judged too fragile.

### PSC-3 — Filtering is not re-implemented in Nix

No `lib.fileset`, `cleanSourceWith`, or `filterSource` call is added. `lib.fileset.gitTracked` is unusable for a `path:`-resolved flake by design, `toSource` is `cleanSourceWith` underneath, and filtering a store path mangles its name against the unfiltered hash. With the Git-tree form the source is already the tracked set, so the Nix side stays one line.

### PSC-4 — Project policy lives outside openspec-managed files

`AGENTS.md` carries the project-owned sections: the `.#` evaluation rule, the index rule from PSC-2, and the delegation/apply discipline used for OpenSpec implementation work. The OpenSpec-managed integration files under `.pi/`, `.github/`, and `.opencode/` are regenerated wholesale by `openspec update` and therefore cannot be the only home of project policy.

## Risks

| Risk | Mitigation |
| --- | --- |
| The index diverges again and evaluation silently uses a partial tree | `tests/check-flake-source-tracking.sh` fails in `just checks all` with the repair command; the rule is documented in `AGENTS.md` |
| A brand-new file is missed because it is not yet tracked | jj stages files it first sees as added, so any jj command before evaluation is sufficient; the guard reports the divergence if that assumption ever breaks |
| `.#` behaves differently in CI | CI checks out a clean Git tree and already used `path:`; with a clean checkout both forms resolve the same content, and the tracked-only guarantee is what CI wants |
| Switching the bootstrap projection changes reimage behaviour | The projection value changes form only; it is exercised through the same evaluated flake, and a reimage transfers 5.5 MB of tracked source instead of 440 MB of working-directory debris |
| Remediation by editing the index is forgotten after a future incident | The test's failure message carries the exact command, and the guidance names the forbidden commands |
