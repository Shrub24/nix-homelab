## Context

The notification daemon currently folds `monitor.services` into `systemd.services`. OCI still names Beets units that moved to home-forge, creating static fragments without an `ExecStart`; the real home-forge unit has only its feature-owned retry/failure hooks. The contract must compose with existing unit definitions without replacing their hooks.

## Goals / Non-Goals

**Goals:**
- MON-1: monitoring participation is declared by the unit owner;
- MON-2: per-event policy is typed and additive;
- MON-3: references to nonexistent service implementations fail evaluation;
- MON-4: existing Beets retry and failure notification behavior remains intact.

**Non-Goals:**
- changing the daemon API, message routing, or topics;
- extracting notifications to another repository;
- renaming systemd units.

## Decisions

### MON-1 — Use a typed unit attribute set

Expose `monitor.units.<unit>` with explicit event booleans rather than another list. This preserves additive Nix module merging and allows owners to request only meaningful lifecycle events. A compatibility list is not retained because it would preserve two authorities.

### MON-2 — Require a real service implementation

After module merging, each enabled monitor entry must correspond to a `systemd.services.<unit>` definition with a non-empty service implementation (`serviceConfig.ExecStart` or `script`). This rejects phantom fragments while allowing generated and native units. The check occurs before hooks are injected or uses a pre-hook implementation predicate so the monitor cannot satisfy its own assertion.

### MON-3 — Owners contribute registrations

Music contributes Beets units, OmniRoute keeps its own contribution, and operational owners contribute their units. Hosts retain only genuinely host-local units. Existing unit hooks are appended using module-list semantics; they are never replaced.

### MON-4 — Validate evaluated behavior

Capture structured service definitions before and after. Required assertions include: OCI has no Beets service fragments; home-forge's Beets units retain retry/failure hooks and gain only declared generic hooks; all monitor targets have real implementations.

## Risks / Trade-offs

- **Native units may not expose `ExecStart` in the expected shape** → constrain the first migration to repository-owned units and test every current target.
- **Hook merging could change ordering** → compare evaluated `unitConfig` and `serviceConfig` arrays and preserve existing owner hooks.
- **Two-step bootstrap could omit the daemon** → contributions remain valid only where the explicitly selected `notify` aspect supplies the contract.

## Migration Plan

1. Capture current per-host monitor targets and service definitions.
2. Introduce the typed contract and migrate all current registrations in one evaluation-safe batch.
3. Remove host reverse indexes and the old list option.
4. Validate all hosts, then deploy home-forge first and confirm Beets hooks.

Rollback restores the old option and registrations as one change; no persistent state migrates.
