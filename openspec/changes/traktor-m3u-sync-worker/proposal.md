## Why

The music stack now has a reliable library/ingest foundation, but Traktor playlists remain outside the fleet-managed workflow. Adding `traktor-m3u-sync` as a manually triggered music worker lets us test Traktor NML ↔ M3U playlist synchronization safely before deciding whether any automatic path or timer triggers are warranted.

Core value: introduce playlist synchronization as an observable, reversible, low-automation extension of the existing music stack, without putting Traktor collection state at risk during the first iteration.

## What Changes

- Add `https://github.com/Shrub24/traktor-m3u-sync` as an upstream flake-backed dependency for the music stack, using its `nixosModules.traktor-m3u-sync` module and `services.traktor-m3u-sync.*` option surface where compatible.
- Compose the upstream NixOS/systemd packaging into `applications.music` as an optional/manual worker on `oci-melb-1`.
- Configure initial paths for:
  - Syncthing-sourced Traktor collection file at `/srv/media/traktor/collection.nml`.
  - Separate playlist workspace under `/srv/media/playlists/traktor/`.
  - Export output and import input as distinct directories to avoid accidental feedback loops.
- Expose upstream manual systemd triggers `traktor-m3u-sync-export.service` and `traktor-m3u-sync-import.service`; do not add timers or path watches yet.
- Keep the Traktor-to-NixOS music path mapping configurable with a placeholder operator value for the Traktor-side root until the real NML path layout is verified.
- Document the manual test/iteration workflow and the import sandbox safety model.

## Capabilities

### New Capabilities
- `traktor-playlist-sync`: Declarative/manual integration for Traktor NML ↔ M3U playlist synchronization in the music stack.

### Modified Capabilities
- `media-services`: Music application composition gains a manual playlist synchronization worker and separate playlist workspace paths.
- `operations`: Operators gain a documented manual trigger/test workflow for Traktor export/import before automation is introduced.
- `feature-topology`: The music feature subtree gains another optional leaf service while preserving stable public option namespaces.

## Impact

- Affected code:
  - `flake.nix` / `flake.lock` for the upstream `traktor-m3u-sync` input.
  - `modules/applications/music/default.nix` for composition and initial path wiring.
  - Potential new wrapper module under `modules/services/music/` only if the upstream module needs repo-specific defaults or hardening.
  - `hosts/oci-melb-1/default.nix` for host enablement if the worker is not enabled unconditionally by `applications.music`.
- Affected docs/specs:
  - Add a Traktor playlist sync capability spec.
  - Update media-services, operations, and feature-topology deltas.
- Dependencies:
  - Upstream flake `github:Shrub24/traktor-m3u-sync` and its Python application closure.
- Operational constraints:
  - Initial deployment is manual-trigger only.
  - Import writes to `collection.nml` only through the upstream sandbox/backup behavior.
  - No new public exposure and no new secret scope expected for the first iteration.
