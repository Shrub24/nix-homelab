## Why

The Beets music automation pipeline has accumulated several gaps between its different execution paths and operational boundaries. Five separate changes have been addressing these issues individually; this consolidation merges them into a coherent "workflow hardening" effort:

1. **Runner parity**: `beets-interactive` behaved differently from `beets-inbox` — missing promotion cleanup, permission reconciliation, Navidrome refresh, and durable journald capture. Manual quarantine rescue was hard to audit and could leave accepted files outside the visible library path.
2. **Navidrome scan timing**: Successful Beets imports updated the library on disk, but Navidrome only saw new content on its periodic scan schedule, creating a delayed feedback loop for operators.
3. **Permission reconciliation coupling**: The permission reconciliation worker (`beets-runner-permission-reconcile`) ran root-level ACL operations (`chgrp`, `chmod`, `setfacl`) but was wired as a beets runner kind running as the unprivileged `beets` user, causing silent failures when triggered standalone.
4. **Convert plugin temp-file naming**: The beets `convert` plugin with `auto: yes` created temp files during import whose names leaked into the final library path (e.g., `tmp0jep9ejq.aiff`). Since `ffmpeg-preprocess` already converts before import, the plugin was redundant.


## What Changes

### Runner Parity (from beets-interactive-runner-parity)
- Make the interactive quarantine runner use the same explicit library destination and post-import cleanup pattern as the normal runner, except without ffmpeg conversion (preprocessing already happened before demotion).
- Make interactive runs emit output to journald under a predictable transient unit name while preserving persistent `/srv/data/beets/logs/*-runner.log` files.
- Run permission reconciliation and Navidrome scan after successful interactive runs.
- Adjust quarantine Beets config to avoid phantom imported-but-still-untagged entries and keep retry behavior operator-friendly.

### Navidrome Scan Hook (from beets-navidrome-scan-hook)
- Add a dedicated `navidrome-scan.service` systemd oneshot using the same Navidrome package, data folder, and music folder as the running service.
- Chain `beets-inbox.service` success to `navidrome-scan.service` using native systemd `OnSuccess=` wiring.
- Keep Navidrome scan execution in the Navidrome module — Beets should not know how to invoke Navidrome's CLI directly.

### Permission Reconciliation Extraction (from extract-permission-reconcile)
- Extract permission reconciliation from the beets runner framework into a standalone root service (`media-permission-reconcile.service`) in the application composition layer.
- Remove `permission-reconcile` from the beets runner kinds enum and all related framework wiring.
- Replace `ExecStartPost` with `OnSuccess=` chaining; the `onSuccessUnits` list is a module-level option set by the application composition layer.
- Rename `beets-fixperms` CLI wrapper to `media-fixperms`.

### Convert Plugin Removal (from remove-beets-convert-plugin)
- Remove the `convert` plugin and its configuration block from the standard Beets config.
- Conversion is handled solely by `ffmpeg-preprocess` before import, eliminating temp-file name leakage.

## Capabilities

### New Capabilities

- `navidrome-scan-trigger`: Defines how repo-managed automation triggers Navidrome scans after successful Beets runs.

### Modified Capabilities

- `beets-automation`: Interactive quarantine imports gain deterministic promotion/post-processing and inspectable logs consistent with inbox automation. Beets inbox automation gains a post-success systemd chain to request a Navidrome scan. Standard config no longer uses the convert plugin.
- `media-services`: Permission reconciliation becomes a standalone root service rather than a beets runner kind, decoupling media ACL maintenance from the beets framework.

## Impact

- Affected modules: `modules/applications/music/default.nix`, `modules/services/music/beets/default.nix`, `modules/services/music/beets/runners.nix`, `modules/services/music/beets/types.nix`, `modules/services/music/navidrome.nix`, `modules/applications/music/files/beets-config.yaml`, `modules/applications/music/files/beets-quarantine-config.yaml`
- Affected runtime units: `beets-inbox.service`, `beets-interactive`, `navidrome-scan.service`, `media-permission-reconcile.service`
- CLI commands: `beets-interactive`, `media-fixperms` (renamed from `beets-fixperms`), `journalctl -u 'beets-interactive*.service'`
- No new public routes or external services required
