## 1. Stage 5 baseline and ownership inventory

- [x] 1.1 Capture the mandatory clean Stage 5 baseline from exactly `ee774aa622aa8a572a34cfcc534f00b2538cbde0` before any implementation edit.
  - refs: `openspec/changes/dendritic-stage-6-music-composition/design.md` (S6-1, S6-12), `flake.nix`, `modules/flake/registry.nix`
  - criteria: Create a clean detached checkout/worktree of commit `ee774aa622aa8a572a34cfcc534f00b2538cbde0`; if the commit is not present locally, fetch it and record the resolved hash before any edit — never reconstruct baseline content from the working tree. Record its absolute path and clean status; evaluate from `path:<recorded-absolute-path>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` rather than reconstructing configuration; capture per-host toplevel/closure inputs and the full structured observable JSON defined by S6-12 for `oci-melb-1`, `la-admin-1`, and `home-forge`; record pre-existing failures. No implementation task starts until the captures are complete.
  - delegate: BuildAgent
  - verify: `git -C <baseline-path> rev-parse HEAD` prints `ee774aa622aa8a572a34cfcc534f00b2538cbde0`; `git -C <baseline-path> status --porcelain` is empty; all capture commands and actual output paths are recorded; `nix eval --raw 'path:<baseline-path>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'` succeeds for every host.

- [x] 1.2 Inventory exact source ownership and every behavior block in the 792-line coordinator before moving or deleting anything.
  - refs: `modules/applications/music/default.nix`, `modules/applications/music/files/`, `modules/services/music/`, `modules/applications/dj/engine-dj.nix`, `modules/flake/dj.nix`, `modules/flake/registry.nix`, `modules/hosts/home-forge/default.nix`
  - criteria: Record current files, symbols, imports, consumers, option namespaces, and destination owner for every coordinator block: `cfg`/`secretHelpers`/`mediaPaths`; Beets config sources and rendered fallback; `ffmpeg-preprocess`; four Beets operator binaries; `media-fixperms`; slskd completion hook; Beets secret entries/template/secret builders; all runner instances; private-leaf imports; every `applications.music.*` option; required-secret assertion; SOPS templates/secrets; groups/dev memberships; Syncthing/Navidrome/AudioMuse/Beets/slskd/Tagr wiring; all state-backup contracts; permission reconcile; success chain/import-ready flag; ffmpeg/path/poke/timers/polkit; package and zsh contributions; every tmpfiles/ACL rule. Inventory all files under the old `files/` directory and pin exact move destinations; deletion of `modules/applications/music/` is blocked until every row has one retained composition owner or one private leaf owner and matching baseline observable.
  - delegate: CodeScout
  - depends: 1.1
  - verify: Exhaustive source/reference results reconcile with lines 1–792 and every file in `modules/applications/music/files/`; no unowned block, script, option, import, unit, timer, path, ACL, package, secret/template field, or backup entry remains.

## 2. Beets ownership extraction

- [x] 2.1 Move Beets secret registration and rendered configuration ownership into the existing Beets leaf without changing secret bootstrap.
  - refs: `modules/applications/music/default.nix`, `modules/applications/music/files/beets-config.yaml`, `modules/applications/music/files/beets-quarantine-config.yaml`, `modules/services/music/beets/default.nix`, `lib/secrets.nix`
  - criteria: Move both Beets YAML inputs into `modules/services/music/beets/files/`; make `applications.music.configFiles` defaults point there; move `sops.secrets.beets_*` and both `sops.templates` definitions into the leaf; add read-only `services.beets.renderedConfigFiles.{standard,quarantine}` as an unconditional option declaration/value (placed outside the existing secret-file `lib.mkIf (cfg.secretFiles.host != null)` gate) that prefers `config.sops.templates.*.path` when available and otherwise falls back to the source `configFiles` paths, with no cycle through `runners`. Preserve every SOPS file value, key, placeholder, `/run/secrets/beets.*` path, owner `beets`, group `beets`, mode, and rendered library/state/convert value exactly. Do not decrypt or edit `secrets/**`, `.sops.yaml`, or ciphertext; this change introduces no secret bootstrap change.
  - delegate: OpenDevopsSpecialist
  - depends: 1.2
  - verify: Focused `home-forge` eval compares `sops.secrets`, `sops.templates`, and `services.beets.renderedConfigFiles` with the Stage 5 capture; source/config move review finds no content drift; `nix eval --raw '.#nixosConfigurations.home-forge.config.system.build.toplevel.drvPath'` succeeds.

- [x] 2.2 Move the Beets operator CLIs and Beets-state tmpfiles into the Beets owner while leaving runner policy in composition.
  - refs: `modules/applications/music/default.nix`, `modules/applications/music/files/merge-splits.sh`, `modules/applications/music/files/prune-empty-dirs.sh`, `modules/services/music/beets/default.nix`, `modules/services/music/beets/runners.nix`
  - criteria: The Beets leaf owns `beets-interactive`, `beets-dupes`, `beets-merge-splits`, and `beets-prune-empty`, their system-package entries, moved helper scripts, and only Beets data/state/log/dev-ACL tmpfiles; command text, runtime inputs, environment, users/groups, paths, and runner invocation remain equivalent. `beets-interactive` consumes `cfg.onSuccessUnits` and preserves the exact post-success systemd unit set/order. `runners.nix` remains unchanged; composition still selects configs, runner instances, and success-chain intent.
  - delegate: OpenDevopsSpecialist
  - depends: 2.1
  - verify: Compare package names, generated command text, Beets tmpfiles, runner units, `services.beets.onSuccessUnits`, and `services.beets.importReadyFlag` with Stage 5; confirm `modules/services/music/beets/runners.nix` has zero diff; run the focused home-forge drvPath eval.

## 3. Ingest and storage private leaves

- [x] 3.1 Extract ingest mechanisms into the independently reviewable private `services.musicIngest` leaf.
  - refs: `modules/applications/music/default.nix`, `modules/applications/music/files/ffmpeg-preprocess.sh`, `modules/services/music/ingest.nix`, `modules/services/music/files/ffmpeg-preprocess.sh`
  - criteria: Add private `modules/services/music/ingest.nix` with explicit `inboxDir`, `storageRoot`, `stateDirectory`, `readyFlag`, `onSuccessUnit`, and read-only `downloadCompleteScript` interfaces; move `ffmpeg-preprocess` binary/service, `dropbox-inbox.path`, `dropbox-poke.service`, `dropbox-settle.timer`, `slskd-settle.timer`, slskd completion hook, scoped polkit rule, package contribution, and script file to this owner. Preserve script bytes, unit names, triggers, `OnSuccess`, timer values, hardening, `StateDirectory`, ready flag `/var/lib/beets/ffmpeg-preprocess/inbox-ready`, and authorization behavior.
  - delegate: OpenDevopsSpecialist
  - depends: 2.2
  - verify: Compare ingest services/timers/paths, polkit text, package/script output, and ready flag against Stage 5; run `nix eval --raw '.#nixosConfigurations.home-forge.config.system.build.toplevel.drvPath'` immediately after the ingest batch.

- [x] 3.2 Extract storage ownership into the independently reviewable private `services.musicStorage` leaf.
  - refs: `modules/applications/music/default.nix`, `modules/services/music/storage.nix`, `modules/services/music/beets/default.nix`
  - criteria: Add private `modules/services/music/storage.nix` with explicit storage/library/playlists/inbox/quarantine/version-archive inputs and equivalent untagged/approved derivation; move group GIDs (`music-ingest = 990`, `media = 987`), all media root/`.versions`/library/playlists/quarantine/untagged/approved/inbox/dropbox tmpfiles and ACLs, slskd/tagr environment-file rules, `media-permission-reconcile`, `media-fixperms`, and its package contribution into this owner. Preserve root execution, mounts, command body, paths, modes, owners/groups, ACLs, unit name, and permissions exactly; keep `users.users.dev.extraGroups` composition-owned.
  - delegate: OpenDevopsSpecialist
  - depends: 2.2
  - verify: Compare all storage tmpfiles/ACL rules, GIDs, reconcile service definition, and package output with Stage 5; evaluate the home-forge drvPath after this storage batch independently of aspect wiring.

## 4. Music aspect, contributor wiring, and DJ contract

- [x] 4.1 Publish the discovered `music` contributor and relocate only composition ownership into it.
  - refs: `modules/applications/music/default.nix`, `modules/flake/music.nix`, `modules/services/music/`, `openspec/changes/dendritic-stage-6-music-composition/design.md` (S6-2, S6-4, S6-8, S6-9)
  - criteria: Add discovered `modules/flake/music.nix` publishing `flake.modules.nixos.music`; selecting it sets `applications.music.enable = true`; import all private music leaves explicitly. Keep inline only the inventory's composition-owned options, path derivation, required-secret assertion, feature choices, service/backup selection and wiring, secret-file passthrough, runner instances, `renderedConfigFiles` consumption, dev groups/zsh alias, and success-chain intent. Wire `services.musicIngest` and `services.musicStorage` only through explicit strings/paths; no leaf reads `applications.music`; no cycle is introduced. Private files under `modules/services/music/**` publish no aspects and the four-root filter remains exactly `applications`, `hosts`, `providers`, `services`.
  - delegate: OpenDevopsSpecialist
  - depends: 3.1, 3.2
  - verify: Evaluate home-forge and compare composition observables with Stage 5; inspect the dependency directions from S6-8; confirm only `modules/flake/music.nix` adds the publication and no private leaf is discovered/published.

- [x] 4.2 Select `aspects.music` only on home-forge, remove legacy ownership, and prove discovery remains inert elsewhere.
  - refs: `modules/flake/registry.nix`, `modules/hosts/home-forge/default.nix`, `modules/applications/music/`, `modules/flake/_unconverted-nixos-dirs.nix`
  - criteria: Add `aspects.music` to the home-forge registry record only; remove the host's direct music import and redundant `applications.music.enable = true`; retain host-specific `dataRoot`, `storageRoot`, secret file, Navidrome/AudioMuse variants, and Postgres host. Delete `modules/applications/music/` only after inventory reconciliation proves all content moved. On `oci-melb-1` and `la-admin-1`, discovery alone leaves `(c.applications.music or {})` empty and activates no music service, unit, tmpfile, secret, or package; a mutation removing `applications.music.enable = true` from the selected aspect leaves selection present but the music contract/application disabled.
  - delegate: OpenDevopsSpecialist
  - depends: 4.1
  - verify: Focused evals for all three hosts pass; mutation probes (each evaluated as `path:<throwaway-copy>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`, never a shallow `.config` read) prove selection-owned enablement and discovery inertness; exhaustive imports find no host import of the deleted coordinator/private leaves; filter output remains exactly `["applications","hosts","providers","services"]`.

- [x] 4.3 Add the typed music storage/library contract and additive DJ consumption with the named failure contract.
  - refs: `modules/flake/music.nix`, `modules/flake/dj.nix`, `modules/applications/dj/engine-dj.nix`, `modules/hosts/home-forge/default.nix`, `openspec/changes/dendritic-stage-6-music-composition/design.md` (S6-3, S6-11)
  - criteria: Expose read-only typed `applications.music.contract.{storageRoot,libraryDir,playlistsDir}` from current values, declared inside the composition's `lib.mkIf cfg.enable` body (so it is absent, not empty, when the aspect is unselected); have DJ read `config.applications.music.contract or null` without importing/enabling music; keep `applications.dj.engine.sharePath` and `musicStorageRoot` typed `lib.types.str` (never `nullOr`) and give both the safe default `if musicContract != null then musicContract.storageRoot else ""`; retain explicit host override support; remove only the duplicate host root/share literals; add the exact named assertion from S6-3 with semantics `musicContract != null || (sharePath != "" && musicStorageRoot != "")`, active only when the engine is enabled. `music` and `dj` remain separately selected. DJ-without-music is allowed only when the host explicitly sets both values non-empty, otherwise it fails with the named assertion message (not a null/missing-attribute error); music-without-DJ evaluates successfully. Explicitly defer/out-of-scope adoption of `contract.libraryDir` or `contract.playlistsDir` in active Engine export/worker job paths.
  - delegate: OpenDevopsSpecialist
  - depends: 4.2
  - verify: Throwaway mutations prove the named DJ-missing-music failure and music-without-DJ success; home-forge `sharePath` and `musicStorageRoot` both remain `/srv/storage/media/music`, and `traktorStateDir` remains its Stage 5 value; no hidden import or enable edge exists.

- [x] 4.4 Enforce the S6-11 worker freeze while reviewing the DJ contract diff.
  - refs: `modules/applications/dj/engine-dj.nix` (re-pinned at implementation start), `openspec/changes/navidrome-m3u-itunes-worker/`, `openspec/changes/traktor-m3u-sync-worker/`
  - criteria: The contract diff is additive/current-value preserving only. Re-pin the forbidden symbol/range set from the current file via symbol search at implementation start, not from stale line numbers; the pinned set is: `playlistSyncFetch` / `playlistSyncBin` script text, `services.traktor-m3u-sync.jobs.{navidrome,engine,itunes}`, `state-backups.services.engine-dj` prepare/cleanup commands, the `windows-vm` instance, `dj-library-writers.target` bindings, and the `Engine Library` tmpfiles. Do not edit unit mutual exclusion, worker scripts, timers, playlist behavior, or Traktor behavior. Do not replace active worker derivations with `contract.libraryDir`/`playlistsDir`; rebase contract wiring after overlapping worker changes if necessary.
  - delegate: CodeReviewer
  - depends: 4.3
  - verify: Diff the re-pinned symbol/range bodies against the pre-task tree and Stage 5 capture; all forbidden bodies are unchanged, except surrounding line movement attributable solely to additive defaults/assertion; no playlist/Traktor behavior edit is present.

## 5. Contract tests and negative mutations

- [x] 5.1 Update the dendritic scaffold contract for exact Stage 6 publication, selection, privacy, and observables.
  - refs: `tests/check-dendritic-scaffold-contract.sh`, `modules/flake/music.nix`, `modules/flake/registry.nix`, `modules/services/music/`
  - criteria: Change the exact publication contract from 14 to 15 by adding `flake.modules.nixos.music`; change the exact home-forge selection set to add `aspects.music`; leave OCI/LA selection sets unchanged; keep the filter exact at the same four roots. Assert privacy by owner rather than by a hardcoded operational predicate: (a) an exhaustive host-tree grep forbidding any direct `modules/services/music` import from `modules/hosts/**`, (b) a publication-exclusion check over every private music leaf (each file under `modules/services/music/**` publishes no `flake.modules.nixos` aspect), and (c) an explicit owner-import check that only the music concern owner (`modules/flake/music.nix`) imports those leaves. Add focused music probes for selection enablement, contract paths, units, timers/paths, tmpfiles, groups, packages, Beets wiring, and DJ values without weakening existing Stage 1–5 checks.
  - delegate: TestEngineer
  - depends: 4.4
  - verify: `bash tests/check-dendritic-scaffold-contract.sh` passes on the unmodified implementation and reports exact semantic set/value differences for prepared publication, selection, privacy, or observable drift.

- [x] 5.2 Add semantic throwaway mutations for music selection, privacy, and the DJ contract.
  - refs: `tests/check-dendritic-scaffold-contract.sh`, `modules/flake/music.nix`, `modules/flake/dj.nix`, `modules/applications/dj/engine-dj.nix`, `modules/flake/registry.nix`
  - criteria: Mutations detect discovery-without-selection activation on OCI/LA; removal of selected aspect enablement; host/private-leaf direct import; private-leaf publication/discovery; deletion of the music contributor; DJ selected/enabled without music or explicit root fails with the exact named assertion; DJ without music but with both `sharePath` and `musicStorageRoot` explicitly non-empty succeeds; music selected without DJ succeeds and retains music observables. Every negative/positive mutation must be evaluated as the full toplevel `path:<throwaway-copy>#nixosConfigurations.<host>.config.system.build.toplevel.drvPath` (never a shallow `.config` read). Mutations operate only in throwaway copies and cannot alter the working tree.
  - delegate: TestEngineer
  - depends: 5.1
  - verify: Run each mutation and record that it fails or succeeds for its intended semantic reason; rerun `bash tests/check-dendritic-scaffold-contract.sh` on the clean working tree and confirm PASS.

## 6. Current documentation and D-052

- [x] 6.1 Record D-052 and reconcile the exact current-state paths without rewriting history.
  - refs: `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/context-history.md`, `docs/dendritic-transition-analysis.md`, `openspec/changes/dendritic-stage-6-music-composition/{proposal.md,design.md,specs/,tasks.md}`
  - criteria: Add D-052 describing the home-forge-only discovered `music` aspect, selection-owned enablement, separate `music`/`dj` aspects, private `modules/services/music/**` implementation owners, explicit DJ storage/library contract, unchanged four-root filter, and the retirement criterion for the transitional services root. D-052 supersedes only the music-deferral clause of D-050/D-051. Current docs name `modules/flake/music.nix`, `modules/services/music/beets/{default.nix,runners.nix,files/}`, `modules/services/music/{ingest.nix,storage.nix,files/ffmpeg-preprocess.sh}`, `modules/flake/registry.nix`, and the separate DJ paths accurately; state that worker adoption of contract `libraryDir`/`playlistsDir` is deferred. Reconcile the exact current-state paths in root `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md` plus the existing `docs/*` set without rewriting history. State explicitly: no secret bootstrap change, no deployment, and no archive operation.
  - delegate: CoderAgent
  - depends: 5.2
  - verify: Path/link review matches the implemented tree; `git diff --check` passes; hashes/diff prove `openspec/changes/archive/**` is byte-identical and no other active change artifact was edited.

## 7. Validation, equivalence, and review gates

- [x] 7.1 Run focused evaluation after every structural group, then repository-wide formatting and validation.
  - refs: `tests/check-dendritic-scaffold-contract.sh`, `treefmt.toml`, `.just/checks.just`, `flake.nix`
  - criteria: Evidence includes a successful focused home-forge drvPath eval after Beets, ingest, storage, and aspect/host/DJ wiring groups; final `bash tests/check-dendritic-scaffold-contract.sh`, `treefmt --fail-on-change`, `just checks all`, and `nix flake check --no-build` pass; all three host drvPaths evaluate. Failures are fixed only within this change's scope.
  - delegate: BuildAgent
  - depends: 6.1
  - verify: Run `nix eval --raw '.#nixosConfigurations.home-forge.config.system.build.toplevel.drvPath'` after each named group; finally run `bash tests/check-dendritic-scaffold-contract.sh`, `treefmt --fail-on-change`, `just checks all`, `nix flake check --no-build`, and `nix eval --raw '.#nixosConfigurations.{oci-melb-1,la-admin-1,home-forge}.config.system.build.toplevel.drvPath'` (or one exact command per host), retaining command/status evidence.

- [x] 7.2 Compare exact structured observables and classify every closure delta against clean Stage 5.
  - refs: baseline captures from task 1.1, `openspec/changes/dendritic-stage-6-music-composition/design.md` (S6-12), all three `nixosConfigurations`
  - criteria: Before/after JSON is exactly equal per host for systemd music service keys/full definitions, timer/path keys, tmpfiles including slskd/tagr file rules, SOPS secret metadata and template metadata/content, system package names, music/media GIDs and dev groups, `programs.zsh.shellAliases.b`, the exact `security.polkit.extraConfig` text, `services.slskd.downloadCompleteScript` (derivation/path and, as feasible, rendered content), named state-backup contracts, Beets success/ready values, and DJ engine values; home-forge derived share/root remain `/srv/storage/media/music` and state dir remains unchanged; OCI/LA remain music-inert. Run per-host `nix diff-closures`; classify every difference as unchanged, source-order only, or derivation/store-path rename caused solely by relocation/nesting. Any runtime, secret, policy, route, topology, filter, input, permission, unit, timer, path, package, backup, or worker difference blocks completion.
  - delegate: BuildAgent
  - depends: 7.1
  - verify: Machine-readable equality report is clean; per-host closure reports carry an explicit provenance classification for every delta and no unexplained item; actual capture paths point to the clean `ee774aa6` worktree and current checkout.

- [x] 7.3 Obtain final independent review and close strict scope gates without deploying or archiving.
  - refs: `openspec/changes/dendritic-stage-6-music-composition/{proposal.md,design.md,specs/,tasks.md}`, `.sops.yaml`, `secrets/`, `policy/`, `modules/flake/_unconverted-nixos-dirs.nix`, `flake.nix`, `flake.lock`
  - criteria: CodeReviewer reports no unresolved high/medium correctness, ownership, security, behavior-equivalence, worker-overlap, or rollback finding; parent agent alone updates checkboxes. Strict OpenSpec validation passes. Final diff contains no secret decryption/edit, `.sops.yaml`, policy, route, provider, edge/admin, deploy topology/order/target, filter, flake input/lock, playlist/Traktor behavior, archive-history, or unrelated active-change diff. No deployment and no OpenSpec archive command is run.
  - delegate: CodeReviewer
  - depends: 7.2
  - verify: Run `openspec validate dendritic-stage-6-music-composition --strict`; inspect the complete diff and scope guards; reconcile all 16 parent checkboxes to evidence; record review result and leave the change unarchived and undeployed.
