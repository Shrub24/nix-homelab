## 1. Upstream package and module integration

- [x] 1.1 Add `github:Shrub24/traktor-m3u-sync` as a flake input and make its package plus `nixosModules.traktor-m3u-sync` module available to NixOS host evaluation.
  - refs: `flake.nix`, `flake.lock`
  - criteria: the upstream package and `nixosModules.traktor-m3u-sync` module can be referenced from the fleet configuration without vendoring local Python packaging; supported systems include `aarch64-linux`
  - verify: `nix flake metadata` or targeted `nix eval` confirms the input is present

- [x] 1.2 Confirm the upstream module/package interface and decide whether a thin local wrapper is needed before composing it.
  - refs: upstream `traktor-m3u-sync` module/package, `modules/applications/music/default.nix`, optional `modules/services/music/traktor-m3u-sync.nix`
  - criteria: implementation records whether the upstream `services.traktor-m3u-sync.*` module can be imported directly, or creates a thin local wrapper only for fleet defaults, ACLs, and stable music-stack composition
  - verify: targeted eval of `inputs.traktor-m3u-sync.nixosModules.traktor-m3u-sync` or `.default` and package attrs succeeds; chosen integration path is documented in code comments or docs

## 2. Music stack composition

- [x] 2.1 Compose Traktor M3U sync into the music stack using the upstream module where possible, or a thin `modules/services/music/` wrapper only if needed for fleet defaults.
  - refs: `modules/applications/music/default.nix`, optional `modules/services/music/traktor-m3u-sync.nix`
  - criteria: enabling `applications.music` can make manual Traktor export/import units available without changing unrelated music services
  - verify: targeted eval shows `traktor-m3u-sync-export.service` and `traktor-m3u-sync-import.service` exist when enabled

- [x] 2.2 Configure initial manual-sync paths for `oci-melb-1`.
  - refs: `modules/applications/music/default.nix`, `hosts/oci-melb-1/default.nix`
  - criteria: collection path is `/srv/media/traktor/collection.nml`; playlist workspace is under `/srv/media/playlists/traktor/`; export output and import input are distinct; Traktor-side root mapping remains explicit/configurable
  - verify: targeted eval prints the resolved collection/export/import path values

- [x] 2.3 Ensure required directories are created with music-stack-compatible ownership/permissions and ACLs.
  - refs: `modules/applications/music/default.nix`, service tmpfiles rules if wrapper is created
  - criteria: `/srv/media/traktor`, `/srv/media/playlists/traktor/export`, and `/srv/media/playlists/traktor/import` are created for operator/Syncthing use without becoming Beets inbox/quarantine paths; write access follows the existing `music-ingest` model and read access follows the existing `media` group ACL model
  - verify: targeted eval of `systemd.tmpfiles.rules` or upstream module directory settings shows the Traktor paths participate in the existing media ACL pattern

- [x] 2.4 Keep automation disabled for the first iteration.
  - refs: generated systemd timers/path units, upstream module options
  - criteria: no timer/path unit automatically starts Traktor export or import; upstream units keep `wantedBy = []`; manual `systemctl start traktor-m3u-sync-export.service` / `systemctl start traktor-m3u-sync-import.service` remains the trigger model
  - verify: targeted eval confirms no Traktor M3U timers/path units are enabled and the export/import units have no automatic `wantedBy` activation

- [ ] 2.5 Register Traktor manual units with centralized notification monitoring where appropriate.
  - refs: `hosts/oci-melb-1/default.nix`, `services.notification-daemon.monitor.services`
  - criteria: failed `traktor-m3u-sync-export.service` / `traktor-m3u-sync-import.service` units are visible through the existing notification-daemon monitoring path rather than bespoke notification logic
  - verify: targeted eval shows `traktor-m3u-sync-export` and `traktor-m3u-sync-import` appear in `services.notification-daemon.monitor.services`, or the implementation documents why registration is deferred
  - note: deferred — Traktor is pivoting away and the units stay disabled (`applications.music.traktorM3uSync.enable = false`); no monitor registrations were added, to avoid phantom monitored units.

## 3. Operator documentation

- [x] 3.1 Document the manual Traktor playlist sync workflow and safety model.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`
  - criteria: docs explain Syncthing-sourced `collection.nml`, separate export/import playlist directories, placeholder path mapping, manual `systemctl start` usage, import sandbox/backup caution, and follow the docs maintenance rule for behavior/trust-boundary changes
  - verify: documentation references the configured paths and explicitly states no automation is enabled yet

## 4. Validation and handoff

- [x] 4.1 Run the repository validation workflow for the proposed integration.
  - refs: OpenSpec artifacts, flake outputs, `justfile`, `.just/checks.just`
  - criteria: the change passes the same validation path used by CI/operators, with OpenSpec validation as a supplementary artifact check
  - verify: `just check`; `openspec validate "traktor-m3u-sync-worker" --strict`

- [ ] 4.2 Deploy and run a first manual export smoke test when a real `collection.nml` is present.
  - refs: `oci-melb-1` deployed systemd units
  - criteria: operator can run the export unit manually and inspect generated M3U output; import remains optional and manual
  - verify: `systemctl start traktor-m3u-sync-export.service` on `oci-melb-1`; inspect `/srv/media/playlists/traktor/export`
