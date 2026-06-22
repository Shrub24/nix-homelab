## 1. Configuration files — `.editorconfig` + `treefmt.toml`

- [x] 1.1 Add `.editorconfig` at repo root — charset `utf-8`, indent `space`/`2` for Nix/YAML/TOML/Markdown/shell/JSON/TOFU, `space`/`4` for Python, `insert_final_newline = true`, `trim_trailing_whitespace = true`. Editor defaults only — no path exclusion sections, no `unset` overrides. Formatting exclusions belong solely in `treefmt.toml`. Add a brief comment noting `.editorconfig` is editor baseline only.

- [x] 1.2 Add `treefmt.toml` at repo root — declare formatters:
  - `nixfmt` for `.nix`, `prettier` for `.yaml`/`.yml`/`.md`/`.json`, `taplo` for `.toml`, `shfmt` for `.sh`/`.bash`, `black` for `.py`, `tofu` for `.tf`/`.tfvars` (NOT `.hcl`).
  - Excludes SSOT: `["secrets/**", "generated/**", "pkgs/_sources/generated.*", "pkgs/_sources/generated/**", "flake.lock", ".terraform.lock.hcl"]`.
  - Add `# SSOT` comment on the excludes section. `.terraform.lock.hcl` is explicitly named (not just caught by a glob).

## 2. Flake tooling — devShell formatter packages

- [x] 2.1 Add `treefmt`, `prettier`, `taplo`, `shfmt`, `black`, and `opentofu` (if not already present) to `flake.nix` devShell `packages` (in the `mkDevShell` `with pkgs;` block). Keep existing `nixfmt` — it serves both `nix fmt` and `treefmt` dispatch.

## 3. Pre-commit hook — lefthook formatting

- [x] 3.1 Add a `treefmt` pre-commit command to `lefthook.yml` — glob matches all tracked file classes, runs `treefmt $STAGED_FILES`, `stage_fixed: true`. Place it before existing hooks so formatting runs early.

## 4. CI — formatting validation step

- [x] 4.1 Add a `Check formatting` step to `.github/workflows/ci.yml` in the `validate` job, after the `Validate flake wiring` step — runs `nix develop --command treefmt --fail-on-change` (or equivalent devShell-entering invocation). Confirm it fails with non-zero exit when unformatted files exist and prints paths.

- [x] 4.2 Keep formatting validation local-only in CI — the `validate` job installs Nix without invoking `.github/actions/setup-nixbuild`, and nixbuild.net setup remains limited to jobs that actually build/deploy host profiles.

## 5. Just command surface

- [x] 5.1 Add `just fmt` target — runs `treefmt` (repo-wide format) and `just fmt-check` target — runs `treefmt --fail-on-change` (read-only check). Place in the root `justfile` with a brief comment describing each.

## 6. Documentation updates

- [x] 6.1 Update `AGENTS.md` — replace the "`nix fmt` only" entry in the Development Tools table with both `nix fmt` (Nix-only) and `treefmt` (cross-language). Add a note explaining the relationship: `treefmt` wraps `nixfmt` for `.nix` files and dispatches `prettier`/`taplo`/`shfmt`/`black`/`tofu` for the rest. Reference `treefmt.toml` as the exclusion SSOT.

- [x] 6.2 Update canonical specs — add `.editorconfig` requirement to `openspec/specs/repository-structure/spec.md`, add formatting CI step requirement to `openspec/specs/operations/spec.md`. These are the upstream versions of the delta specs already written in this change.

## 7. Exclusion SSOT verification

- [x] 7.1 Verify the `treefmt.toml` exclusion list (the SSOT) covers: `secrets/`, `generated/`, `pkgs/_sources/generated.*`, `pkgs/_sources/generated/**`, `flake.lock`, `.terraform.lock.hcl`. Add a `# SSOT` comment to the `treefmt.toml` excludes section. Confirm `.editorconfig` has no exclusion sections — it is editor-defaults only.

## 8. One-shot repo reformat

- [x] 8.1 Run `treefmt` across the full repo (exclusions active). Review the diff — verify `secrets/`, `generated/`, `pkgs/_sources/generated.*`, `flake.lock`, `.terraform.lock.hcl` are untouched. Commit the baseline reformat as part of this change.

## 9. Validation

- [x] 9.1 Run `treefmt --fail-on-change` — confirm zero unformatted files post-reformat.

- [x] 9.2 Run `nix flake check --no-build` — confirm evaluation passes (flake checks, formatter output, devShell evaluation).

- [ ] 9.3 Test pre-commit hook: stage an intentionally unformatted file (`*.nix`, YAML, or `*.py`), run `lefthook run pre-commit`, confirm it formats and re-stages. Then test bypass with `--no-verify` — confirm CI catch.

- [ ] 9.4 Update `tasks.md` checkboxes to reflect completion.
