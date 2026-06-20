# Delta Spec: Repository Structure

## ADDED Requirements

### Requirement: `.editorconfig` SHALL be present at repo root (editor baseline only)

The repository SHALL include an `.editorconfig` file at the repository root declaring baseline editor behavior (charset, indentation style/size, line endings) for all file classes the repository uses. This is an editor convenience — it is NOT the source of formatting policy. The SSOT for exclusions is `treefmt.toml`.

#### Scenario: Repository structure is audited

- **WHEN** the repository root is inspected
- **THEN** `.editorconfig` is present as a committed file
- **AND** it contains editor-default settings for every file class the repo uses (`.nix`, YAML, TOML, Markdown, shell, JSON, Python, OpenTofu `.tf`/`.tfvars`, plus `.hcl` for editor indentation only)
- **AND** it does not carry path-specific exclusion sections — formatting exclusion policy is solely in `treefmt.toml`

### Requirement: `treefmt.toml` SHALL be present at repo root (canonical formatter config + exclusion SSOT)

The repository SHALL include a `treefmt.toml` file at the repository root declaring the canonical cross-language formatter configuration and exclusion patterns. This file is the single source of truth for formatting exclusions.

#### Scenario: Repository structure is audited

- **WHEN** the repository root is inspected
- **THEN** `treefmt.toml` is present as a committed file
- **AND** it declares formatter entries for `.nix`, YAML, TOML, Markdown, shell scripts, JSON, Python, and OpenTofu (`.tf`, `.tfvars`)
- **AND** its `excludes` list (the SSOT) covers `secrets/`, `generated/`, `pkgs/_sources/generated.*`, `pkgs/_sources/generated/**`, `flake.lock`, and `.terraform.lock.hcl`
- **AND** the `excludes` section has a comment identifying it as the SSOT
