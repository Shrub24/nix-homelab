## Context

The automated inbox path is reliable because it runs preprocessed media through a non-interactive runner, demotes unresolved leftovers, reconciles permissions, and triggers a Navidrome scan. However, several execution paths and operational boundaries were misaligned:

- The interactive quarantine path only launched `beet import` in a transient unit with a random name, capturing no useful output in journald.
- Permission reconciliation was embedded in the beets runner framework as a runner kind, but required root to function — causing silent failures when triggered standalone.
- The beets `convert` plugin created temp files whose names leaked into the final library path.
- Navidrome only saw new imports on its periodic scan schedule.

## Goals / Non-Goals

**Goals:**

- Make all Beets import paths (interactive and automated) produce consistent outcomes: explicit library destination, promotion cleanup, permission reconciliation, Navidrome scan, and durable logging.
- Decouple permission reconciliation from the beets runner framework; run it as root via a standalone service.
- Eliminate temp-file name leakage by removing the redundant convert plugin.
- Trigger Navidrome scans immediately after successful Beets runs via systemd chaining.

**Non-Goals:**

- Make interactive imports fully non-interactive.
- Replace Beets matching behavior or metadata providers.
- Change the slskd/dropbox ingestion trigger flow.
- Guarantee scans happen only when Beets imports more than zero songs.
- Change the ACL rules themselves (group ownership, modes, setfacl rules stay the same).

## Decisions

### MW-1: Explicit library destination in Beets configs

Both standard and quarantine Beets configs SHALL declare the library destination explicitly as `/srv/media/library` so imports do not depend on Beets defaults derived from `HOME` or `BEETSDIR`.

*Source: beets-interactive-runner-parity (BIRP-1)*

### MW-2: Quarantine import skips unresolved items instead of importing as-is

The quarantine config SHALL use retry-friendly behavior for unresolved prompts. Skipped files remain in quarantine for a later interactive run instead of becoming confusing DB entries that still point at untagged paths.

*Source: beets-interactive-runner-parity (BIRP-2)*

### MW-3: Interactive runner mirrors inbox post-processing without conversion

The quarantine-interactive runner SHALL run Beets interactive import, then demote any leftover media to the configured untagged boundary and clean old runner logs. The quarantine config SHALL NOT auto-convert because files entering quarantine have already passed through preprocessing.

*Source: beets-interactive-runner-parity (BIRP-3)*

### MW-4: Wrapper handles host-level post actions and logging

The `beets-interactive` wrapper SHALL use a predictable transient unit name and journal mode that preserves command output in journald, then run permission reconciliation and trigger Navidrome scan when the interactive import exits successfully.

*Source: beets-interactive-runner-parity (BIRP-4)*

### MW-5: Use systemd `OnSuccess=` as the Navidrome scan trigger

The application composition layer SHALL wire `beets-inbox.service` success to `navidrome-scan.service` using systemd `OnSuccess=`. This is the canonical systemd mechanism for starting one unit after another unit completes successfully. No-op scans after successful imports that add no items are acceptable — they avoid marker files, PolKit rules, unprivileged `systemctl`, and custom runner callback abstractions.

*Source: beets-navidrome-scan-hook (BNS-1)*

### MW-6: Keep Navidrome scan execution in the Navidrome module

Navidrome scan execution SHALL live in the Navidrome module as a systemd oneshot. Beets should not know how to invoke Navidrome's CLI directly.

*Source: beets-navidrome-scan-hook (BNS-2)*

### MW-7: Keep scan command native and explicit

Because Navidrome is native NixOS here, the scan unit SHALL use the configured Navidrome package and explicit data/music folders instead of Docker/Podman exec patterns.

*Source: beets-navidrome-scan-hook (BNS-3)*

### MW-8: Standalone root service in the music application layer

The permission reconciliation service SHALL be defined in `modules/applications/music/default.nix` as `media-permission-reconcile.service`, running as root with `Type=oneshot`. This is the application composition layer where cross-service media concerns belong.

*Source: extract-permission-reconcile (EPR-1)*

### MW-9: Remove permission-reconcile from beets runner framework

The `permission-reconcile` runner kind SHALL be removed from the `runnerKind` enum, the `permission-reconcile` entry in `runners.nix`, the `permissionReconcileBin` let-binding, and the `ExecStartPost` on generated beets services.

*Source: extract-permission-reconcile (EPR-2)*

### MW-10: OnSuccess chaining replaces ExecStartPost

Beets runner services SHALL use `OnSuccess` chaining to trigger post-run services. The `onSuccessUnits` list is a module-level option set by the application composition layer, keeping the beets framework generic. The music application layer sets it to `[ "media-permission-reconcile.service" "navidrome-scan.service" ]` so all beets runners trigger both ACL reconciliation and Navidrome scan on success.

*Source: extract-permission-reconcile (EPR-3)*

### MW-11: CLI wrapper renamed from beets-fixperms to media-fixperms

The `beets-fixperms` CLI wrapper SHALL be renamed to `media-fixperms` to reflect that it's a media-directory operation, not a beets operation.

*Source: extract-permission-reconcile (EPR-4)*

### MW-12: Remove convert plugin from standard config

The standard Beets config SHALL NOT include the `convert` plugin or its configuration block. Conversion is handled by `ffmpeg-preprocess` before import.

*Source: remove-beets-convert-plugin (RBCP-1)*

## Risks / Trade-offs

- [Risk] Predictable transient unit names can collide if two operators run `beets-interactive` concurrently → Mitigation: include a timestamp or allow systemd to fail clearly; concurrent manual rescue is not expected.
- [Risk] Successful no-op Beets inbox runs trigger redundant Navidrome scans → Mitigation: Navidrome scans are idempotent and this avoids substantially more orchestration machinery.
- [Risk] `OnSuccess=` fires even on 0-item imports → Mitigation: permission reconciliation is idempotent; running it on no-op imports costs negligible time.
- [Risk] Removing the convert plugin means files in formats not handled by ffmpeg-preprocess (ALAC, APE, etc.) will be imported as-is → Mitigation: extend ffmpeg-preprocess to handle additional formats if the need arises.
- [Risk] Existing library items with tmp names need manual cleanup → Mitigation: operator can rename or re-import affected albums.
