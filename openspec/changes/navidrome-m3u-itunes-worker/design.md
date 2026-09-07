## Context

See proposal.md. The upstream revision `c345ed02` exposes an M3U-only import job and an engine direct-DB export job (plus an optional iTunes export), separates the Linux path check from the emitted location, and supports `onSuccess` job chaining. Navidrome supplies playlists as M3Us; the `playlist-sync` command fetches them through Navidrome's Subsonic API and stages `/music`-rooted M3Us into the import dir. Engine DJ sees the home-forge library as `M:`.

## Goals / Non-Goals

**Goals:**
- Produce Engine-valid track locations without leaking Linux paths into the Engine database.
- Keep the worker manual, local, and reversible; fetch via the Subsonic API, not direct DB access.
- Keep application composition unchanged; this is a narrow host-local external module.

**Non-Goals:**
- Automate Navidrome retrieval, run recurring automation, handle bidirectional Engine sync, or configure Traktor/NML.
- Make iTunes XML the primary result; it remains an optional/manual sibling export.

## Decisions

- **PL-1:** Pin the upstream flake revision and pass its package explicitly because it is not in nixpkgs. The module is enabled only on `home-forge`; the flake module list also carries the import for `oci-melb-1` from the legacy layout, where the worker stays inert.
- **PL-2:** Use `/music` as the M3U source root and the Engine library database as the export target. The fetcher normalizes both library-relative paths and absolute paths rooted at `<musicStorageRoot>/library` into `/music/<relative>`, emitted exactly once (never `/music/library/...`); paths outside the library root or containing any `..` segment are skipped fail-closed.
- **PL-3:** Store SQLite state and inbound M3Us under `/srv/data/traktor-m3u-sync`, outside the media library; the engine export writes playlists directly into the Engine library database at `Engine Library/Database2/m.db` beneath the music root, so they never surface as audio in Navidrome or Syncthing sync scope.
- **PL-4:** Leave `wantedBy`, timers, and path triggers empty. Operators explicitly run `playlist-sync`, then validate in Engine DJ.
- **PL-5:** Credentials come from the Subsonic API (`navidrome_username`/`navidrome_password` secret) via the `playlist-sync-env` SOPS template; the worker never reads the Navidrome DB directly.
- **PL-6:** Navidrome's `DefaultReportRealPath=true` covers new clients; the existing `playlist-sync` player must be toggled to report real paths in the Navidrome UI (per-player setting) or the API returns music-folder-relative paths instead.
- **PL-7:** The import and engine-export jobs bind to `dj-library-writers.target` (`BindsTo` + `After`), which conflicts with the VM unit, so the import→export chain cannot write the Engine DB while the VM runs.

## Risks / Trade-offs

- [Navidrome API path shape changes] → the fetcher normalizes both absolute and relative shapes and skips off-root or `..`-containing paths; no source data is mutated.
- [Engine DB interpretation differs] → one live import is the acceptance gate; the Engine DB and worker state can be removed independently.
- [Upstream update changes the module contract] → flake lock pin plus target evaluation validates the configured option surface.

## Migration Plan

1. Deploy home-forge with inactive manual units and empty state/input directories.
2. Run `playlist-sync` to fetch `/music`-rooted M3Us into the import dir and start the import job; the engine export chains via `onSuccess`.
3. Validate the synced playlists in Engine DJ against `M:\library`.
4. Roll back by removing the worker state and reverting the Engine database; no media or Navidrome state is changed.
