# Delta Spec: Formatting Toolchain

## Purpose

Define the formatting toolchain contracts for multi-language code formatting across the repository: editor baseline, CLI formatter, pre-commit enforcement, and CI validation.

## ADDED Requirements

### Requirement: Editor behavior SHALL be guided by repo-root `.editorconfig` (editor baseline only)

The repository SHALL include an `.editorconfig` file at the root that declares baseline editor settings (charset, indentation style/size, line endings, trailing whitespace, final newline) for every file class the repository uses. This is a convenience for editors — it is NOT the source of formatting policy or exclusion truth. The SSOT for exclusions is `treefmt.toml`.

#### Scenario: New contributor opens a file without editor configuration

- **WHEN** a contributor opens a file in the repository in an editor that supports `.editorconfig`
- **THEN** the editor respects the indentation style, charset, and line ending settings declared in `.editorconfig`
- **AND** the contributor does not need to configure editor settings manually for this repository

#### Scenario: Managed file is opened for editing

- **WHEN** a file under `secrets/`, `generated/`, `pkgs/_sources/generated.*`, `flake.lock`, or `.terraform.lock.hcl` is opened
- **THEN** `.editorconfig` applies the same root defaults to these files as to all other files — editor baselines are uniform and do not carry formatting exclusion awareness
- **AND** formatting exclusion is enforced solely by `treefmt.toml`, not by `.editorconfig`

### Requirement: Cross-language formatting SHALL be driven by `treefmt.toml`

The repository SHALL include a `treefmt.toml` configuration file that declares the canonical formatter for each file type and supports `--fail-on-change` for CI validation.

#### Scenario: Repo-wide formatting is requested

- **WHEN** a contributor or CI runs `treefmt` with no additional arguments
- **THEN** the following file classes are formatted by their declared formatter:
  - `.nix` → `nixfmt`
  - `.yaml` / `.yml` → `prettier` (or equivalent YAML formatter)
  - `.toml` → `taplo`
  - `.md` → `prettier` (or equivalent Markdown formatter)
  - `.sh` / `.bash` → `shfmt`
  - `.json` → `prettier` (or equivalent JSON formatter)
  - `.py` → `black`
  - `.tf` / `.tfvars` → `tofu fmt`
- **AND** `.nix` formatting is handled by `nixfmt` through the same `treefmt` dispatch

#### Scenario: Managed files are excluded from formatting

- **WHEN** `treefmt` is run across the repository
- **THEN** files under `secrets/`, `generated/`, `pkgs/_sources/generated.*`, `pkgs/_sources/generated/**`, `flake.lock`, and `.terraform.lock.hcl` are excluded
- **AND** excluded files are not read, formatted, or reported by treefmt
- **AND** this exclusion list is the SSOT — no other config file maintains a separate exclusion list

### Requirement: Formatting exclusions SHALL have `treefmt.toml` as the exclusive single source of truth

The `treefmt.toml` `excludes` list SHALL be the sole authoritative source for formatting exclusions. `.editorconfig` SHALL NOT maintain an exclusion list — it applies editor defaults uniformly to all file classes without path-specific overrides for formatting policy. Specs and tasks SHALL reference the SSOT rather than duplicating the full exclusion list elsewhere.

#### Scenario: An exclusion needs to be added

- **WHEN** a new file class requires formatting exclusion
- **THEN** the exclusion is added to the `treefmt.toml` `excludes` list only (the SSOT)
- **AND** `.editorconfig` is not updated — it has no exclusion list to maintain
- **AND** the exclusion rationale is documented in the change description

#### Scenario: Exclusion list consistency is verified

- **WHEN** a reviewer inspects the formatting configuration
- **THEN** `treefmt.toml` is identified as the sole authoritative exclusion list
- **AND** `.editorconfig` carries no exclusion sections — consistency means verifying `treefmt.toml` is the only place exclusions are declared

### Requirement: `nix fmt` SHALL remain the dedicated Nix-only formatter

The existing `flake.nix` `formatter` output SHALL continue to produce `nixfmt` for `nix fmt` behavior. The `treefmt.toml` SHALL wrap `nixfmt` internally so `treefmt` also covers `.nix` files without replacing the dedicated `nix fmt` path.

#### Scenario: Contributor runs `nix fmt` on a Nix file

- **WHEN** a contributor runs `nix fmt path/to/file.nix`
- **THEN** the file is formatted by `nixfmt` through the existing flake `formatter` output
- **AND** the result is identical to running `treefmt` on the same file

#### Scenario: Contributor runs `treefmt` on a Nix file

- **WHEN** a contributor runs `treefmt path/to/file.nix`
- **THEN** the file is formatted by `nixfmt` through the `treefmt.toml` formatter dispatch
- **AND** the result is identical to running `nix fmt` on the same file

### Requirement: Pre-commit formatting hook SHALL enforce `treefmt` on staged files

The `lefthook.yml` SHALL include a pre-commit hook that runs `treefmt` on staged files and re-stages any formatting fixes before the commit completes.

#### Scenario: Pre-commit hook formats a staged file

- **WHEN** a contributor stages and commits files
- **THEN** the lefthook pre-commit hook runs `treefmt` on all staged files matching included patterns
- **AND** any formatting changes are re-staged into the same commit
- **AND** the commit proceeds only after treefmt finishes formatting and lefthook re-stages any fixes

#### Scenario: Pre-commit hook is bypassed

- **WHEN** a contributor commits with `git commit --no-verify`
- **THEN** the formatting hook does not run
- **AND** the CI formatting gate catches any unformatted files at push/merge time

### Requirement: CI SHALL validate formatting via `treefmt --fail-on-change`

The CI workflow SHALL include a formatting validation step that fails the build if any formatted file class has unformatted content.

#### Scenario: CI formatting check passes

- **WHEN** CI runs on a pull request or push where all formatted files are clean
- **THEN** the formatting check step exits zero
- **AND** the workflow continues to subsequent check steps

#### Scenario: CI formatting check fails

- **WHEN** CI runs on a pull request or push containing unformatted files
- **THEN** the formatting check step exits non-zero
- **AND** the workflow reports the failed step and lists unformatted file paths
- **AND** the contributor can reproduce locally with `treefmt --fail-on-change`

### Requirement: Formatter packages SHALL be provided through the devShell, not a dedicated flake input

All formatter packages (`treefmt`, `nixfmt`, `prettier`, `shfmt`, `taplo`, `black`, `opentofu`) SHALL be added to the devShell `nativeBuildInputs` or equivalent in `flake.nix`, sourced from the existing nixpkgs baseline.

#### Scenario: Developer opens a devShell

- **WHEN** a contributor enters the devShell via `nix develop` or `direnv`
- **THEN** `treefmt` and all declared formatter packages are available on `$PATH`
- **AND** the contributor can run `treefmt` without additional installation steps

### Requirement: One-shot repo reformat SHALL establish the formatted baseline

The implementation of this specification SHALL include a one-shot `treefmt` reformat across all non-excluded files to establish a consistent formatting baseline.

#### Scenario: Baseline reformat is applied

- **WHEN** the formatting toolchain is introduced in a change
- **THEN** `treefmt` is run across the full repository (excluding managed paths per the `treefmt.toml` SSOT)
- **AND** all formatting changes are committed in the same change as the toolchain introduction
- **AND** after the baseline reformat, `treefmt --fail-on-change` exits successfully with zero unformatted files

#### Scenario: Post-baseline drift is detected

- **WHEN** `treefmt --fail-on-change` is run after the baseline reformat
- **THEN** any file modified after the baseline that deviates from the declared formatter output is reported
