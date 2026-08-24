## 1. Planning and draft reconciliation

- [x] 1.1 Review this proposal/design/spec set with the user and confirm the combined scope: AudioMuse/Navidrome integration plus mechanical `modules/services/music/` regrouping.
- [x] 1.2 Reconcile the existing draft implementation files against the accepted plan; do not assume prior draft code or checked boxes are correct.
- [x] 1.3 Run `openspec status --change "audiomuse-navidrome-integration" --json` and `openspec instructions apply --change "audiomuse-navidrome-integration" --json` immediately before implementation.

## 2. Music service regrouping

- [x] 2.1 Move music-owned service modules into `modules/services/music/` with a mechanical path-only rehome and no public option namespace migration.
  - refs: `modules/services/navidrome.nix`, `modules/services/beets/`, `modules/services/slskd.nix`, `modules/services/soulsync.nix`, `modules/services/tagr.nix`, AudioMuse module path after reconciliation
  - criteria: existing options such as `services.navidrome`, `services.beets`, and `services.slskd` remain stable
  - verify: `nix eval "path:$PWD#nixosConfigurations.oci-melb-1.config.applications.music.enable"`
- [x] 2.2 Audit Syncthing imports before moving or wrapping it; preserve compatibility for any non-music consumers.
  - refs: `modules/services/syncthing.nix`, `modules/applications/music/default.nix`
  - criteria: non-music Syncthing consumers, if any, still evaluate after the regroup
  - verify: repo-wide import search plus host evaluation
- [x] 2.3 Update documentation references to old music service paths.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `AGENTS.md` if it references moved paths
  - verify: no stale `modules/services/navidrome.nix`-style references remain except compatibility notes

## 3. AudioMuse service and Navidrome plugin integration

- [x] 3.1 Add or revise the AudioMuse service module under `modules/services/music/` with typed options for images, service paths, explicit enablement, music host secret input, and shared-Postgres durable state (no embedded Postgres container).
  - criteria: Redis/temp data are not promoted to canonical backup state unless implementation validation requires it; AudioMuse connects to `services.postgres-shared` for durable storage
  - verify: evaluate `config.services.audiomuse` for `oci-melb-1`
- [x] 3.2 Add `applications.music.audiomuse.enable` and compose AudioMuse/Navidrome plugin wiring only when that explicit feature toggle is enabled.
  - refs: `modules/applications/music/default.nix`
  - criteria: `applications.music.enable` can still evaluate without requiring AudioMuse
  - verify: evaluate both enabled and disabled toggle shapes if practical
- [x] 3.3 Extend the Navidrome music service module to include the AudioMuse plugin via `pkgs.navidromePlugins.audiomuseai` and set repo-owned runtime flags, while documenting UI/plugin settings that remain operator-managed.
  - criteria: plugin inclusion is declarative via nixpkgs package reference; brittle DB/plugin-state seeding is not introduced without a stable interface
  - verify: host evaluation includes the plugin derivation and runtime flags only when AudioMuse feature is enabled
- [x] 3.4 Add or refresh pinned OCI image references for AudioMuse core and Redis; verify current upstream versions, digests, and `aarch64-linux` suitability. (Navidrome plugin comes from `pkgs.navidromePlugins.audiomuseai` — not a separate pinned asset.)
  - refs: `policy/oci-images.nix`
  - criteria: OCI image refs are canonical and host evaluation succeeds; the plugin derivation resolves from the pinned nixpkgs input
  - verify: image refs pass host evaluation; `nix build` for the plugin derivation succeeds on the target architecture

## 4. Secrets, backups, operator docs, and deploy-found reconcile fixes

- [x] 4.1 Update the music secret template with AudioMuse keys without editing encrypted secret payloads manually.
  - refs: `secrets/.templates/applications/music.yaml`
  - criteria: template documents `audiomuse/user`, `audiomuse/password`, `audiomuse/api_token`, `audiomuse/jwt_secret`, and `audiomuse/postgres_password` or accepted equivalents
- [x] 4.2 Wire AudioMuse backup coverage for shared-Postgres durable state (via `services.postgres-shared` coverage), keeping Redis/temp out of canonical backup scope unless evidence requires inclusion.
  - refs: `modules/services/music/audiomuse.nix`, `modules/services/postgres-shared.nix`
  - verify: evaluated backup paths match shared-Postgres durable-state policy (no local Postgres volume backup)
- [x] 4.3 Update operator-facing docs/runbooks for deploy, first-run AudioMuse setup, Navidrome plugin configuration, and Symfonium similar/radio validation.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md` or a more specific runbook if present
  - criteria: docs distinguish deployed infrastructure from end-to-end validated behavior

- [x] 4.4 Add `audiomuse` database/user provision option to `services.postgres-shared` submodule.
  - refs: `modules/services/postgres-shared.nix`
  - criteria: enabling `services.postgres-shared.audiomuse.enable` creates the `audiomuse` database and user via `ensureDatabases`/`ensureUsers`, and adds a password/TCP authentication rule using `audiomuse/postgres_password`
  - verify: evaluate `config.services.postgresql.ensureDatabases` includes `"audiomuse"` when enabled
- [x] 4.5 Refactor audiomuse service module to connect to shared PostgreSQL instead of running an embedded Postgres container.
  - refs: `modules/services/music/audiomuse.nix`
  - criteria: `virtualisation.oci-containers.containers.audiomuse-postgres` is removed; `POSTGRES_HOST` in the env template points to `host.containers.internal:5432`; `POSTGRES_PASSWORD` is wired from the `audiomuse/postgres_password` secret; the `postgresImage` option is removed or marked deprecated
  - verify: `config.virtualisation.oci-containers.containers` no longer contains `audiomuse-postgres`; `config.sops.templates."audiomuse.env".content` includes `POSTGRES_PASSWORD`
- [x] 4.6 Remove embedded Postgres OCI container and associated systemd dependencies from audiomuse module.
  - refs: `modules/services/music/audiomuse.nix`
  - criteria: `podman-audiomuse-postgres.service` systemd unit, postgres tmpfiles rule (`${cfg.dataDir}/postgres`), and Postgres data volume mapping are removed; `postgresImage` option is removed; state-backup `dataBackupPaths` no longer references `${cfg.dataDir}/postgres`
  - verify: `systemd.services` does not include `podman-audiomuse-postgres` when audiomuse is enabled
- [x] 4.7 Add repo-pattern expectations for service restart on env/config file changes.
  - refs: `modules/services/music/audiomuse.nix`, repo conventions documentation
  - criteria: implement `systemd.services."podman-audiomuse-web".restartTriggers` and/or `systemd.services."podman-audiomuse-worker".restartTriggers` referencing the `.env` template path so that service restart is automatically triggered when the rendered environment file changes; establish this as the repo convention for OCI container services consuming SOPS-rendered env templates
  - verify: `systemd.services."podman-audiomuse-web".restartTriggers` or `systemd.services."podman-audiomuse-worker".restartTriggers` includes the `.env` template path
- [x] 4.8 Update audiomuse backup paths to reflect shared-Postgres coverage (remove local Postgres volume path from `dataBackupPaths`).
  - refs: `modules/services/music/audiomuse.nix`
  - criteria: `dataBackupPaths` no longer includes `${cfg.dataDir}/postgres`; backup coverage for AudioMuse durable state is satisfied by shared-Postgres backup (which is managed separately)
  - verify: `config.services.audiomuse.dataBackupPaths` does not include a postgres subdirectory
- [x] 4.9 Fix data directory ownership/permissions for audiomuse-redis and audiomuse-temp so containers can write at runtime.
  - refs: `modules/services/music/audiomuse.nix` (tmpfiles rules or directory-creation logic)
  - criteria: `${cfg.dataDir}/redis` is created with ownership/permissions allowing `audiomuse-redis` to write temp RDB files under `/data`; `${cfg.dataDir}/temp` has matching ownership; no permission-denied errors on container start
  - verify: deploy-apply succeeds without permission-denied for `audiomuse-redis` RDB writes; `journalctl` for `podman-audiomuse-redis` shows clean startup

## 5. Validation and acceptance

- [x] 5.1 Run `treefmt` or scoped formatting for touched Nix/Markdown/YAML files.
- [x] 5.2 Run `openspec validate --strict` for the change.
- [x] 5.3 Run `nix flake check --no-build` or `nix flake check --no-build "path:$PWD"` when untracked files must be visible to Nix.
- [x] 5.4 Run host-targeted evaluation/build checks that exercise `oci-melb-1` music stack wiring.
- [~] 5.5 Deploy to `oci-melb-1`, complete AudioMuse first-run setup and Navidrome plugin configuration, then validate actual Symfonium similar/radio behavior.
  - **Limitation:** Navidrome 0.61.2 (current nixpkgs) does not include the Sonic Similarity API (PR #5419). The AudioMuse plugin v8 exposes `getSimilarSongs`/`getSimilarSongs2`/`getArtistInfo` which work on 0.61.2, but the newer Sonic Similarity endpoints (`findSonicPath`, `getSonicSimilarTracks`) require Navidrome 0.62.0+ which is not yet in nixpkgs unstable. Full Sonic Similarity parity is deferred until nixpkgs packages 0.62.0.
  - criteria: final acceptance is real Symfonium behavior against the deployed stack
