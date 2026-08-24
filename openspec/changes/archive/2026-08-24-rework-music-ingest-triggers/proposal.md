## Why

The music ingest pipeline on `oci-melb-1` has been dead since the event-driven refactor shipped, due to two independent breaks stacked on top of each other:

1. Both `systemd.paths` units declare their trigger target as `unitConfig.Unit`, which renders `Unit=` into the `[Unit]` section where systemd ignores it ("Unknown key 'Unit' in section [Unit]"). Path units fall back to triggering their namesake `.service`, which does not exist, so `dropbox-inbox.path` and `slskd-download-trigger.path` fail to start at every boot ("Refusing to start, unit ... to trigger not loaded").
2. Even with correct wiring, the slskd leg cannot work: the debounced hook runs inside slskd's mount namespace (`PrivateTmp=true`), so its `/tmp/slskd-download-trigger` marker lands in slskd's private tmpfs while the path unit watches the real `/tmp`. Host evidence confirms the marker exists in `/proc/<slskd-pid>/root/tmp` while the host-side watch never fires.

Secondary defects in the same machinery: the bash debounce duplicates settle logic that already lives in `beets-runner-import`; its `.trigger` extension file is written by nothing (dead code); its busy-skip (`exit 0` while the pipeline is active) loses events with no recovery path; and `beets-inbox-retry.timer` uses only `OnActiveSec=10min`, firing once per boot and then sitting `active (elapsed)` forever. The one import attempt in six days came from that timer and failed on a since-healed template permission issue, masking the dead trigger chain.

## What Changes

- Fix `Unit=` placement: move the trigger target from `unitConfig` to `pathConfig` on `dropbox-inbox.path`.
- Replace the marker-file/path-unit slskd leg with a settle timer: the slimmed hook becomes `systemctl try-restart slskd-settle.timer`, and the timer (`OnActiveSec=60s`, `AccuracySec=5s`, `Persistent=true`, targeting `ffmpeg-preprocess.service`) starts the pipeline 60 seconds after the last `DownloadDirectoryComplete` event. Each event re-arms the window, which debounces concurrent album completions without any file state.
- Grant the unprivileged `slskd` user polkit permission to manage exactly one unit (`slskd-settle.timer`) via a scoped `security.polkit.extraConfig` rule.
- Delete the bash debounce machinery (lockdir, `is-active` probes, dead `.trigger` logic, `/tmp` marker) and the `slskd-download-trigger.path` unit.
- Delete the `beets-inbox-retry.timer` generator from the beets framework layer (approved capability removal). `Persistent=true` on the settle timer provides boot catch-up.
- Keep `services.slskd.downloadCompleteScript` as the framework seam, keep the `ffmpeg-preprocess` / `beets-inbox` unit split and the `OnSuccess` chain unchanged.
- Update `ARCHITECTURE.md` Media Ingest Flow to describe the timer-based trigger.
- Out of scope: the ntfy HTTP 403 error-1010 Cloudflare bot-block affecting UnifiedPush delivery (separate future change).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `beets-automation`: inbox trigger sources are a settle timer reset by the slskd completion hook plus a corrected dropbox path unit; the once-per-boot retry timer is removed and boot catch-up is provided by timer persistence.

## Impact

- `modules/applications/music/default.nix` (hook body, timer, path unit fix, polkit rule)
- `modules/services/music/slskd.nix` (no interface change; consumes the slimmed script)
- `modules/services/music/beets/default.nix` (retry-timer generator removal)
- `openspec/specs/beets-automation/spec.md` (trigger-source scenario rewrite)
- `ARCHITECTURE.md` (Media Ingest Flow wording)
- New system-level surface: one scoped polkit rule permitting `slskd` to restart `slskd-settle.timer`.
