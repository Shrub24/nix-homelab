# Restrict the provenance source copy and make local flake evaluation trustworthy

## Why

`modules/flake/provenance.nix` publishes the flake's own source to `/etc/nixos-source` with `environment.etc."nixos-source".source = self.outPath`. Which content that is depends entirely on how the flake is referenced:

| reference | copied content | measured |
| --- | --- | --- |
| `path:.` | the raw working directory; `.gitignore` is not consulted | 440 MB: `.git` 104 MB, `opentofu/` 161 MB (incl. `.terraform` providers), `.hp-forge-esp-backup` 86 MB, `.opencode` 57 MB, `.jj` 20 MB, `.qmd` 8.8 MB |
| `.#` (git tree) | tracked/staged files only | 5.5 MB, with `.git`, `.jj`, `.qmd`, `.opencode`, `.hp-forge-esp-backup`, `mTLS.key`, `secrets.auto.tfvars` and `terraform.tfstate` all absent |

The `path:` form therefore ships VCS metadata, vendored bulk, and plaintext credential files into every host's world-readable `/etc/nixos-source`. Those credential files are already exposed today, which makes this a security fix and not only a size fix.

A second, independent defect made the first one hard to see. `just deploy`, `just deploy-dry`, `just prebuild-*` and the documented cutover command resolved the flake as `.#`, and in this jj-colocated repository `.#` was evaluating a **partial** tree: jj tracks 835 files while the Git index held only 816 of them, and the 19 missing entries were exactly the files created during Stage 8 (`modules/flake/host-registry.nix`, the underscore host fragments, the archived change documents, `tests/check-internal-contracts.sh`). Reproduced directly:

```
nix eval --raw .#deployHosts.edgeHost   → error: The option `nixos' does not exist …
                                          (source: …-source missing host-registry.nix)
nix eval --raw path:.#deployHosts.edgeHost → la-admin-1
```

## What changes

- Local flake references use the Git-tree form `.#`, which resolves tracked content only: the published source becomes the fleet configuration, and `system.configurationRevision` — currently `null` because `path:` flakes have no `rev`/`dirtyRev` — becomes meaningful again.
- `modules/flake/provenance.nix` returns to `source = self.outPath`; the hand-written exclusion list is deleted, because tracking is the single filtering authority.
- A guard test fails when a jj-tracked file is missing from the Git index, naming the repair, so the partial-tree failure cannot recur silently.
- `AGENTS.md`, the canonical documentation, and the debt ledger record the rule and the change.

## Scope

**In scope:** `modules/flake/provenance.nix`; local flake references in `justfile`, `.github/workflows/deploy-host.yml`, and the operator command in `docs/architecture.md`; the bootstrap projection value in `modules/flake/registry.nix` and its test anchors; a new index-integrity guard wired into `just checks all`; `AGENTS.md`; `docs/decisions.md`; the canonical docs and ledger entries about provenance; the stale project context in `openspec/config.yaml`.

**Out of scope:** changing what CI deploys; changing secret values, `.sops.yaml` readership, or encrypted files; removing the plaintext credential files from the working tree (operator-owned); rotating the already-exposed credentials.

## Constraints

- The Git index must stay complete for jj-tracked files; external index manipulation (`git reset`, `git checkout`) is what produced the 19-entry divergence and must be named as forbidden in the repository guidance.
- The guard must be cheap and must fail with an explicit repair instruction rather than silently skipping.
- Provenance semantics stay: `/etc/nixos-source` exists on every host and describes the deployed configuration.
- No new flake input and no new dependency for filtering.
