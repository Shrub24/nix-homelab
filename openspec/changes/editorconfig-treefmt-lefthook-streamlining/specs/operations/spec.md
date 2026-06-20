# Delta Spec: Operations

## ADDED Requirements

### Requirement: CI SHALL validate cross-language formatting via `treefmt`

CI validation workflows SHALL include a formatting check step that runs `treefmt --fail-on-change` across the repository and fails the workflow if any formatted file class has unformatted content.

#### Scenario: Formatting check passes in CI

- **WHEN** CI runs on a pull request or push to any branch class
- **THEN** the formatting check step runs `treefmt --fail-on-change` across the working tree
- **AND** the step exits successfully if all formatted files are clean

#### Scenario: Formatting check fails in CI

- **WHEN** CI runs on a pull request or push containing unformatted files
- **THEN** the formatting check step exits non-zero and lists unformatted file paths
- **AND** the step output is actionable — the contributor can reproduce locally with `treefmt --fail-on-change`

#### Scenario: Formatter packages are available in CI

- **WHEN** CI runner executes the formatting check step
- **THEN** all formatter packages declared in `treefmt.toml` are available via the devShell
- **AND** no additional CI-level tool installation is required beyond entering the devShell

### Requirement: Operator workflow references SHALL reflect the expanded toolchain

Operator-facing documentation (`AGENTS.md`, `justfile` entries, architecture docs) SHALL reference `treefmt` as the canonical cross-language formatting command alongside the existing `nix fmt` for Nix-only formatting.

#### Scenario: Operator reads formatting workflow in `AGENTS.md`

- **WHEN** an operator reviews `AGENTS.md` for repository formatting guidance
- **THEN** the documented formatting commands include `treefmt` (repo-wide) and `nix fmt` (Nix-only)
- **AND** the relationship between the two commands is explained:
  - `treefmt` covers Nix, YAML, TOML, Markdown, shell, JSON, Python, and OpenTofu (`.tf`, `.tfvars`)
  - `nix fmt` remains the canonical Nix-only formatter backed by `nixfmt`
  - Formatting exclusions are defined by `treefmt.toml` (SSOT — see `treefmt.toml` `excludes` section)
