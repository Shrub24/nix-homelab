## Why

The repository currently relies on `nix fmt` (backed by `nixfmt`) as its sole formatting gate — Nix-only, editor-optional, and unenforced in CI or pre-commit hooks. This means non-Nix files (YAML, TOML, Markdown, shell, OpenTofu, JSON, Python) have no canonical formatter, every contributor's editor picks its own defaults, and formatting drift silently accumulates until a change batch absorbs a noisy reformat.

We should add a lightweight formatting toolchain that:
- Covers the file types the repo actually uses day-to-day
- Runs in pre-commit hooks so drift never lands
- Runs in CI so drift never merges
- Keeps `nix fmt` as the Nix formatter (unchanged) and wraps everything else through `treefmt`

Core value: Eliminate formatting-as-noise from diffs and reviews while keeping the toolchain simple enough to maintain with the rest of the fleet infrastructure.

## What Changes

- Add `.editorconfig` at repo root as the **editor baseline only** — charset, indentation, line endings for every file class. Must not be treated as the origin of formatting policy.
- Add `treefmt.toml` as the canonical multi-language formatter config — declares formatters for each file class (Nix → `nixfmt`, YAML / Markdown / JSON → `prettier`, TOML → `taplo`, shell → `shfmt`, OpenTofu (`.tf`, `.tfvars`) → `tofu fmt`, Python → `black`). `treefmt.toml` is the **single source of truth** for formatting exclusions.
- Add a `pre-commit` formatting hook to `lefthook.yml` that runs `treefmt` on staged files and stages the fix.
- Add a formatting check step to CI (`ci.yml`) that verifies `treefmt --fail-on-change` and fails the build on unformatted files.
- Update `flake.nix` to add `treefmt` and all new formatter packages to the devShell as native packages (backed by `treefmt.toml`, not via a separate flake input).
- Run one-shot `treefmt` reformat across the repo to establish the baseline.
- Add exclusions for encrypted (`secrets/*`), generated (`generated/*`, `pkgs/_sources/generated.*`, `flake.lock`, `.terraform.lock.hcl`), and vendor-originated files.
- Update canonical documentation references to reflect the expanded formatting toolchain.

## Capabilities

### New Capabilities
- `formatting-toolchain`: Define and enforce cross-language formatting coverage through `.editorconfig` (editor baseline only), `treefmt.toml` (canonical formatter config + exclusion SSOT), and `lefthook` pre-commit hooks.

### Modified Capabilities
- `repository-structure`: Add `.editorconfig` as an expected repo-root editor-baseline file and establish `treefmt.toml` as the exclusion SSOT.
- `operations`: Add CI formatting validation as a canonical repository check and update operator workflow references (`AGENTS.md`, `justfile`, docs) from `nix fmt`-only to `treefmt`-backed formatting.

## Impact

- Affected code:
  - `.editorconfig` (new)
  - `treefmt.toml` (new)
  - `lefthook.yml` (add formatting hook)
  - `flake.nix` (add `treefmt` and formatter packages to devShell, update formatter expression)
  - `.github/workflows/ci.yml` (add formatting check step)
- Affected documentation:
  - `AGENTS.md` (update formatting tool references)
  - `docs/*.md` as relevant (update architecture/operations references)
  - `openspec/specs/operations/spec.md` (add CI formatting check requirement)
  - `openspec/specs/repository-structure/spec.md` (add `.editorconfig` expectation)
- One-shot reformat of majority of non-excluded files (expect large single commit, minimal ongoing noise)
- Exclusions (SSOT in `treefmt.toml`): `secrets/`, `generated/`, `pkgs/_sources/generated.*`, `flake.lock`, `.terraform.lock.hcl`, and any vendored or third-party files
