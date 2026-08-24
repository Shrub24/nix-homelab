# Design

## Why not a path watch on the slskd download tree

`PathModified`/`PathChanged` are non-recursive inotify watches. slskd writes nested `artist/album/track` trees, so a watch on `inbox/slskd` sees only top-level directory creation, not file completion. A direct watch is therefore not viable for the slskd leg; the dropbox leg keeps its `PathModified` watch because drops there are flat.

## slskd event semantics (verified from source, `DownloadService.cs`)

- `DownloadDirectoryComplete` fires once per `(username, remote directory)` when the last *tracked* transfer completes; queued, initializing, and in-flight siblings all count as pending because only finished transfers are removed from the client dictionary before the check.
- The event fires only in the success path, after the file has been moved from `slskd-incomplete` into the downloads tree. Directories whose files all fail never fire.
- Single-file downloads from a directory fire the event normally.

Consequence: re-arming a settle window on every event yields "all currently-queued batches settled" semantics without querying the API. The API alternative (`/api/v0/transfers/downloads`, filter by transfer `State`) has no aggregate endpoint and would add JSON walking plus credential plumbing for the same outcome.

## Polkit grant

The hook executes as the unprivileged `slskd` user inside the slskd service; restarting a system unit requires `org.freedesktop.systemd1.manage-units` authorization. The rule grants `polkit.Result.YES` only when `subject.user == "slskd"` and `action.lookup("unit") == "slskd-settle.timer"`. Rejected alternative: marker file in a shared real directory watched by a path unit — rejected because file-touch triggering is explicitly unwanted and it reintroduces namespace-sensitive state.

## Rejected: merging ffmpeg-preprocess into beets-inbox

Conversion stays a separate idempotent unit shared by both trigger sources. Merging couples conversion retries to import failures and rewrites working machinery for no capability gain.

## Residual edges (accepted, documented)

- Split batches across time (partial album today, rest next week) produce two imports; beets handles dedup.
- The same album from two sources/directories fires independent events per `(username, remote directory)`.
- Manual copies straight into `inbox/slskd/` produce no event; manual drops belong in `dropbox/`.
