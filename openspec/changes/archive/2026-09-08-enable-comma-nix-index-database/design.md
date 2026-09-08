## Context

See `proposal.md`. The shared shell profile already applies to all three hosts; the flake entrypoint explicitly assembles each host's external modules.

## Goals / Non-Goals

**Goals:**
- Use the upstream pre-built nix-index database for `comma`.
- Apply the same configuration to every fleet host.

**Non-Goals:**
- Local index generation or custom update automation.
- Changes to unrelated shell packages or flake structure.

## Decisions

**COMMA-1 — Use `nix-index-database`'s NixOS module.** It provides the maintained database and native `comma` integration. A locally generated index adds avoidable work and host drift.

**COMMA-2 — Import the module at each `nixosSystem` boundary and enable it in the shared shell profile.** This follows the repository's explicit host assembly while keeping the operator policy in one shared profile.

## Risks / Trade-offs

- **[Additional flake input]** The lock file gains one weekly-updated source → keep it pinned and Renovate-managed like other inputs.
- **[Database freshness follows upstream cadence]** Very recent packages may briefly be absent → accept upstream cadence rather than maintain local indexing machinery.
