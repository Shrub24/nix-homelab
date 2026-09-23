## Context

See `proposal.md` for motivation. The deployed, archived Stage 5 change lands at commit `ee774aa622aa8a572a34cfcc534f00b2538cbde0` ("refactor: convert shared source contributors"); music is the application conversion explicitly deferred by D-051 (many source conversions remain). Today `modules/applications/music/default.nix` is a 792-line evaluator-class coordinator imported directly by `home-forge`: it doubles as composition root and implementation owner. Wrong ownership in that file: Beets secret registration plus config-template rendering (`sops.secrets` / `sops.templates`), the Beets operator binaries (`beets-interactive`, `beets-dupes`, `beets-merge-splits`, `beets-prune-empty`), the concrete ingest mechanisms (`ffmpeg-preprocess` bin/service, `dropbox-inbox` path unit, `dropbox-poke` service, `dropbox-settle`/`slskd-settle` timers, `slskd-download-complete` hook, slskd polkit rule), the permission-reconcile unit body, and the media tmpfiles/ACL implementation. Engine DJ reaches music only through host-supplied path literals, not an explicit contract.

The four-root import-tree filter (`applications`, `hosts`, `providers`, `services`) is unchanged by this change, so `modules/services/music/**` stays a filtered (non-discovered) subtree and the music contributor must import its private leaves explicitly. No behavior may change: units, timers, scripts, ACLs, paths, option namespaces, secret content/scope, backup paths, and the playlist/Traktor worker logic/input are frozen.

## Goals / Non-Goals

**Goals:**

- Publish a home-forge-only `flake.modules.nixos.music` aspect whose selection provides `applications.music.enable`.
- Keep a thin `applications.music` coordinator: shared path derivation, feature choices, inter-service wiring, secret-file passthrough, backup policy, success-chain intent, and the explicit music contract.
- Move concrete mechanisms to their owners: Beets SOPS/template + operator binaries + runner runtime to the Beets leaf; ingest ffmpeg/path/timers/polkit to a private music ingest leaf; groups/tmpfiles/permission reconcile to a private music storage leaf.
- Give `dj` a typed explicit music contract consumed with a named assertion, without `dj` importing or enabling `music`.
- Prove behavior equality against the Stage 5 baseline with structured observables and provenance-only closure deltas.

**Non-Goals:**

- No filter shrink, no `applications`/`services` root conversion, no new flake input, no deployment.
- No public option rename or namespace migration, no `specialArgs`, no compatibility bus.
- No change to secrets/`.sops.yaml`, policy, routes, providers, edge-ingress, admin, backup paths, or product behavior.
- No change to the playlist/Traktor worker logic, unit mutual exclusion, scripts, timers, or inputs.

## Decisions

### S6-1 — Baseline is the deployed archived Stage 5 change at `ee774aa622aa8a572a34cfcc534f00b2538cbde0`

Before any edit, capture the baseline from a clean detached checkout of exactly full hash `ee774aa622aa8a572a34cfcc534f00b2538cbde0` (short `ee774aa6`) at a recorded absolute path (e.g. `git worktree add --detach /tmp/s6-baseline-ee774aa6 ee774aa622aa8a572a34cfcc534f00b2538cbde0`). If the commit is absent locally, fetch it and record the resolved hash before edits; do not reconstruct the baseline from working-tree content. Evaluate `path:<abs>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` from that path so evidence is tied to the actual repo files. Store a structured observable snapshot per host (see S6-12) plus `nix diff-closures` output. The hard gate is structured observable equality against these captures; `nix-diff` / `nix diff-closures` deltas are permitted only when attributable to source-order or derivation/store-path renames caused by relocating or nesting expressions.

### S6-2 — Publish `flake.modules.nixos.music` from a discovered contributor; selection is enablement

Add `modules/flake/music.nix`, a normal top-level discovered contributor publishing `flake.modules.nixos.music`. Its NixOS body nests the retained composition inline (S6-4) and imports the private leaves (S6-9). Like `dj`, selecting the aspect sets `applications.music.enable = true`; the `home-forge` host drops its `../../../modules/applications/music` import and its `applications.music.enable = true` assignment, and the registry adds `aspects.music` to the forge record only. Discovery alone must stay inert: on `oci-melb-1` and `la-admin-1` the aspect is discovered but never selected, so no `applications.music` option, service, unit, tmpfile, secret, or package is activated. `modules/applications/music/default.nix` and its `files/` directory are deleted after their contents move to owners (S6-5..S6-7); other application contributors under `modules/applications/` are untouched.

### S6-3 — Typed explicit music contract; DJ consumes it with a named assertion

The composition exposes a read-only typed contract, declared **inside its `lib.mkIf cfg.enable` body** so it only exists when the aspect is selected:

```
applications.music.contract = {
  storageRoot;   # = cfg.storageRoot
  libraryDir;    # = mediaPaths.libraryDir
  playlistsDir;  # = mediaPaths.playlistsDir
};
```

Because the contract lives only in that gated body, `config.applications.music.contract` is absent — not merely empty — on any host that does not have the `music` aspect selected (e.g. `oci-melb-1`, `la-admin-1`, and `home-forge` before selection). `engine-dj.nix` reads it defensively, never as an import:

```
musicContract = config.applications.music.contract or null;
```

Both public options **keep `lib.types.str`** and gain contract-derived safe defaults that never leave them null or missing:

```
sharePath.default = if musicContract != null then musicContract.storageRoot else "";
musicStorageRoot.default = if musicContract != null then musicContract.storageRoot else "";
```

The type therefore stays `str` (never `nullOr`), so `dj` without `music` evaluates instead of failing on a missing attribute or a null type error. Correctness is enforced by one named assertion, active only when the engine is enabled, that accepts either source of truth:

```
assertions = lib.optional engineEnabled {
  assertion = musicContract != null || (engine.sharePath != "" && engine.musicStorageRoot != "");
  message = "applications.dj.engine requires applications.music.contract; select the music aspect on this host (or set applications.dj.engine.sharePath and musicStorageRoot explicitly).";
};
```

Semantics: selecting `dj` without `music` is allowed **only** when the host explicitly sets both `applications.dj.engine.sharePath` and `musicStorageRoot` to non-empty strings; otherwise the named assertion fires with that message. When `music` is selected the defaults fill both from `musicContract.storageRoot`, so `home-forge` drops its repeated literal while explicit host overrides still win. `music` and `dj` stay separate, co-selected aspects: `music` never asserts or imports `dj`, and `dj` never imports or enables `music`. `home-forge` keeps `applications.music.storageRoot = "/srv/storage/media/music"` and `applications.dj.engine.traktorStateDir` / `secretFiles.navidrome`; it drops only the now-derived DJ share/root literals. `libraryDir`/`playlistsDir` are contract surface for downstream; adopting them inside the Engine export job paths is deferred (S6-11, Open Questions).

### S6-4 — The coordinator keeps composition ownership only

`modules/flake/music.nix` retains, inline:

- `applications.music` public options unchanged (`enable`, `dataRoot`, `storageRoot`, `syncthingDevices`, `syncthingFolders`, `audiomuse.*`, `navidrome.enable`, `secretFiles.host`, `slskdDomain`, `configFiles`) plus the read-only `contract`.
- `mediaPaths` derivation; `secretHelpers`; the `applications.music.secretFiles.host` required-secret assertion.
- Service selection/wiring: `services.syncthing` (+ its state-backup), `services.navidrome` (+ backup), `services.audiomuse` (+ backup), `services.beets` (dataDir/paths/secretFiles/configFiles/runners/notify), `services.slskd` (+ download-complete hook from the ingest leaf), `services.tagr`, `services.state-backups.services.{media,beets}` with the existing paths/exclude, `users.users.dev.extraGroups`, `programs.zsh.shellAliases.b`.
- Inter-service wiring and success-chain intent: `services.beets.onSuccessUnits = [ "media-permission-reconcile.service" ] ++ optional cfg.navidrome.enable "navidrome-scan.service"`, `services.beets.importReadyFlag = config.services.musicIngest.readyFlag`, `services.musicIngest.onSuccessUnit = "beets-inbox.service"`, and runner `configSource = config.services.beets.renderedConfigFiles.{standard,quarantine}`.
- Backup policy (which music services are covered and their `mode`/`paths`/`exclude`) stays composition-owned; the mechanism of a covered service stays with its leaf.

### S6-5 — Beets owner absorbs Beets SOPS/templates, operator binaries, and runner runtime

`modules/services/music/beets/default.nix` gains:

- Registration of `sops.templates."beets-config.yaml"` / `"beets-quarantine-config.yaml"` and `sops.secrets.beets_*` from `cfg.secretFiles.host`, with the exact existing keys, `/run/secrets/beets.*` paths, `owner = "beets"`, `group = "beets"`, modes, placeholders, and rendered values (`libraryDir`, `${cfg.dataDir}/state/library.db`, `${cfg.dataDir}/convert`). These stay inside the leaf's existing secret-file `lib.mkIf (cfg.secretFiles.host != null)` gate; only actual SOPS secrets/templates are secret-gated.
- A read-only `services.beets.renderedConfigFiles` option (`{ standard; quarantine; }`) whose **option declaration and value are unconditional — outside that secret-file `mkIf`**. It resolves `config.sops.templates."beets-config.yaml".path` / `"beets-quarantine-config.yaml".path` when those templates are present and otherwise falls back to the source `configFiles.{standard,quarantine}` paths, so the composition stops re-deriving it and reads a stable option regardless of secret wiring. Cycle-safe: it reads `configFiles` (an option it does not write) plus `config.sops.templates.*`, and never depends on `cfg.runners`; the composition's `runners` then depend on it (S6-8).
- The four Beets operator binaries (`beets-interactive`, `beets-dupes`, `beets-merge-splits`, `beets-prune-empty`) and their `environment.systemPackages` entries. `beets-interactive` reuses `cfg.onSuccessUnits` for its post-success tail (identical `systemctl start` set/order to today); the merge-splits and prune-empty scripts move to `modules/services/music/beets/files/`.
- Its own Beets-state tmpfiles (`dataDir`, `state`, `logs`, dev ACL) only. The media untagged/approved tmpfiles+ACLs move to the storage leaf (S6-7).

The two `beets-*.yaml` configs move to `modules/services/music/beets/files/`; `applications.music.configFiles` defaults repoint there. `runners.nix` is unchanged.

### S6-6 — Private ingest leaf owns the ingest mechanisms

New private `modules/services/music/ingest.nix` (options `services.musicIngest`):

- Inputs injected by the composition: `inboxDir`, `storageRoot`, `readyFlag`, `onSuccessUnit` (default `"beets-inbox.service"`), and a read-only `downloadCompleteScript`.
- Owns the `ffmpeg-preprocess` binary/service, the `dropbox-inbox` path unit, `dropbox-poke.service`, the `dropbox-settle`/`slskd-settle` timers, the `slskd-download-complete` hook, the scoped slskd polkit rule, and `environment.systemPackages` contribution.
- `readyFlag` derives from a `stateDirectory` option (default `"beets/ffmpeg-preprocess"`), i.e. `/var/lib/beets/ffmpeg-preprocess/inbox-ready`, matching today's literal. `ffmpeg-preprocess.sh` moves to `modules/services/music/files/ffmpeg-preprocess.sh`. Unit names, `OnSuccess=`, path/timer triggers, hardening keys, `StateDirectory`, and the script body stay byte-identical.

### S6-7 — Private storage leaf owns groups, media tmpfiles/ACLs, and permission reconcile

New private `modules/services/music/storage.nix` (options `services.musicStorage`):

- Inputs injected by the composition: `storageRoot`, `libraryDir`, `playlistsDir`, `inboxDir`, `quarantineDir`, `versionArchiveRoot`; derives `untaggedDir`/`approvedDir` from `quarantineDir` (same values as the Beets leaf derivation).
- Owns `users.groups.music-ingest.gid = 990` and `users.groups.media.gid = 987`, the media tmpfiles/ACL rules (root, `.versions` + subdirs, library, playlists, quarantine, untagged, approved, inbox, inbox/dropbox, plus the `/var/lib/{slskd,tagr}/environment` file rules), `systemd.services.media-permission-reconcile` (same body/paths), the `media-fixperms` binary, and its `environment.systemPackages` contribution. `users.users.dev.extraGroups` stays in the composition because it spans Beets and media groups.

### S6-8 — Leaf option interfaces and acyclic wiring

| Direction | Interface | Rule |
|---|---|---|
| composition → leaves | `services.musicStorage.*`, `services.musicIngest.*`, existing `services.{beets,navidrome,syncthing,slskd,tagr,audiomuse}.*` | leaves receive explicit strings/paths; no leaf reads `applications.music` |
| beets leaf → composition | read-only `services.beets.renderedConfigFiles` | depends on `configFiles` + its own `sops.templates`; composition reads it when building `runners` |
| ingest leaf → composition → slskd leaf | read-only `services.musicIngest.downloadCompleteScript` | ingest leaf produces the hook script; composition assigns it to `services.slskd.downloadCompleteScript`; no slskd↔ingest direct edge |
| composition → dj | read-only `applications.music.contract` | `engine-dj.nix` reads via `config.applications.music.contract or null`; `dj` never imports `music` |
| cross-leaf | frozen literal unit names (`media-permission-reconcile.service`, `beets-inbox.service`, `navidrome-scan.service`) | stable contract strings, not option reads |

No cycle: `renderedConfigFiles` never depends on `runners`; the composition's `runners` depend on `renderedConfigFiles`; the ingest leaf's `downloadCompleteScript` is consumed only by the composition and never reads `services.slskd`; leaves depend only on their own injected options; `dj` → `music` is a read-only config edge with an `or null` guard.

### S6-9 — Private placement under `modules/services/music/**` is consistent with D-050

The one deployment aspect is published from the discovered contributor `modules/flake/music.nix`; the concrete leaves stay private under `modules/services/music/**` and are reachable only through that aspect's imports. This matches D-050: source ownership and deployment granularity are independent axes, discovery registers contributions without deploying them, and genuine private implementation may remain under an explicit private path. It also matches `feature-topology`'s feature-domain subtree allowance. It does **not** imply permanent non-contribution: the four-root filter is unchanged by this change, so `services` remains transitional. **Retirement criterion:** when `modules/services/` is scheduled for conversion, these leaves either move beside the music contributor under a concern-owned underscore path (`modules/flake/_music/**`) or become top-level contributors if they gain independent placement; this change records that path but does not perform it to avoid churn and to stay clear of the in-flight worker change.

### S6-10 — Behavior freeze, filter, and multi-host inertness

Do not change: unit names, timers, scripts, ACLs/rules, paths, public option namespaces (`applications.music.*`, `services.beets.*`, `services.navidrome.*`, `services.syncthing.*`, `services.slskd.*`, `services.tagr.*`, `services.audiomuse.*`, `applications.dj.*`), secret content/scope/paths/owners, backup paths/modes/excludes, or the playlist/Traktor worker logic/input. `_unconverted-nixos-dirs.nix` remains exactly `["applications","hosts","providers","services"]` and both filtered roots are untouched. `home-forge` remains the only music host; `oci-melb-1`/`la-admin-1` must evaluate with no music options/services activated.

### S6-11 — Overlap with the active playlist/Traktor worker change

`navidrome-m3u-itunes-worker` / `traktor-m3u-sync-worker` overlap `engine-dj.nix`. Contract wiring there is additive-only (new defaults + read-only `musicContract` read + named assertion). **Re-pin the forbidden symbols/line ranges at implementation start** using symbol search and the current file contents rather than trusting any line numbers recorded here; the pinned set is the symbols named below, not stale coordinates. Do not edit: the `playlistSyncFetch` / `playlistSyncBin` script text, `services.traktor-m3u-sync.jobs.{navidrome,engine,itunes}`, `state-backups.services.engine-dj` prepare/cleanup commands, the `windows-vm` instance definition, the `dj-library-writers.target` bindings, and the `Engine Library` tmpfiles. Rebase the contract wiring after those changes land if they conflict.

### S6-12 — Verification

**Structured observables (per host, from `ee774aa6` and post-change):** `systemd.services` keys and the full definitions of music units; `systemd.timers` / `systemd.paths` keys; `systemd.tmpfiles.rules` (including slskd/tagr `f` rules); `sops.secrets` (name, `sopsFile`, `key`, `path`, `owner`, `group`, mode) and `sops.templates` (name, owner/group/mode, content); `environment.systemPackages` names; `users.groups.{music-ingest,media}.gid` and `users.users.dev.extraGroups`; `programs.zsh.shellAliases.b`; the exact `security.polkit.extraConfig` text; `services.slskd.downloadCompleteScript` as a derivation/path plus, as feasible, its rendered content; `services.state-backups.services.{media,syncthing,navidrome,beets,tagr,audiomuse,engine-dj}` (`enable`, `mode`, `paths`, `exclude`); `services.beets.{onSuccessUnits,importReadyFlag}`; and `applications.dj.engine` values. Compare JSON equality; on `home-forge` also compare the derived `applications.dj.engine.{sharePath,musicStorageRoot,traktorStateDir}` and assert both equal `/srv/storage/media/music` and the existing state dir.

**Closure:** per host, `nix diff-closures` against the baseline; deltas are acceptable only for source-order or store/derivation-path renames caused solely by relocating/nesting expressions.

**Negative mutations (throwaway copies):** every negative mutation is proven by evaluating the full toplevel `path:<copy>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` — never a shallow `.config` read — so evaluation-order, option-merge, and assertion failures surface as they would on a real build. Specifically: discovery-without-selection leaves `oci-melb-1`/`la-admin-1` with `(c.applications.music or {})` empty and no music units; removing `applications.music.enable = true` from the selected `music` aspect leaves the selection but disables the application contract; selecting `dj` without `music` and without explicit `sharePath`/`musicStorageRoot` fails the S6-3 named assertion (while explicit values for both succeed); `music` without `dj` evaluates and keeps music observables; the new private leaves are not discovered, publish no aspect, and are not host-imported.

**Contract test:** extend `tests/check-dendritic-scaffold-contract.sh` for the 15-publication set (`+ flake.modules.nixos.music`), the forge selection adding `aspects.music`, and the music observable/mutation probes above. Privacy is asserted by owner, not by a hardcoded operational predicate: an exhaustive host-tree grep forbidding any direct `modules/services/music` import, a publication-exclusion check over every private music leaf, and an explicit owner-import check that only the concern owner imports those leaves.

### S6-13 — Migration and rollback

1. Capture the `ee774aa6` baseline worktree and structured snapshots (S6-1).
2. Move the Beets config/template inputs and operator scripts to their owners; add `renderedConfigFiles` and the Beets owner body (S6-5).
3. Add the ingest and storage leaves and rewire the composition into `modules/flake/music.nix` (S6-4/S6-6/S6-7).
4. Delete `modules/applications/music/`; update `home-forge` and the registry; add the contract/assertion to `engine-dj.nix` (S6-2/S6-3).
5. Update `tests/check-dendritic-scaffold-contract.sh`; run `treefmt --fail-on-change`, `nix flake check --no-build`, all three host toplevels, structured comparison, and `nix diff-closures`.
6. Record the Stage 6 decision (superseding only the music-deferral clause of D-050/D-051) and reconcile current docs. Deployment stays behind the established per-stage operator gate.

Rollback is the `ee774aa6` baseline (JJ change / `git revert`). No secrets, `.sops.yaml`, or media data are touched.

## Risks / Trade-offs

- **Relative imports break on relocation** → Beets stays at the same depth (`../../../../lib/secrets.nix` unchanged); `modules/flake/music.nix` is one level shallower (`../../lib/secrets.nix`); new `modules/services/music/*.nix` leaves use `../../../lib/...` if needed. Gate on all three host evals.
- **`applications.music` options now exist only under selection** → only `engine-dj.nix` reads them and does so via `config.applications.music.contract or null`; because the contract is declared inside `lib.mkIf cfg.enable`, it is absent on OCI/LA (which must leave `(config.applications.music or {})` empty, S6-12) and DJ options stay `types.str` with `""` defaults plus the named assertion, never `nullOr` (S6-3).
- **Store-path churn from relocating template/config expressions** → gate on structured equality plus the provenance-only closure allowlist.
- **Duplicate untagged/approved derivation** → storage and Beets leaves derive the same values from the same `quarantineDir`; structured tmpfiles/runner-path equality catches drift.
- **Overlap with the active worker change** → additive wiring only plus the S6-11 forbidden ranges, rebased if needed.
- **Filter still holds `services`** → leaves stay private under a transitional root with the recorded retirement criterion (S6-9), not a permanent exception.

## Open Questions

- Adopting `contract.libraryDir`/`playlistsDir` inside the Engine export job paths (replacing `${musicStorageRoot}/library` derivations) is deferred until the active playlist/Traktor worker change lands, to keep this change's `engine-dj.nix` wiring additive and rebase-safe.
