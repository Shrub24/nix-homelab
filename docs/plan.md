# Plan

This plan is intentionally strategic, not a command-by-command runbook. The goal is to preserve intent, decision quality, and migration clarity while implementation details are researched incrementally.

## Planning Objective

Transition this repository from legacy `dev-vps` orientation to a clean, modular fleet-infrastructure repository that can reliably bootstrap and operate `oci-melb-1`, then scale to more hosts including `do-admin-1`.

## Planning Constraints

- first host is cloud-hosted and architecture differs from local control machine
- repository currently contains significant legacy configuration and documentation
- migration should reduce confusion, not increase parallel architectures
- initial service baseline should remain operationally simple
- active package baseline is `nixos-unstable` by default; fallback package-set divergence is exception-only and must be explicitly documented

## Execution Strategy

## 1) Stabilize architecture intent first

- keep architecture and decision documents authoritative
- avoid implementation drift that contradicts accepted decisions

## 2) Migrate repository shape aggressively but safely

- remove or archive obsolete paths tied to old mission
- establish host-centric and module-centric structure for the new mission
- keep changes coherent enough that future fleet tooling can be introduced without major reshaping

## 3) Bootstrap first host with minimum sharp edges

- prioritize deterministic and debuggable first-host bring-up
- preserve break-glass access assumptions during early networking transitions

## 4) Add service baseline, then iterate with observed behavior

- `syncthing` + `navidrome` are initial service baseline
- tune behavior from real usage and sync conflict observations

## 5) Defer high-complexity systems until pressure exists

- orchestration stack, worker graph, and internet edge concerns are deferred by design

## Working Tracks

Track A: Repository migration

- simplify repository mission expression
- align naming and structure to fleet model
- eliminate stale documentation that implies old operating model

Track B: Secrets and identity model

- enforce scoped secret topology via `.sops.yaml`
- use topology-aligned secret buckets:
  - `secrets/applications/<name>.yaml` for multi-service application stacks
  - `secrets/services/<name>.yaml` for standalone leaf services
  - `secrets/hosts/<host>/system.yaml` for host-only bootstrap/system material
  - `secrets/hosts/<host>/oidc.yaml` for cross-host OIDC handshake material
- keep ciphertext encrypted directly to host/admin recipients via `age`
- derive normal secret reader scope from host feature enables (`applications.<name>.enable`, `services.<domain>.<name>.enable`)
- maintain explicit exception handling for cross-host readers (OIDC handshakes)
- keep `secrets/templates/*.yaml` as unencrypted reference templates for each encrypted bucket
- deep leaf modules own their own `sops.secrets`/`sops.templates` registrations; application modules pass through `secretFiles.*` bindings
- keep `lib/secrets.nix` as a light reusable helper library for common secret-contract patterns
- keep validation separate from configuration authority: `.sops.yaml` remains SSOT, while repo checks live under `tests/`
- default host recipient bootstrap via live SSH host key to age derivation, with injected-key override available
- keep host enrollment artifacts and policies explicit

Track C: Host and storage baseline

- establish reliable host bootstrap path
- stage remote network-owner transitions so access survives the change window
- maintain a console-only break-glass user baseline with host-scoped recovery password material and a routine reboot exercise on active remote hosts
- apply predictable persistent storage contracts with explicit mounts for service state, media, and host-critical store paths where required
- map service directories on those mounts predictably
- keep provider-specific storage contracts isolated so new hosts do not couple to `oci-melb-1` bootstrap config
- preserve a documented rescue workflow for storage/mount breakage, including offline rebuild of bootable generations

Track D: Service baseline

- deploy private-only Tailscale access model
- deploy bidirectional Syncthing with safety controls
- deploy Navidrome reading direct sync path
- deploy AudioMuse as an optional Navidrome similarity extension (Podman containers, Postgres, Navidrome plugin); deployment lifecycle distinguishes infrastructure deployed from E2E Symfonium-validated behavior
- keep quarantine in synced scope and visible playback surface while library remains canonical promotion target
- keep music service composition explicit through `modules/applications/music.nix`
- keep music service modules regrouped under `modules/services/music/` for navigability without changing option namespaces
- keep private admin service composition explicit through `modules/applications/admin/default.nix`
- keep the admin surface split between reusable service modules and host-owned source/route inputs (for example Quantum sources and Cockpit host overlays)
- evolve Beets via native systemd-based inbox-to-library promotion under `/srv/media/library` while keeping `/srv/media` playback visibility
- support a secondary approved-quarantine promotion runner for manual re-attempt workflows

Track E: Future-ready evolution

- keep layout compatible with later fleet deployment tooling
- reserve integration points for future media processing hooks
- reserve path for later `rclone`/VFS transition
- defer app-based review UX and higher-complexity orchestration while report-first promotion remains sufficient

## Success Criteria (Strategic)

The plan is succeeding when:

- repository intent is unambiguous from docs and directory structure
- legacy `dev-vps` assumptions no longer drive active configuration
- first host bootstrap path is reliable and repeatable
- service baseline is operational with current data flow expectations
- unresolved concerns remain explicitly documented rather than implicit

## Non-Goals During Current Planning Window

- writing full operational runbooks before baseline architecture settles
- selecting long-term orchestration and worker framework now
- optimizing for hypothetical future scale at the cost of current clarity

## Documentation Maintenance Rule

Any major implementation decision that changes behavior, trust boundaries, or migration direction must update:

- `docs/architecture.md`
- `docs/decisions.md`
- `docs/plan.md`

These documents are intended to remain current and drive implementation, not trail it.

Active implementation anchor paths that must stay reflected in docs:

- `hosts/oci-melb-1/default.nix`
- `hosts/do-admin-1/default.nix`
- `modules/applications/music.nix` (or `modules/applications/music/default.nix` as sub-module root)
- `modules/applications/admin/default.nix`
- `modules/services/music/` (canonical music service module subtree: `navidrome.nix`, `audiomuse.nix`, `syncthing.nix`, `beets/`, `slskd.nix`, `soulsync.nix`, `tagr.nix`)
- `modules/core/base.nix`
- `modules/profiles/base-server.nix`
- `modules/services/tailscale.nix`
- `modules/services/termix.nix`
- `modules/services/admin/quantum.nix`
- `modules/services/admin/cockpit.nix`

Maintenance requirement: changes to active architecture paths, trust boundaries, or operator/CI commands must update canonical docs in the same change window. For features that distinguish deployed infrastructure from end-to-end validated behavior (e.g. AudioMuse first-run setup, Navidrome plugin configuration, Symfonium validation), docs must clearly separate the deployment-complete state from the E2E-accepted state.

Current operator/validation entrypoints that docs should track when they change:

- `just check`
- `just tofu-sync`
- `just tofu-runtime`
- `tests/check-secret-scope.sh`
- `tests/check-web-services-policy.sh`
- `scripts/export-web-services-policy.sh`
- `scripts/render-opentofu-cloudflare-runtime.sh`
