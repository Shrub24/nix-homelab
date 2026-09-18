# Plan

This plan is intentionally strategic, not a command-by-command runbook. The goal is to preserve intent, decision quality, and migration clarity while implementation details are researched incrementally.

## Planning Objective

Transition this repository from legacy `dev-vps` orientation to a clean, modular fleet-infrastructure repository that can reliably bootstrap and operate `oci-melb-1` and the active admin/edge host `la-admin-1` (the decommissioned host has been removed).

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
- keep music service composition explicit through the discovered `music` deployment aspect `modules/flake/music.nix` (selected on `home-forge` only; selection provides `applications.music.enable`), with the private implementation leaves under `modules/services/music/**`
- keep music service modules regrouped under `modules/services/music/` for navigability without changing option namespaces
- run the complete music application on `home-forge` under the host-selected music application root `/srv/storage/media/music/{library,playlists,inbox,quarantine,.versions}`, with AudioMuse's database in OCI's shared Postgres over Tailscale and LA edge routes for music/slskd/tagr pointing at `home-forge`; playlist export/import for Engine DJ is owned by a separate repository
- keep admin service composition in independently selected aspects: `identity-provider` (Kanidm), `cockpit`, and the individual workload aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`; there is no `admin-hub` bundle (D-054), and Quantum is removed from the active module graph as disabled/deferred
- keep the admin surface split between reusable service modules and host-owned inputs (Cockpit host overlays, per-workload secret sources, and the LA host-local `/srv/data` ACL/reconcile remainder)
- evolve Beets via native systemd-based inbox-to-library promotion under `home-forge` `/srv/storage/media/music/library` while keeping library and quarantine playback visibility
- support a secondary approved-quarantine promotion runner for manual re-attempt workflows

Track E: Future-ready evolution

- adopt the accepted staged Dendritic transition (D-047): Stage 1 scaffold (flake-parts + `denful/import-tree` + typed host registry under `modules/hosts/`) landed in `dendritic-stage-1-scaffold-hosts`; Stage 2 landed foundation-first in `dendritic-stage-2-foundation-aspects` (five foundation aspects with typed `fleet.foundation` facts, `modules/core/` + `modules/profiles/` removed) — implementation-complete but not deployed or archived; Stage 3 landed operational aspects in `dendritic-stage-3-operational-aspects` (`builder-access` and `observability-agent`, plus the then-combined `backups` aspect, selected by all three hosts, folding the five deferred operational leaves under them, D-049) — implementation-complete but not deployed or archived; Stage 4 (`dendritic-stage-4-source-model-realignment`, D-050) realigned the documented model: source ownership and deployment granularity are independent axes, the central `aspects.nix` was replaced by concern-owned contributors, the support trio is classified as infrastructure wiring, `dj` selection enables the application, and plain class-oriented leaves plus the filter are transitional; Stage 5 (`dendritic-stage-5-shared-source-contributors`, D-051) removed the `shared`/`storage` roots, relocated the remaining private leaves to the concern-owned `_aspects`/`_backups`/`_builder-access` paths, promoted `web-policy` to the all-host support quartet, merged the two identity contributors into the single `identity-client` aspect, and shrank the filter to four entries; Stage 6 (`dendritic-stage-6-music-composition`, D-052) converted the music stack into the discovered home-forge-only `music` aspect `modules/flake/music.nix`, moved Beets secret/template/CLI ownership plus the ingest and storage/permission mechanisms into private leaves under `modules/services/music/**`, added the typed read-only `applications.music.contract` consumed by `dj` with a named assertion, and kept the four-root filter unchanged; Stage 7 (`dendritic-stage-7-placement-aspects`, D-053) published the remaining placement aspects (`oci`, `edge`, `cockpit`, `push-server`, `identity-provider`, `admin-hub`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, `omniroute`), relocated the admin/edge/DJ/OCI implementations beside their concern owners, deleted `modules/applications/` and `modules/providers/`, and shrank the filter to exactly `hosts` and `services` — the Stage 6 and Stage 7 changes (`dendritic-stage-6-music-composition`, `dendritic-stage-7-placement-aspects`) are archived, and the transition analysis's music-exemplar Stage 2 sequencing is superseded. The identity/admin decoupling change (`decouple-identity-admin-capabilities`, D-054) then dissolved `admin-hub` and `applications.admin` into the individual aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`, made identity consumption directional, and removed Quantum from the active module graph as disabled/deferred
- keep layout compatible with later fleet deployment tooling
- reserve integration points for future media processing hooks
- reserve path for later `rclone`/VFS transition
- defer app-based review UX and higher-complexity orchestration while report-first promotion remains sufficient

Track F: Admin/edge host migration

- `la-admin-1` is the active admin, edge, and Kanidm/OIDC host; the previous rollback host was decommissioned after the LA backup/recovery gates passed
- serial deploy order is `la-admin-1` before `oci-melb-1`; the local-admin Cockpit path is `/la-admin-1`
- LA adoption (preinstalled NixOS, non-destructive) is separate from later AU edge and US-East workload work
- cross-host consumers use stable service IDs from the policy catalog (`config.repo.web.catalog`); physical deployment facts (`edgeHost`, `deployOrder`) stay only in `lib/deploy/hosts.nix`
- canonical bring-up and transfer documentation: `docs/runbooks/host-initialization.md` (generic) and `docs/runbooks/admin-host-migration.md` (LA facts only)
- source freeze/rollback: DO decommission is complete; LA is authoritative
- encrypted-secret actions are operator-owned (host-key-verified recipient, ciphertext from templates, Tailscale/R2/ntfy handoff); repository work provides policy, contracts, and templates only
- Open WebUI deployment is deferred until the migration cutover and backup gates pass

## Success Criteria (Strategic)

The plan is succeeding when:

- repository intent is unambiguous from docs and directory structure
- legacy `dev-vps` assumptions no longer drive active configuration
- first host bootstrap path is reliable and repeatable
- service baseline is operational with current data flow expectations
- unresolved concerns remain explicitly documented rather than implicit

## Technical Debt Ledger (Dendritic Transition)

Durable index of confirmed transition debt and acceptance boundaries — an index and criteria record, not a task list. Items owned by active OpenSpec changes are referenced, never duplicated; their task bodies live under `openspec/changes/<name>/`.

**Stop condition (high-level):** the Dendritic architecture is declared established only when identity decoupling is complete, Stage 8 is complete, the host registry is generic, host IDs are canonical, internal contracts are narrow, hosts are explicit contributors, the import filter is exactly `[ "services" ]`, and docs and gates pass. Notification normalization (`TD-06`) and the backup/cache split (`TD-05`) are valuable ownership changes but do not gate that declaration; if the backup/cache split lands first, Stage 8 consumes its final owner.

**In-change**

- `TD-01` (`in-change`) — identity/admin decoupling residue: remove `applications.admin`/`admin-hub`, update the affected decision criterion, and complete equivalence checks, ratchets, and reviews. Owner: `openspec/changes/decouple-identity-admin-capabilities/`. Retired when that change's equivalence, ratchet, and review tasks close.
- `TD-02` (`in-change`) — canonical host identity completion: typed canonical host records, discovered host contributors, the generic registry, the exact `[ "services" ]` boundary, and typed PostgreSQL / Niks3-write contracts. Owner: `openspec/changes/dendritic-stage-8-host-identity-contracts/`. Retired at Stage 8 completion.
- `TD-13` (`in-change`) — documentation debt: the identity merge must remove `admin-hub` architecture text from `docs/architecture.md`, record the revised aspect-boundary criterion in `docs/decisions.md`, and reconcile stale Stage 6 lifecycle wording; reconcile final-review comment residue in code headers — the stale `identity-provider.nix` header describing a provider→`identity-client` consumption dependency that the implementation removed, and the `D-053` provenance in the six extracted-aspect headers (`termix`/`vaultwarden`/`gatus`/`beszel`/`homepage`/`webhook`) that D-054 now governs. Owner: `openspec/changes/decouple-identity-admin-capabilities/` (documentation tasks, with Stage 8 task 5.2). Retired when docs and headers match the post-decoupling model.

**Deferred**

- `TD-03` (`deferred`, partial `in-change`) — flat `modules/flake/` contributor bucket vs feature locality. Stage 8 task 5.1 (within `TD-02`) moves only touched settled concerns into semantic paths; broader relocation is deferred and must not become a repo-wide path-only shuffle. Owner: `openspec/changes/dendritic-stage-8-host-identity-contracts/` (task 5.1). Retirement: an explicit semantic-locality decision driven by touched concerns after Stage 8.
- `TD-04` (`deferred`) — `modules/services/**` import-tree exclusion (`modules/flake/_unconverted-nixos-dirs.nix`). Accepted incremental backlog under the no-direct-host-import ratchet; conversion is not required for high-level transition completion. Retirement: per-subtree conversion when real pressure exists.
- `TD-05` (`resolved by split-state-backups-cache-publication`) — the combined `backups` aspect was split into independent `state-backups` and `cache-publisher` aspects (D-055); the private Niks3 leaves stayed beside their owner under `modules/flake/_backups/`. The Stage 8 Niks3-write contract migration now consumes `cache-publisher` directly (`TD-02`).
- `TD-06` (`deferred`) — LA-owned literal ntfy publisher policy in `modules/hosts/la-admin-1/default.nix`. Owner: `openspec/changes/normalize-notification-policy/`. Trigger: after Stage 8 canonical host IDs exist, since the policy is keyed by them.
- `TD-07` (`deferred`) — Quantum disabled/deferred residue and host-local SSH registrations (the Quantum service/host modules were deleted; the SSH registrations and `/srv/data` ACL remainder remain host-local under `modules/hosts/la-admin-1/`, where the SSH registrations are **reserved for** the disabled/deferred Quantum workload, not actively consumed). Includes the stale Quantum IdP/Kanidm catalog entries and the retained `kanidm_oauth2_quantum_basic_secret` OIDC client registration in `policy/` and `secrets/applications/admin.yaml` (keep-for-possible-reenable). Retirement criterion: **retire or re-enable** — either remove the reserved registrations and catalog entries entirely, or land a self-contained Quantum concern/aspect consuming canonical identity contracts without restoring `admin-hub` coupling.

**Follow-up**

- `TD-08` (`follow-up`) — Termix remains selected despite low priority (`modules/services/termix.nix`). Reassess or remove after the transition if unused; does not block the current change.
- `TD-09` (`follow-up`) — Cockpit default route key is LA-shaped (`cockpit-admin`) while OCI uses overrides (`modules/services/admin/cockpit.nix`, `modules/services/admin/cockpit/loopback-tls.nix`, `modules/services/admin/homepage/data.nix`). Follow-up: a typed/explicit route-key contract.
- `TD-10` (`follow-up`) — feature-owned monitoring residual semantics: `ExecStopPost` success labeling after failures, shallow composition/self-monitoring hardening, and the real-service predicate intentionally excluding arbitrary raw units. Provenance: completed `openspec/changes/feature-owned-service-monitoring/`; the residuals are deliberate follow-ups, not regressions.
- `TD-11` (`follow-up`) — `tests/check-identity-contract-directionality.sh` is becoming a monolithic second specification. After the current change, split it into focused contract tests with shared fixtures while retaining mutation-based non-vacuity. Included in the split: cumulative subset fixture purity (later subsets inherit mutations from earlier ones), the LA aspect-selection list duplicated across `modules/flake/registry.nix` and the two contract tests, and optional coverage for the host-private `_admin-runtime.nix` scaffold fragment in `tests/check-dendritic-scaffold-contract.sh`.

**Superseded cleanup**

- `TD-12` (`superseded-cleanup`) — `openspec/changes/normalize-fleet-boundaries/` is superseded after its useful requirements were harvested by the landed stages. Archive it as superseded; it is not a live implementation source.
- `TD-16` (`follow-up`) — the Kanidm provider data root is the literal `/srv/data/kanidm` in `modules/flake/identity-provider.nix` (default also in `modules/services/admin/kanidm.nix`) instead of a typed/shared data-root contract; align when a host storage contract exists.

**Accepted boundaries — not completion debt**

- `TD-14` (accepted support wiring, not debt) — all-host support contributors (`modules/flake/provenance.nix`, `oci-images.nix`, `fleet-packages.nix`, `web-policy.nix`). Retirement is consumer-driven and optional; recorded here to prevent misclassification as transition completion debt.

**Explicit non-gates**

- `TD-15` (not-a-gate) — full conversion of every service leaf, Den/flake-file adoption, universal service topology, internal DNS, and premature `nix-fleet` extraction are explicitly not completion gates.

## Non-Goals During Current Planning Window

- writing full operational runbooks before baseline architecture settles
- selecting long-term orchestration and worker framework now
- optimizing for hypothetical future scale at the cost of current clarity

## Documentation Maintenance Rule

Any major implementation decision that changes behavior, trust boundaries, or migration direction must update:

- `docs/architecture.md`
- `docs/decisions.md`
- `docs/plan.md`
- `docs/context-history.md`
- the relevant `docs/runbooks/*.md` when bring-up or transfer procedures change

These documents are intended to remain current and drive implementation, not trail it.

Active implementation anchor paths that must stay reflected in docs:

- `modules/hosts/oci-melb-1/default.nix`
- `modules/hosts/la-admin-1/default.nix`
- `modules/flake/music.nix` (home-forge-only `music` deployment aspect: selection provides `applications.music.enable`, nests the music composition, imports the private music leaves)
- `modules/flake/{identity-provider,cockpit,termix,vaultwarden,homepage,gatus,beszel,webhook}.nix` (the admin capability aspects; the `modules/applications/admin/default.nix` coordinator was deleted and `admin-hub` was dissolved by D-054)
- `modules/services/music/` (canonical music service module subtree: `navidrome.nix`, `audiomuse.nix`, `syncthing.nix`, `slskd.nix`, `tagr.nix`, the Beets owner `beets/{default.nix,runners.nix,files/}`, and the Stage 6 private leaves `ingest.nix` and `storage.nix` with `files/ffmpeg-preprocess.sh`)
- `modules/flake/` concern-owned aspect contributors (`base.nix`, `shell.nix`, `networking.nix`, `tailscale.nix`, `notify.nix`, `state-backups.nix`, `cache-publisher.nix`, `builder-access.nix`, `observability-agent.nix`, `dj.nix`, `music.nix`, `identity-oidc.nix`, `kanidm-host-auth.nix`, and the placement contributors `oci.nix`, `edge.nix`, `cockpit.nix`, `push-server.nix`, `identity-provider.nix`, `termix.nix`, `vaultwarden.nix`, `homepage.nix`, `gatus.nix`, `beszel.nix`, `webhook.nix`, `paperless.nix`, `postgres.nix`, `ai-gateway.nix`, `karakeep.nix`, `niks3-cache.nix`, `phoenix.nix`, `omniroute.nix`) plus infrastructure support modules (`provenance.nix`, `oci-images.nix`, `fleet-packages.nix`, `web-policy.nix`) and the concern-owned private paths `modules/flake/_aspects/`, `_backups/`, `_builder-access/`, `_dj/`, `_edge/`, `_oci/`
- `modules/flake/registry.nix` (host composition: aspect selection, typed facts, feature leaf imports)
- `modules/services/tailscale.nix` (tailscale aspect service leaf)
- `modules/services/notification-daemon/` (notify aspect service leaf)
- `modules/services/termix.nix`
- `modules/hosts/la-admin-1/_admin-runtime.nix` (the residual `/srv/data` operator ACL/reconcile unit and Quantum SSH registrations; `modules/services/admin/quantum.nix` was deleted as disabled/deferred)

Maintenance requirement: changes to active architecture paths, trust boundaries, or operator/CI commands must update canonical docs in the same change window. For features that distinguish deployed infrastructure from end-to-end validated behavior (e.g. AudioMuse first-run setup, Navidrome plugin configuration, Symfonium validation), docs must clearly separate the deployment-complete state from the E2E-accepted state.

Current operator/validation entrypoints that docs should track when they change:

- `just check`
- `just tofu-sync`
- `just tofu-runtime`
- `tests/check-secret-scope.sh`
- `tests/check-web-services-policy.sh`
- `scripts/export-web-services-policy.sh`
- `scripts/render-opentofu-cloudflare-runtime.sh`
