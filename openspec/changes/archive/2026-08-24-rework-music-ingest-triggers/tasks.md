## 1. Rework the slskd trigger leg

- [x] 1.1 In `modules/applications/music/default.nix`: replace the `slskdDownloadCompleteHook` body with a single `systemctl try-restart slskd-settle.timer` invocation (keep the `PATH` export); add `systemd.timers.slskd-settle` (`OnActiveSec=60s`, `AccuracySec=5s`, `Persistent=true`, `Unit=ffmpeg-preprocess.service`, `wantedBy=timers.target`); delete the `slskd-download-trigger.path` unit.

    refs: `modules/applications/music/default.nix`
    criteria: no `/tmp` marker, lockdir, `is-active` probe, or `.trigger` logic remains; the timer unit is generated with the declared config.

- [x] 1.2 Fix `dropbox-inbox.path`: move `Unit = "ffmpeg-preprocess.service"` from `unitConfig` to `pathConfig`.

    refs: `modules/applications/music/default.nix`
    criteria: rendered unit has `Unit=` only in `[Path]`; no unknown-key warning possible.

- [x] 1.3 Add the scoped polkit rule allowing the `slskd` user to manage only `slskd-settle.timer` via `security.polkit.extraConfig`.

    refs: `modules/applications/music/default.nix`
    criteria: rule matches on both subject user and exact unit name; no broader manage-units grant.

## 2. Remove the retry-timer capability

- [x] 2.1 Delete the `beets-inbox-retry.timer` generator (the import-kind branch of `systemd.timers`) from `modules/services/music/beets/default.nix`, and remove the dead commented-out timer block from `beetsRunnerInstances.inbox` in `modules/applications/music/default.nix`.

    refs: `modules/services/music/beets/default.nix`, `modules/applications/music/default.nix`
    criteria: no `-retry` timer units are generated for any runner kind; boot catch-up is provided solely by settle-timer persistence.

## 3. Documentation

- [x] 3.1 Update the Media Ingest Flow section in `ARCHITECTURE.md`: slskd completions restart the settle timer; dropbox path watch declares its target via `pathConfig.Unit`; retry timer removed.

    refs: `ARCHITECTURE.md`
    criteria: flow description matches the implemented trigger chain; no mention of marker files or the retry timer.

## 4. Validation

- [x] 4.1 Evaluate `oci-melb-1` and confirm: `slskd-settle.timer` present and enabled; `slskd-download-trigger.path` absent; `dropbox-inbox.path` carries `Unit=` under `[Path]`; no `beets-inbox-retry.timer`; polkit rule rendered.

    verify: `nix eval .#nixosConfigurations.oci-melb-1.config.systemd.timers --apply builtins.attrNames --json`, same for `systemd.paths`, plus targeted evals of the two units' text and `security.polkit.extraConfig`.

- [x] 4.2 Run `treefmt --fail-on-change`, `openspec validate rework-music-ingest-triggers --strict`, and the repo's standard checks.

    verify: all pass with no errors.

- [x] 4.3 Post-deploy live check on `oci-melb-1`: `dropbox-inbox.path` and `slskd-settle.timer` are `active (waiting)`; manually restarting the timer runs `ffmpeg-preprocess.service` then `beets-inbox.service` successfully.

    verify: `systemctl status` of both units plus one manual `systemctl restart slskd-settle.timer` end-to-end run.
