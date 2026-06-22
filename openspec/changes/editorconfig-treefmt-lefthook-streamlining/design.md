## Context

The repository currently has one formatting gate: `nix fmt` via `nixfmt`, scoped to `.nix` files. Everything else — YAML, TOML, Markdown, shell scripts, OpenTofu, JSON, Python — has no canonical formatter and no enforcement. This means every contributor's editor picks defaults, formatting drift silently accumulates, and diffs accumulate noise from unrelated reformatting when someone does run a formatter manually.

The gap is visible at every level:
- **Editor**: No `.editorconfig` means editors default to tabs-vs-spaces and charset heuristics per file.
- **CLI**: `nix fmt` works for Nix files only; no single command covers the full repo.
- **Pre-commit**: `lefthook.yml` exists but has no formatting hook — drift lands in commits.
- **CI**: No formatting gate — drift merges.

This change adds the missing layers without breaking the existing `nix fmt` contract.

## Goals / Non-Goals

**Goals:**
- Add `.editorconfig` at repo root as the **editor baseline** for indentation, charset, line endings — not as the origin of formatting policy.
- Add `treefmt.toml` as the canonical multi-language formatter configuration covering Nix, YAML, TOML, Markdown, shell, OpenTofu (`.tf`, `.tfvars`), JSON, and Python.
- Keep `nix fmt` as the dedicated Nix formatter; `treefmt` becomes the repo-wide formatting/check surface that dispatches to per-language tools including `nixfmt` for `.nix` files.
- Add a pre-commit formatting hook in `lefthook.yml` that runs `treefmt` on staged files and re-stages fixes.
- Add a CI formatting validation step (`treefmt --fail-on-change`) that fails the build on unformatted files.
- Run a one-shot `treefmt` reformat across the repo to establish the formatted baseline.
- Exclude encrypted (`secrets/`), generated (`generated/`, `pkgs/_sources/generated.*`, `flake.lock`, `.terraform.lock.hcl`), and managed/vendored files from formatting.
- Declare `treefmt.toml` as the **single source of truth** for formatting exclusions — `.editorconfig` carries no exclusion sections, and specs/docs reference the SSOT rather than duplicating it.
- Update operator workflow references (`AGENTS.md`, `justfile` entries, docs) from `nix fmt`-only to treefmt-aware.

**Non-Goals:**
- Removing or replacing `nix fmt` / `formatter` flake output — `nix fmt` stays as the Nix-only formatter.
- Introducing a dedicated flake input or NixOS module for treefmt — formatters come from the existing nixpkgs baseline via devShell packages.
- Formatting CI output files, lockfiles, git submodules, `.hcl` files (`backend.hcl`, `.terraform.lock.hcl`), or third-party vendored content.
- Claiming `tofu fmt` support for `.hcl` files — `tofu fmt` handles `.tf` and `.tfvars` cleanly; the repo's `.hcl` files are local/gitignored (`backend.hcl`) or generated lockfiles (`.terraform.lock.hcl`) and are excluded.
- Adding new formatters for languages the repo doesn't yet use (Rust, Go, etc.) — these can be added later when the repo adopts those languages.

## Decisions

### Decision FMT-1: `.editorconfig` is the repo-root **editor baseline only**

**Chosen:** Add `.editorconfig` at repo root with per-file-type settings covering charset, indentation style/size, line endings, trailing whitespace, and final newline behavior. This is a convenience for editors — it is NOT the origin of formatting policy, exclusion truth, or formatter coverage.

**Rationale:** `.editorconfig` is a zero-dependency standard supported by every major editor (VS Code, Vim/Neovim, JetBrains, Emacs) without plugins. It communicates editor intent without requiring per-contributor configuration. It catches the most common diff-noise sources (tab-vs-space, CRLF-vs-LF) at the editor level before formatters run. It applies sensible defaults uniformly and does not maintain a formatting exclusion list — that responsibility belongs solely to `treefmt.toml`.

**Alternative considered:** Design `.editorconfig` as a co-equal policy source with exclusion mirroring. Rejected — an exclusion mirror creates dual-maintenance drift (violates SSOT and DRY) and `.editorconfig` has no enforcement role in formatting policy.

### Decision FMT-2: `treefmt.toml` is the canonical multi-language formatter config

**Chosen:** Add `treefmt.toml` declaring formatters for each file class the repo uses — `nixfmt` for Nix, `prettier` for YAML/Markdown/JSON, `taplo` for TOML, `shfmt` for shell, `tofu fmt` for OpenTofu (`.tf`, `.tfvars`), `black` for Python.

**Rationale:** `treefmt` is the standard Nix-ecosystem multi-formatter runner. It accepts a single `treefmt.toml` config, dispatches to per-language formatters, and supports `--fail-on-change` for CI. Adding formatters later means adding one line to `treefmt.toml` and one package to the devShell.

**Why `.hcl` is excluded from `tofu fmt`:** `tofu fmt` handles `.tf` and `.tfvars` cleanly. The repo's `.hcl` files are `backend.hcl` (local, gitignored) and `.terraform.lock.hcl` (generated lockfile). Neither should be formatted by `tofu fmt`. `.terraform.lock.hcl` is explicitly listed in the `treefmt.toml` exclusion SSOT.

**Why `black` for Python:** Zero-config, deterministic output, widely available in nixpkgs. The repo has 3 `.py` files today; `black` adds minimal surface and is the idiomatic Python formatter.

**Alternative considered:** A shell script that runs each formatter independently. Rejected — a shell script doesn't provide `--fail-on-change`, global exclusion patterns, or standardized output.

### Decision FMT-3: `nix fmt` stays Nix-only; treefmt wraps it

**Chosen:** The existing `flake.nix` `formatter` output stays as `nixfmt` for `nix fmt`. `treefmt.toml` includes `nixfmt` as one of its formatters, so `treefmt` covers `.nix` files too but the dedicated `nix fmt` path remains unchanged.

```toml
[formatter.nix]
command = "nixfmt"
includes = ["*.nix"]
```

**Rationale:** `nix fmt` is the canonical Nix-only formatting command, used by `nix flake check` and muscle memory. Removing it would break existing workflows. Wrapping it through `treefmt` adds the multi-language layer without touching the existing contract.

### Decision FMT-4: `treefmt.toml` is the exclusive SSOT for formatting exclusions

**Chosen:** `treefmt.toml` is the single source of truth for formatting exclusions. Its `excludes` list carries a `# SSOT` comment. `.editorconfig` does not maintain an exclusion list — it sets editor defaults uniformly. Specs and tasks reference "the exclusion SSOT in `treefmt.toml`" rather than duplicating the full list elsewhere.

Authoritative exclusion list (lives in `treefmt.toml` only):
- `secrets/` — encrypted SOPS files, not plaintext
- `generated/` — generated outputs that shouldn't change without regenerating
- `pkgs/_sources/generated.*` — nvfetcher-generated metadata
- `pkgs/_sources/generated/**` — nvfetcher-generated metadata (subdirectory variant)
- `flake.lock` — Nix lockfile, managed by `nix flake lock`
- `.terraform.lock.hcl` — OpenTofu lockfile, managed by `tofu init`
- Any vendored or third-party directories

**Rationale:** A single authority prevents the drift that inevitably occurs when the same list is maintained in multiple places with no declared primary. The exclusion list is a machine-readable policy (enforced by treefmt in CI), so the config file that enforces it is the natural SSOT. `.editorconfig` has no role in formatting enforcement — its editor defaults apply uniformly to all file classes, and editors do not need exclusion awareness for formatting policy.

**Alternative considered:** Mirror exclusions in `.editorconfig` with a subordinate comment. Rejected — creates maintenance debt where a future contributor adds to one list and forgets the other, violating SSOT and DRY. The `.editorconfig` `unset` pattern for path exclusions is non-standard and provides no enforcement benefit since editors already follow the root defaults.

### Decision FMT-5: Formatting runs in both pre-commit and CI

**Chosen:** `lefthook.yml` gets a `treefmt` pre-commit hook that runs on staged files and re-stages fixes. `.github/workflows/ci.yml` gets a formatting check step that runs `treefmt --fail-on-change` across the repo.

**Rationale:** Pre-commit catches formatting drift at the commit boundary — the developer never pushes unformatted code. CI catches the edge case where the hook was bypassed (`--no-verify`), the contributor doesn't use lefthook, or a merge introduced unformatted content.

### Decision FMT-6: Formatter packages come from the existing nixpkgs baseline, not a dedicated flake input

**Chosen:** Add `treefmt` and formatter packages (`prettier`, `shfmt`, `taplo`, `black`, `opentofu`) to the devShell in `flake.nix`. No new flake input for treefmt.

**Rationale:** All required formatters are available in `nixpkgs`. A dedicated treefmt flake input would add lockfile churn for no benefit — the formatters run outside the Nix build sandbox (developer workstations, CI runners) and don't need to be a build dependency.

## Formatter Boundaries by File Class

| File class          | `.editorconfig` setting  | `treefmt.toml` formatter |
|---------------------|--------------------------|--------------------------|
| `.nix`              | indent_style = space, 2  | nixfmt                   |
| `.yaml` / `.yml`    | indent_style = space, 2  | prettier (yaml)          |
| `.toml`             | indent_style = space, 2  | taplo                    |
| `.md`               | indent_style = space, 2  | prettier (markdown)      |
| `.sh` / `.bash`     | indent_style = space, 2  | shfmt                    |
| `.json`             | indent_style = space, 2  | prettier (json)          |
| `.py`               | indent_style = space, 4  | black                    |
| `.tf` / `.tfvars`   | indent_style = space, 2  | tofu fmt                 |

**Exclusion SSOT:** `treefmt.toml` excludes list. `.editorconfig` applies editor defaults uniformly — no exclusion sections.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| **One-shot reformat noise**: A single large reformat commit touches many files, obscuring history and making `git blame` less useful. | Run the reformat in the change that adds the toolchain and review it separately. Add exclusions (SSOT in `treefmt.toml`) first so managed paths aren't touched. Accept that the baseline commit will be large — it's a one-time cost. |
| **Prettier reformats Markdown in ways that break rendered output**: Prettier's Markdown formatter can change list indentation, line wrapping, or table alignment. | Validate rendered output after reformat. Treat Markdown formatting as non-breaking by default; if a `docs/*.md` file renders incorrectly, add it to exclusions and format manually. |
| **Black reformats Python in unexpected ways**: Black has no configuration options — its output is deterministic but may differ from contributor expectations. | The repo has 3 `.py` files; review the reformat diff. Black output is the canonical Python formatting for this repo going forward. |
| **Pre-commit hook slows commits**: `treefmt` on staged files adds latency to `git commit`. | treefmt is fast per-file. If latency becomes a problem, optimize by restricting the hook to changed files only (already the lefthook default) or wrapping in a timeout. |
| **New contributor doesn't have treefmt installed**: If the hook fails, the contributor may be confused. | The devShell provides all formatter packages. lefthook should degrade gracefully if a formatter is missing — treefmt handles missing commands gracefully. |
| **Exclusion list grows stale**: A contributor removes a managed path from the repo but forgets to clean up the `treefmt.toml` excludes list. | Review exclusions as part of general repo maintenance. The `# SSOT` comment helps reviewers locate the list. A stale exclusion is harmless (unmatched globs are ignored). |

## Migration Plan

1. **Add `.editorconfig`** at repo root with per-file-type editor defaults (indentation, charset, line endings, trimming, final newline). No exclusion sections — editor defaults apply uniformly.
2. **Add `treefmt.toml`** declaring all formatters, exclusion SSOT, and `nixfmt` wrapping.
3. **Update `flake.nix` devShell** to include `treefmt` and all formatter packages.
4. **Update `lefthook.yml`** with a formatting pre-commit hook.
5. **Update `.github/workflows/ci.yml`** with a formatting check step.
6. **Run one-shot `treefmt`** across the repo with exclusions active. Review and commit the baseline.
7. **Update documentation** — `AGENTS.md`, `justfile` entries, `docs/architecture.md` if relevant — to reflect the expanded toolchain.
8. **Verify** both hook and CI fire correctly on a test commit with intentionally unformatted content.

**Rollback strategy:**
- All changes are additive (new files, new hooks) — no existing functionality is removed.
- Rollback removes `.editorconfig`, `treefmt.toml`, the lefthook hook, the CI step, and devShell additions.
- The baseline reformat commit can be reverted with `git revert`.

## Open Questions

None. All design decisions are resolved by the established proposal direction.
