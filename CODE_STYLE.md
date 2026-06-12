# Code Style

## Core Principles

- Write concise, idiomatic, modern Python.
- Keep code consistent, explicit, and modular at subsystem boundaries.
- Prefer SSOT and DRY over duplicated branching or repeated literals.
- Avoid YAGNI code, speculative abstractions, and placeholder complexity that is not needed by the active change.

## Structure

- Prefer small functions and small classes with focused responsibilities.
- Keep control flow flat; extract helpers instead of nesting deeply.
- Use explicit typing by default.
- Prefer declarative configuration over scattered constants and ad-hoc environment reads.

## Validation And Error Handling

- Validate at I/O boundaries.
- Do not repeatedly revalidate internal values that should already be trusted.
- Fail fast for impossible or unexpected states.
- Do not catch, hide, or log unexpected exceptions unless the failure is an explicitly handled runtime condition.

## Comments And Documentation

- Let code self-document whenever possible.
- Add comments only when they explain a non-obvious choice, boundary, or trade-off.
- Avoid narration comments and redundant docstrings.
- Document technical debt and intentional deviations explicitly.

## Tooling

- Use the Nix dev environment for local development.
- Use `just` recipes for common workflows.
- Do not suppress linter or type-checker issues unless there is explicit agreement.
