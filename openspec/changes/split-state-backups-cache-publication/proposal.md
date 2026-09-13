## Why

The current `backups` aspect combines mutable state recovery with immutable Nix closure publication. These capabilities already have distinct data models, credentials, failure semantics, and likely future ownership, so present-day co-selection should be expressed as policy rather than shared implementation ownership.

**Core Value:** State recovery and cache distribution remain independently portable, reviewable, and revocable even when every current host selects both.

## What Changes

- Replace the `backups` placement aspect with independent `state-backups` and `cache-publisher` aspects.
- Make `state-backups` own restic repositories, mutable-state contributions, consistency/export policy, retention, restore contracts, and backup monitoring.
- Make `cache-publisher` own the Niks3 upload client, activation-triggered closure publication, cache write credentials, filtering, and publication observability.
- Keep both aspects explicitly selected on all current hosts to preserve behavior; do not add a compatibility bundle or transitive selection.
- Move each contributor toward its semantic feature/domain source path and keep cache publication suitable for later evidence-based extraction into `nix-fleet`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `state-backups`: Remove Nix closure upload ownership and define the independent state-recovery placement capability.
- `cache-push-workflow`: Define cache publication as an independent placement capability with its own secret and failure contract.
- `feature-topology`: Require composition by explicit co-selection when capabilities have distinct security, state, and lifecycle boundaries.
- `fleet-infrastructure`: Replace the combined operational aspect selection with independent state-backup and cache-publication selections.

## Impact

- Affects `modules/flake/backups.nix`, private backup/upload leaves, registry selections, secret contracts, monitoring contributions, checks, and docs.
- No restic scope, schedule, repository, Niks3 endpoint, token path, closure filter, or activation behavior changes.
- No compatibility `backups` bundle is retained; rollback is a direct restoration of the prior contributor and host selections.
