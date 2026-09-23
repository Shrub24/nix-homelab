## Purpose

Batch-export Navidrome playlists as `/music`-rooted M3Us via the Subsonic API into the worker import dir, then start the import job that chains to the engine direct-DB export on `home-forge`.

## ADDED Requirements

### Requirement: Home-forge SHALL provide a `playlist-sync` command
Home-forge SHALL ship a `playlist-sync` command that fetches every Navidrome playlist as a `/music`-rooted M3U through the Subsonic API into the declared import dir (stale M3Us replaced, empty playlists skipped) and then starts the import job. The worker SHALL use the Subsonic API credentials from the `navidrome_username`/`navidrome_password` secret and SHALL NOT read the Navidrome database directly.

#### Scenario: Operator syncs Navidrome playlists
- **WHEN** the operator runs `playlist-sync` on `home-forge`
- **THEN** each Navidrome playlist is staged as a `/music`-rooted M3U in the import dir
- **AND** the import job is started
- **AND** no playlist, media file, or Navidrome database is modified by the worker

### Requirement: M3U paths SHALL normalize to `/music/<relative>` exactly once
The fetcher SHALL accept both library-relative paths and absolute paths rooted at `<musicStorageRoot>/library` and emit `/music/<relative>` exactly once, never `/music/library/...`. Paths outside the library root or containing any `..` path segment SHALL be skipped fail-closed.

#### Scenario: Fetcher normalizes API paths
- **WHEN** the Subsonic API returns a library-relative path or an absolute path rooted at `<musicStorageRoot>/library`
- **THEN** the staged M3U contains `/music/<relative>` for that entry
- **AND** no entry is emitted as `/music/library/...`

#### Scenario: Off-root or escaping paths are rejected
- **WHEN** the Subsonic API returns a path outside `<musicStorageRoot>/library` or a path containing a `..` segment (leading, embedded, or trailing)
- **THEN** the entry is skipped with a diagnostic and the M3U is not corrupted

### Requirement: The import job SHALL chain to the engine direct-DB export
The `import@navidrome` job SHALL consume the `/music`-rooted M3Us and chain to the `export@engine` job via `onSuccess`. The engine export SHALL publish playlists directly into the Engine library database at `<musicStorageRoot>/Engine Library/Database2/m.db` (guest `M:\Engine Library\Database2\m.db`) with `track_path_prefix=../library`, so tracks resolve relative to the Engine Library dir on `M:`.

#### Scenario: Import chains to engine export
- **WHEN** the import job succeeds
- **THEN** the engine export job runs and publishes playlists into the Engine library database
- **AND** tracks resolve from `M:\library` in Engine DJ

### Requirement: The writer jobs SHALL be mutually exclusive with the VM
The `import@navidrome` and `export@engine` jobs SHALL bind to `dj-library-writers.target` (which conflicts with the VM unit) so neither can write the Engine library database while the VM runs.

#### Scenario: Writer starts while the VM runs
- **WHEN** the import or engine-export job is started while the VM is active
- **THEN** the VM is stopped before the job writes
- **AND** starting the VM stops any running writer job

### Requirement: The worker SHALL remain manual
The worker SHALL NOT run on a timer, path watcher, or boot target, and SHALL NOT configure Traktor/NML import or export.

#### Scenario: Host configuration is evaluated
- **WHEN** home-forge evaluates the worker configuration
- **THEN** the `playlist-sync` command and the import/export jobs are defined
- **AND** neither unit is enabled by a timer, path trigger, or boot target
