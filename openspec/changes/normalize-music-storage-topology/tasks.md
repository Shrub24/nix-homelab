## 1. Storage Contract

- [x] 1.1 Remove physical music roots from `policy/globals.nix`, make `applications.music.dataRoot` and `.storageRoot` host-required, derive the conventional music subtree internally, and verify all fleet hosts evaluate without hidden path defaults.
  - refs: `proposal.md`, `design.md`, `specs/media-services/spec.md`
  - delegate: CoderAgent
  - verify: `nix eval --impure .#nixosConfigurations.home-forge.config.system.build.toplevel.drvPath` and equivalent evaluation for every fleet host
- [x] 1.2 Remove hardcoded shared-path defaults from enabled music leaf modules, inject required paths from `modules/applications/music/`, and verify missing enabled-service paths fail evaluation while composed hosts remain valid.
  - refs: `design.md` MS-3
  - delegate: CoderAgent
  - verify: targeted Nix evaluations for home-forge and OCI plus repository path-reference search
- [x] 1.3 Make home-forge the SSOT for `musicStorageRoot = "/srv/storage/media/music"`, pass it to the music and DJ applications, share it as `M:`, and keep `/srv/data/engine-dj/library` bind-presented at `Engine Library`; deliberately leave `traktor-m3u-sync` output wiring unchanged.
  - refs: `design.md` MS-1, MS-2, MS-4
  - delegate: CoderAgent
  - verify: evaluate derived application paths, VM share source, bind mount, and state-backup path

## 2. Guest Setup Compatibility

- [x] 2.1 Repair `pkgs/windows-dj-setup/setup.ps1` for Windows PowerShell 5.1 using ASCII executable text, parenthesized command expressions, compatible service removal, and `New-Service`/`Start-Service`; verify the packaged script is ASCII-clean and parses in Windows PowerShell 5.1.
  - refs: `design.md` PS-1
  - delegate: CoderAgent
  - verify: local ASCII/static checks followed by the Windows PowerShell parser on the guest

## 3. Preflight

- [x] 3.1 Format and build the changed home-forge configuration, run targeted fleet evaluations, and capture live path/mount/service/Syncthing facts before touching data.
  - refs: `design.md` Migration Plan 1-2
  - delegate: BuildAgent
  - verify: `treefmt --fail-on-change`, targeted Nix build/evals, and recorded preflight output

## 4. Controlled Migration

- [x] 4.1 Inhibit the state-backup timer, quiesce the live Beets/slskd/Navidrome/Syncthing/Podman writers and `windows-dj` domain, unmount the old Engine bind, and migrate the live tree to `/srv/storage/media/music/{library,playlists,inbox,quarantine,.versions}` while preserving `tagged` unchanged and retaining all stale paths until post-deploy validation.
  - refs: `design.md` OP-1 and Migration Plan 3-4
  - depends: 3.1
  - verify: source paths absent as intended, target counts/sizes match, tagged counts match, stale paths remain available, and rollback generations 30/31 are retained
- [x] 4.2 Deploy the normalized home-forge configuration and verify activation creates the new bind/share and restarts all required services without rollback.
  - refs: `design.md` Migration Plan 5
  - depends: 4.1
  - verify: deploy-rs success, current generation, zero relevant failed units, expected mount sources and targets

## 5. Reconciliation

- [x] 5.1 Validate Beets path resolution, Navidrome health/scan, Syncthing folder IDs and paths, the guest `M:` layout, and Engine state-backup coverage; record the expected Engine track re-import requirement, re-enable the backup timer, then remove the approved stale paths as a post-validation cleanup.
  - refs: `specs/media-services/spec.md`
  - delegate: BuildAgent
  - verify: live service/API/database/config checks, guest-side PowerShell path listing, backup timer active, and explicit metadata validation before deleting the non-empty Beets pre-import copy
- [ ] 5.2 Update architecture, decision, restore, and Engine DJ runbook documentation to the normalized schema; run `treefmt --fail-on-change` and `openspec validate --strict` before handoff.
  - refs: `proposal.md`, `design.md`
  - delegate: DocWriter
  - verify: documentation search has no active stale topology references and strict validation passes

## 6. Beets Library-Hygiene Operator Tooling

- [x] 6.1 Ship repo-managed `beets-merge-splits` operator bin (preview default, `--apply [filter]`) promoting the proven split-merge workflow; auto-merge only identical-metadata groups, list the rest REVIEW.
  - verify: `bash -n`, 3-host eval, strict validation
- [x] 6.2 Ship repo-managed `beets-prune-empty` operator bin (preview default, `--apply`) deleting audio-free library dirs including cover-only husks while skipping `.stfolder` trees.
  - verify: `bash -n`, 3-host eval, strict validation
- [x] 6.3 Define permanent music-scoped `b` beets operator alias (beets user, standard config) in the music application module.
  - verify: 3-host eval, alias resolves on home-forge after deploy
- [x] 6.4 Wire `badfiles` into the import flow (no standalone runner): plugin + `check_on_import` in both beets configs; standard config skips bad files on error (existing demote sweeps them to quarantine); quarantine config keeps ask-actions so the operator answers per file; `commands:` covers aif/aiff via a `beet-ffmpeg-check` wrapper (mp3 uses built-in mp3val).
  - verify: 3-host eval, quiet inbox import skips (not imports) a corrupt file, strict validation
- [x] 6.5 Enable `convert` for the library-format sweep: plugin + `convert.dest` placeholder in standard config, per-format `aiff` (pcm_s16be) / `mp3` (320k) profiles matching the inbox preprocess outputs, `ffmpeg` on host PATH for `b convert`
  - verify: 3-host eval, `b convert --pretend` resolves, strict validation
- [x] 6.6 Debounce dropbox inbox triggers like slskd: `dropbox-poke.service` re-arms a 60s `dropbox-settle.timer` on every path event; preprocess skips files younger than 45s and synthesizes one dropbox event when any were skipped so no straggler waits for the next real change
  - verify: 3-host eval, strict validation
- [x] 6.7 Run AudioMuse 3.5 on home-forge against OCI's shared Postgres over Tailscale (folded from the unfiled audiomuse-3.5 lane: module refactor with `postgresHost`, `max_connections` 20→40, pinned 3.5.2 image, home-forge recipient on the app credentials).
  - verify: 3-host eval, strict validation...[truncated]
