## Why

Dendritic Stages 1–5 separated source ownership from deployment granularity, but music remains the application conversion explicitly deferred by D-051 (many source conversions remain): `modules/applications/music/default.nix` is a 792-line evaluator-class coordinator imported directly by `home-forge`, and it doubles as composition root and implementation owner. Its audit shows wrong ownership: Beets secret/config-template assembly, operator binaries, concrete runner/timer/path/polkit mechanics, permission-reconcile unit body, and tmpfiles ACL implementation all live in the coordinator instead of their leaf services. DJ couples through host-supplied paths rather than an explicit music contract. The user approved a real redesign now rather than mechanically wrapping the coordinator, provided nothing changes behavior.

**Core Value:** Publish a home-forge-only `music` deployment aspect whose selection provides `applications.music.enable`, move implementation ownership into private leaf services, and give `dj` an explicit music library/storage contract — with zero behavior change.

## What Changes

- Add discovered flake-parts contributor material under `modules/flake/` defining `flake.modules.nixos.music`. It is discovered everywhere but selected only on `home-forge`; selection provides `applications.music.enable = true`, so the host drops its direct `modules/applications/music` import and `enable = true` and the registry gains `aspects.music`.
- The `music` aspect nests the retained composition ownership inline: shared path derivation (`mediaPaths`), service selection/wiring, `secretFiles.host` passthrough, backup policy co-selection, feature variants (`navidrome.enable`, `audiomuse.*`), success-chain intent (`onSuccessUnits`), and the explicit music library/storage contract.
- Move implementation ownership out of the coordinator into private lower-level leaves under `modules/services/music/**`, imported by the aspect and **not** published as aspects:
  - Beets secret registration and config-template rendering (`sops.secrets`, `sops.templates`, secret keys/placeholders) into the Beets leaf.
  - Operator binaries (`beets-interactive`, `beets-dupes`, `beets-merge-splits`, `beets-prune-empty`, `media-fixperms`, `ffmpeg-preprocess`) and concrete runner/timer/path/polkit mechanics into their owning leaves.
  - Permission-reconcile implementation and the tmpfiles ACL rules into the media-owning leaf.
- Keep `dj` a separate aspect that consumes the explicit music storage/library contract via policy co-selection with a named assertion, and never imports or enables `music`. DJ keeps `types.str` share/root options with safe `""` defaults derived from `contract.storageRoot` when present, and a named assertion requires either the contract or both explicit non-empty values — so DJ without music is allowed only with both explicit values, never with a null/missing-attribute error.
- Preserve every option namespace (`applications.music.*`, `services.beets.*`, `services.navidrome.*`, …), path, unit name, timer, and runtime behavior; keep the four-root filter (`applications`, `hosts`, `providers`, `services`) unchanged.

### Constraints

- No playlist/Traktor worker behavior changes: no edits to unit mutual exclusion, worker scripts, or timers. Active playlist changes overlap `engine-dj`; prefer rebasing after they land, and keep contract edits additive/current-value preserving only.
- No flake input changes.
- Excluded: `secrets/**`/`.sops.yaml`, policy, routes, admin, edge, providers, standalone services, deploy topology, a filter shrink, public option-namespace migration, or product behavior.
- Music service files stay private leaves, not individually published aspects.
- Behavior-preserving: unexplained evaluated or runtime differences against the deployed Stage 5 baseline are blocking.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `feature-topology`: An application deployment aspect may be published from a discovered contributor whose selection provides that application's top-level enablement (`music` provides `applications.music.enable`); the application's service files remain private leaves rather than aspects; and `dj` consumes an explicit music library/storage contract through policy co-selection with a named assertion instead of an import side effect.
- `media-services`: The music composition keeps shared path derivation, service selection/wiring, secret-file passthrough, backup co-selection, variants, and success-chain intent, while secret/template assembly, operator binaries, runner mechanics, ingest timer/path/polkit wiring, and permission implementation are owned by their leaves; paths, units, and permissions are unchanged.
- `beets-automation`: The reusable Beets framework leaf owns Beets secret registration plus rendered config-template assembly and the operator CLI binaries generated from built-in runner kinds; the music workflow composition keeps selecting configs, runner instances, and the `OnSuccess` chain intent.
- `beets-workflow-stages`: Stage instantiation stays application-owned and composition still selects concrete runner instances/policy, but the Beets config assets move from `modules/applications/music/files/` to the leaf-owned `modules/services/music/beets/files/`.

Related specs inspected: `engine-dj-library` (requirements unchanged — this change only makes the DJ side consume the existing music storage/library value explicitly, so no delta) and `navidrome-scan-trigger` (unchanged).

## Impact

- Affected code (estimated 9–11 implementation files, honest range): new `modules/flake/music.nix`; Beets owner changes (`modules/services/music/beets/default.nix` plus moved `files/beets-{config,quarantine-config}.yaml`, `merge-splits.sh`, `prune-empty-dirs.sh`); new `modules/services/music/ingest.nix` with `modules/services/music/files/ffmpeg-preprocess.sh`; new `modules/services/music/storage.nix`; `modules/applications/dj/engine-dj.nix` (additive contract only); `modules/flake/registry.nix` (`aspects.music` on home-forge); `modules/hosts/home-forge/default.nix` (import/enable removal); and deletion of `modules/applications/music/default.nix` + its `files/` directory. The composition relocates into `modules/flake/music.nix`; no separate private composition leaf is added.
- Contracts/tests: extend `tests/check-dendritic-scaffold-contract.sh` for the new publication set (14 → 15), the home-forge selection set (adds `aspects.music`), and the as-yet-unpublished private music leaves.
- Docs: root `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md` plus `docs/{architecture,decisions,plan,context-history,dendritic-transition-analysis}.md`; a decision records the Stage 6 ownership/contract split and supersedes the music-deferral clause of D-050/D-051 for `music` only — `dj` stays a separate aspect.
- Verification: `nix build` each host top-level. The hard gate is behavior equality against deployed Stage 5 captures (music units, paths, permissions, Beets secrets/templates, DJ share/contract) with an explicit provenance-only allowlist for source-order and store-path differences.
- No new flake inputs, packages, runtime services, secrets, routes, or deploy targets.
