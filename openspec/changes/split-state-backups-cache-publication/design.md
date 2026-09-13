## Context

The `backups` aspect imports restic state backup, Niks3 upload-client, and post-deploy closure publication. All hosts currently need both, but the capabilities differ in state model, credentials, recovery semantics, and likely repository ownership.

## Goals / Non-Goals

**Goals:**
- OPSPLIT-1: make state recovery and cache publication independently selectable;
- OPSPLIT-2: preserve current behavior through explicit co-selection;
- OPSPLIT-3: give each capability its own secrets, monitoring, and source ownership;
- OPSPLIT-4: leave cache publication ready for later extraction.

**Non-Goals:**
- changing backup coverage, schedules, retention, or restore procedures;
- changing Niks3 server/read architecture or publication triggers;
- extracting to `nix-fleet` now;
- retaining a compatibility bundle.

## Decisions

### OPSPLIT-1 — Two public aspects

`state-backups` imports and enables only mutable-state backup behavior. `cache-publisher` imports the upstream upload module plus upload-client/post-deploy implementations. Host policy explicitly selects both where required.

### OPSPLIT-2 — Separate bootstrap gates and secrets

Each aspect independently derives the conventional host secret path and gates only its own capability. Existing key names and paths remain unchanged. This permits future independent revocation without changing ciphertext during the split.

### OPSPLIT-3 — Owner-specific monitoring

Backup units contribute monitoring from `state-backups`; upload/post-deploy units contribute from `cache-publisher`, using the feature-owned monitoring contract. Neither imports notifications; named assertions enforce required co-selection only when monitoring is needed.

### OPSPLIT-4 — No compatibility aspect

Keeping `backups` as a bundle would preserve ambiguous ownership and a second selection authority. Registry updates are atomic and tests assert the old aspect is absent.

## Risks / Trade-offs

- **One capability accidentally disabled** → compare all three hosts' units, timers, secrets, and activation scripts before/after.
- **Shared secret file obscures independent security domains** → preserve current file paths now; independent key rotation can follow without coupling aspect ownership.
- **Activation ordering changes** → freeze unit dependencies and activation-script text.

## Migration Plan

1. Capture current state-backup and cache-publication observables for every host.
2. Publish both aspects and co-select them atomically.
3. Move implementation ownership and delete `backups`.
4. Validate closure/structured equivalence and deploy one host at a time.

Rollback restores the single aspect and previous selections; no persistent data changes.
