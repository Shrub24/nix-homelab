## Why

The live home-forge music tree mixes audio files, generated playlists, Engine DJ state, and stale migration directories under overlapping `media` and `library` names. Physical paths are also duplicated across fleet policy, application options, host configuration, and leaf defaults, making the effective storage contract unclear and easy to drift.

**Core Value:** Give the music stack one host-selected storage root with predictable application-owned subdirectories, while preserving service state, backup boundaries, and a simple single-drive Engine DJ view.

## What Changes

- **BREAKING:** Make home-forge select `/srv/storage/media/music` as the music application's storage root, with `library`, `playlists`, `inbox`, `quarantine`, `.versions`, and the bind-presented `Engine Library` as sibling paths.
- Share the music application root as the Engine DJ guest's single writable `M:` drive.
- Remove physical music-root policy from `policy/globals.nix`; the host supplies required application and DJ path options instead.
- Remove hardcoded shared-path defaults from enabled music leaf services; the application composition root injects every required shared path.
- Preserve `/srv/data/<service>` as the service-state boundary and keep the Engine DJ database physically at `/srv/data/engine-dj/library`.
- Remove confirmed-empty pre-cutover directories and the stale Beets pre-import copy during the controlled migration; leave `tagged` data unchanged for later Beets reorganization.
- Repair the setup-media PowerShell script for Windows PowerShell 5.1 while retaining `New-Service` and `Start-Service` for VirtIO-FS service management.
- Deliberately leave the `traktor-m3u-sync` output-path wiring unchanged because that integration is being replaced separately.

Key constraints:

- Do not modify encrypted secrets or secret values.
- Quiesce writers and the Windows VM before moving or unmounting live paths.
- Preserve Syncthing folder IDs and Beets/Navidrome databases; paths move on the same filesystem.
- Keep future media categories (`photos`, `video`) outside the music subtree and outside the DJ guest share.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `media-services`: Define host-owned application storage roots, application-derived music subtrees, explicit leaf path injection, and the single-root Engine DJ share boundary.

## Impact

- Nix modules: `modules/applications/music/`, `modules/applications/dj/engine-dj.nix`, and music leaf services.
- Host composition: `hosts/home-forge/default.nix`.
- Policy: removes physical music paths from `policy/globals.nix`.
- Guest setup media: `pkgs/windows-dj-setup/setup.ps1` and its runbook.
- Runtime: same-filesystem home-forge directory moves, service restarts/rescans, Syncthing re-indexing, VM restart, and Engine DJ track re-import under `M:\library`.
