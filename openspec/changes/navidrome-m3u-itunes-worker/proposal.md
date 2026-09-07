## Why

Engine DJ's library is the active authority on `home-forge`; Navidrome owns playlists. The upstream `traktor-m3u-sync` worker now supports an M3U-only import job plus an engine direct-DB export job, making a narrow, observable playlist-sync path ready for live validation. A `playlist-sync` command fetches Navidrome playlists through the Subsonic API as `/music`-rooted M3Us and triggers the import, which chains to the engine export that writes playlists straight into the Engine library database.

Core value: add the smallest reproducible playlist path from Navidrome to Engine DJ without automating retrieval, reintroducing Traktor/NML behavior, or making iTunes XML the primary result.

## What Changes

- Add `Shrub24/traktor-m3u-sync` as a pinned flake input and import its NixOS module for the `home-forge` configuration (the flake module list also carries the import for `oci-melb-1` from the legacy layout; the worker is enabled only on `home-forge`).
- Ship a `playlist-sync` command on `home-forge`: fetch every Navidrome playlist as a `/music`-rooted M3U via the Subsonic API into the worker import dir (stale M3Us replaced, empties skipped), then start the import job.
- Configure the worker jobs on `home-forge`:
  - `import@navidrome`: M3U import rooted at Navidrome's `/music` export prefix, chaining to the engine export via `onSuccess`.
  - `export@engine`: direct-DB export into the Engine library database at `<musicStorageRoot>/Engine Library/Database2/m.db` (guest `M:\Engine Library\Database2\m.db`) with `track_path_prefix=../library`, so tracks resolve relative to the Engine Library dir on `M:`.
  - `export@itunes`: optional/manual sibling iTunes XML export (superseded by the engine-direct path; kept only as an operator fallback).
- Bind the import and engine-export jobs to `dj-library-writers.target` so they are mutually exclusive with the running VM.
- Keep retrieval and services manual; add no timer, watcher, or recurring automation. Credentials come from the Subsonic API (`navidrome_username`/`navidrome_password` secret), never direct Navidrome DB access.
- Document the manual sync/import/export workflow and its live Engine DJ validation gate.

## Capabilities

### New Capabilities
- `playlist-sync`: Batch-export Navidrome playlists as `/music`-rooted M3Us via the Subsonic API into the worker import dir, then start the import job that chains to the engine direct-DB export.

### Modified Capabilities
- `feature-topology`: Home-forge may compose the external manual playlist worker without reviving the removed Traktor feature.
- `media-services`: The canonical home-forge library gains an Engine-library playlist artifact generated from Navidrome M3Us.
- `operations`: Operators gain a documented manual `playlist-sync` workflow and live Engine DJ import validation.

## Impact

- `flake.nix`, `flake.lock`, `hosts/home-forge/default.nix`, and `modules/applications/dj/engine-dj.nix`
- Home-forge worker state under `/srv/data/traktor-m3u-sync` and the Engine library database under `<musicStorageRoot>/Engine Library/Database2`
- Engine DJ documentation and the affected OpenSpec specs
