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
- keep music service composition explicit through the discovered `music` deployment aspect `modules/music/music.nix` (selected on `home-forge` only; selection provides `applications.music.enable`), with the service contributors beside it under `modules/music/`
- keep music service modules regrouped under `modules/music/` for navigability without changing option namespaces
- run the complete music application on `home-forge` under the host-selected music application root `/srv/storage/media/music/{library,playlists,inbox,quarantine,.versions}`, with AudioMuse's database in OCI's shared Postgres over Tailscale and LA edge routes for music/slskd/tagr pointing at `home-forge`; playlist export/import for Engine DJ is owned by a separate repository
- keep admin service composition in independently selected aspects: `identity-provider` (Kanidm), `cockpit`, and the individual workload aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`; there is no `admin-hub` bundle (D-054), and Quantum is removed from the active module graph as disabled/deferred
- keep the admin surface split between reusable service modules and host-owned inputs (Cockpit host overlays, per-workload secret sources, and the LA host-local `/srv/data` ACL/reconcile remainder)
- evolve Beets via native systemd-based inbox-to-library promotion under `home-forge` `/srv/storage/media/music/library` while keeping library and quarantine playback visibility
- support a secondary approved-quarantine promotion runner for manual re-attempt workflows

Track E: Future-ready evolution

- adopt the accepted staged Dendritic transition (D-047): Stage 1 scaffold (flake-parts + `denful/import-tree` + typed host registry under `modules/hosts/`) landed in `dendritic-stage-1-scaffold-hosts`; Stage 2 landed foundation-first in `dendritic-stage-2-foundation-aspects` (five foundation aspects with typed `fleet.foundation` facts, `modules/core/` + `modules/profiles/` removed) — implementation-complete but not deployed or archived; Stage 3 landed operational aspects in `dendritic-stage-3-operational-aspects` (`builder-access` and `observability-agent`, plus the then-combined `backups` aspect, selected by all three hosts, folding the five deferred operational leaves under them, D-049) — implementation-complete but not deployed or archived; Stage 4 (`dendritic-stage-4-source-model-realignment`, D-050) realigned the documented model: source ownership and deployment granularity are independent axes, the central `aspects.nix` was replaced by concern-owned contributors, the support trio is classified as infrastructure wiring, `dj` selection enables the application, and plain class-oriented leaves plus the filter are transitional; Stage 5 (`dendritic-stage-5-shared-source-contributors`, D-051) removed the `shared`/`storage` roots, relocated the remaining private leaves to the concern-owned `_aspects`/`_backups`/`_builder-access` paths, promoted `web-policy` to the all-host support quartet, merged the two identity contributors into the single `identity-client` aspect, and shrank the filter to four entries; Stage 6 (`dendritic-stage-6-music-composition`, D-052) converted the music stack into the discovered home-forge-only `music` aspect `modules/flake/music.nix`, moved Beets secret/template/CLI ownership plus the ingest and storage/permission mechanisms into private leaves in the then-current service tree, added the typed read-only `applications.music.contract` consumed by `dj` with a named assertion, and kept the four-root filter unchanged; Stage 7 (`dendritic-stage-7-placement-aspects`, D-053) published the remaining placement aspects (`oci`, `edge`, `cockpit`, `push-server`, `identity-provider`, `admin-hub`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, `omniroute`), relocated the admin/edge/DJ/OCI implementations beside their concern owners, deleted `modules/applications/` and `modules/providers/`, and shrank the filter to exactly `hosts` and `services` — the Stage 6 and Stage 7 changes (`dendritic-stage-6-music-composition`, `dendritic-stage-7-placement-aspects`) are archived, and the transition analysis's music-exemplar Stage 2 sequencing is superseded. The identity/admin decoupling change (`decouple-identity-admin-capabilities`, D-054) then dissolved `admin-hub` and `applications.admin` into the individual aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`, made identity consumption directional, and removed Quantum from the active module graph as disabled/deferred; Stage 8 (`dendritic-stage-8-host-identity-contracts`, D-056) then made host identity a typed discovered record with a generic materializer, reduced `modules/flake/registry.nix` to the `flake.bootstrap.nodes` projection, added canonical-host-ID validation to deploy and web metadata, published the two internal transport contracts under `modules/fleet/`, and moved the settled concern contributors into domain directories — and the post-Stage-8 services-tree conversion then converted every remaining service leaf into a discovered contributor, emptying the import-tree exclusion entirely
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

- `TD-01` (`resolved by decouple-identity-admin-capabilities`, D-054) — the identity/admin decoupling residue is gone: `applications.admin` and `admin-hub` are deleted, the six former hub members are self-contained placement aspects, the equivalence capture, ratchet group, and both reviews closed with the change (archived 2026-09-18), and the decision criterion was updated with it.
- `TD-02` (`resolved by dendritic-stage-8-host-identity-contracts`) — canonical host identity completion: typed canonical host records, discovered host contributors, the generic registry, the exact `[ "services" ]` boundary, and typed PostgreSQL / Niks3-write contracts (D-056). Implementation tasks 1.1-5.1 are complete (same-tree A/B drvPath equality per host, 35 publications, all contract suites green); task 5.3 closed the gate battery (treefmt 0-changed, `just checks all`, `nix flake check --no-build path:.`, three host evaluations, strict OpenSpec validation, LA/home-forge closure comparison showing only the source-provenance object, OCI structured observables with one intended audiomuse `aspectOption` delta) and two independent reviews (architecture ACCEPT; correctness review returned no P0 after its blocker was disproven as a `.#`-vs-`path:.` methodology artifact).
- `TD-13` (`resolved by Stage 8 task 5.2`) — documentation debt: the `admin-hub` architecture text and the revised aspect-boundary criterion were reconciled by D-054's documentation pass; Stage 8 task 5.2 closed the code-header residue — the stale `identity-provider.nix` header (which described the removed provider→`identity-client` URL consumption; the provider reads the canonical URL from web policy and the Kanidm leaf asserts agreement with `services.identity.oidc.providerUrl`) and the six extracted-aspect headers (`termix`/`vaultwarden`/`gatus`/`beszel`/`homepage`/`webhook`), whose `D-053` provenance now records the D-054 self-containment.

**Deferred**

- `TD-03` (`deferred`, partial `resolved`) — flat `modules/flake/` contributor bucket vs feature locality. Stage 8 task 5.1 landed the bounded move of settled touched concerns into domain directories (`modules/identity/`, `modules/notifications/`, `modules/cache/`, `modules/music/`, `modules/admin/`, `modules/edge/`, `modules/oci/`, `modules/fleet/`); broader relocation remains deferred and must not become a repo-wide path-only shuffle. Retirement: an explicit semantic-locality decision driven by touched concerns after Stage 8.
- `TD-04` (`resolved by the post-Stage-8 services-tree conversion`) — the service-root import-tree exclusion (`modules/flake/_unconverted-nixos-dirs.nix`) is empty: every former leaf is now a discovered contributor, a sibling contributor of its owner aspect, or an underscore-private helper, and the boundary file is kept as the inspectable, contract-tested empty list.
- `TD-05` (`resolved by split-state-backups-cache-publication`) — the combined `backups` aspect was split into independent `state-backups` and `cache-publisher` aspects (D-055); the Niks3 publication leaves are now the sibling contributors `modules/cache/cache-publisher/{upload-client,post-deploy}.nix` beside their owner (path corrected again by the post-Stage-8 services-tree conversion; D-055 recorded the pre-Stage-8 `modules/flake/_backups/` location and D-056 the intermediate `modules/cache/_backups/` one). The Stage 8 Niks3-write contract migration now consumes `cache-publisher` directly (`TD-02`).
- `TD-06` (`deferred`) — LA-owned literal ntfy publisher policy in `modules/hosts/la-admin-1/default.nix`. Owner: `openspec/changes/normalize-notification-policy/`. Trigger: after Stage 8 canonical host IDs exist, since the policy is keyed by them.
- `TD-07` (`deferred`) — Quantum disabled/deferred residue and host-local SSH registrations (the Quantum service/host modules were deleted; the SSH registrations and `/srv/data` ACL remainder remain host-local under `modules/hosts/la-admin-1/`, where the SSH registrations are **reserved for** the disabled/deferred Quantum workload, not actively consumed). Includes the stale Quantum IdP/Kanidm catalog entries and the retained `kanidm_oauth2_quantum_basic_secret` OIDC client registration in `policy/` and `secrets/applications/admin.yaml` (keep-for-possible-reenable). Retirement criterion: **retire or re-enable** — either remove the reserved registrations and catalog entries entirely, or land a self-contained Quantum concern/aspect consuming canonical identity contracts without restoring `admin-hub` coupling.

**Follow-up**

- `TD-08` (`follow-up`) — Termix remains selected despite low priority (`modules/admin/termix.nix`). Reassess or remove after the transition if unused; does not block the current change.
- `TD-09` (`follow-up`) — Cockpit default route key is LA-shaped (`cockpit-admin`) while OCI uses overrides (`modules/admin/cockpit.nix`, `modules/admin/cockpit/loopback-tls.nix`, `modules/admin/homepage/_data.nix`). Follow-up: a typed/explicit route-key contract.
- `TD-10` (`follow-up`) — feature-owned monitoring residual semantics: `ExecStopPost` success labeling after failures, shallow composition/self-monitoring hardening, and the real-service predicate intentionally excluding arbitrary raw units. Provenance: completed `openspec/changes/feature-owned-service-monitoring/`; the residuals are deliberate follow-ups, not regressions.
- `TD-11` (`follow-up`) — `tests/check-identity-contract-directionality.sh` is becoming a monolithic second specification. After the current change, split it into focused contract tests with shared fixtures while retaining mutation-based non-vacuity. Included in the split: cumulative subset fixture purity (later subsets inherit mutations from earlier ones), the per-host aspect-selection expectations now duplicated across the three host records and the two contract suites (Stage 8 moved selections from `modules/flake/registry.nix` into `modules/hosts/<host>/default.nix`), and optional coverage for the host-private `_admin-runtime.nix` scaffold fragment in `tests/check-dendritic-scaffold-contract.sh`.

**Superseded cleanup**

- `TD-12` (`superseded-cleanup`) — `openspec/changes/normalize-fleet-boundaries/` is superseded after its useful requirements were harvested by the landed stages. Archive it as superseded; it is not a live implementation source.
- `TD-16` (`follow-up`) — the Kanidm provider data root is the literal `/srv/data/kanidm` in `modules/identity/identity-provider.nix` (default also in `modules/identity/kanidm-runtime.nix`) instead of a typed/shared data-root contract; align when a host storage contract exists.
- `TD-17` (`follow-up`) — support-quartet placement: `provenance`, `oci-images`, `fleet-packages`, and `web-policy` remain contributors in `modules/flake/` (recorded as accepted wiring by `TD-14`). Stage 8 task 5.1 deliberately left them there under the "no repo-wide path-only shuffle" rule; moving them into a fleet/materialization domain is a separate decision to take only when a real ownership pressure appears.
- `TD-18` (`follow-up`) — `_dj` ownership predicate layout dependence is now discharged for the DJ leaves (they are sibling contributors `modules/music/dj-engine.nix`), but the scaffold contract's private-leaf ownership check still matches `./_<dir>`-shaped imports, so a cross-concern import written as a bare underscore directory path would evade it. Tighten the predicate (or assert on resolved paths) when the remaining `_` helpers next change.
- `TD-19` (`resolved by restrict-provenance-source-copy`, D-057) — the `/etc/nixos-source` provenance copy shipped the whole working tree, including `.git`, `opentofu/**/.terraform`, `.hp-forge-esp-backup`, editor caches, and plaintext credential files, at ~440 MB per host closure. Resolved by evaluating the flake through the Git-tree form `.#`, which publishes the tracked configuration set (~5.5 MB) and restores a non-null `system.configurationRevision`; the fallback `cleanSourceWith` exclusion list was deleted so tracking stays the single filtering authority.
- `TD-20` (`operational-constraint`) — the `.#` Git-tree form reads the Git index, so a tracked file missing from the index is silently absent from evaluation and from the published provenance. Colocated jj keeps the index in sync and `tests/check-flake-source-tracking.sh` (in `just checks all`) fails with the repair (`git add -A`) when it diverges; index-mutating Git commands (`git reset`, `git checkout`, `git stash`) must not be used in this repository (D-057).

- `TD-22` (`resolved`) — the 20 placeholder capability Purposes are replaced with real sentences derived from each capability's requirements, and one further canonical scenario that the PostgreSQL migration had made false (AudioMuse's database described as remote OCI) now states the local-cluster shape. `openspec validate --all --strict` reports 54 passed, 0 failed, so the repo-wide strict gate is again a usable signal; a stale delta in `navidrome-m3u-itunes-worker` that would have dropped five canonical scenarios was repaired in the same pass.

- `TD-23` (`superseded-reference`) — `openspec/changes/normalize-fleet-boundaries` remains active with 0/22 tasks by its own status header, because it was superseded by the staged Dendritic transition before implementation. Its ownership findings were harvested into the follow-up changes that did execute (notification policy, identity/admin decoupling, host identity and internal contracts, state-backup/cache-publication split) and into the ledger entries above. It is kept as a reference record rather than archived: `openspec archive` applies every delta spec to the canonical capabilities, which would enter requirements the repository never implemented.

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

- `modules/hosts/oci-melb-1/default.nix` (host record) + `modules/hosts/oci-melb-1/_nixos.nix` (private composition)
- `modules/hosts/la-admin-1/default.nix` (host record) + `modules/hosts/la-admin-1/_nixos.nix` (private composition)
- `modules/hosts/home-forge/default.nix` (host record) + `modules/hosts/home-forge/_nixos.nix` (private composition)
- `modules/music/music.nix` (home-forge-only `music` deployment aspect: selection provides `applications.music.enable`, nests the music composition, imports the private music leaves)
- `modules/identity/identity-provider.nix`, `modules/admin/{cockpit,termix,vaultwarden,homepage,gatus,beszel,webhook}.nix` (the admin capability aspects; the `modules/applications/admin/default.nix` coordinator was deleted and `admin-hub` was dissolved by D-054)
- `modules/music/` (canonical music service module subtree: `navidrome.nix`, `audiomuse.nix`, `syncthing.nix`, `slskd.nix`, `tagr.nix`, `beets.nix` with its asset directory `beets/files/` and runner helper `_beets/runners.nix`, and the `ingest.nix` and `storage.nix` contributors with `files/ffmpeg-preprocess.sh`)
- domain aspect contributors (`modules/identity/{identity-oidc,kanidm-host-auth,identity-provider}.nix`, `modules/notifications/{notify,push-server}.nix`, `modules/cache/{state-backups,cache-publisher,niks3-cache}.nix`, `modules/music/{music,dj}.nix`, `modules/admin/{cockpit,termix,vaultwarden,homepage,gatus,beszel,webhook}.nix`, `modules/edge/edge.nix`, `modules/oci/oci.nix`, `modules/fleet/internal-contracts.nix`) plus the fleet-baseline and materialization contributors in `modules/flake/` (`base/foundation.nix`, `base/host-recovery.nix`, `shell.nix`, `networking.nix`, `tailscale.nix`, `builder-access.nix`, `observability-agent.nix`, `paperless.nix`, `ai-gateway.nix`, `karakeep.nix`, `phoenix.nix`, `omniroute.nix`, `provenance.nix`, `oci-images.nix`, `fleet-packages.nix`, `web-policy.nix`, `host-registry.nix`, `deploy.nix`) and the sibling contributors beside their owners (`modules/cache/cache-publisher/{upload-client,post-deploy}.nix`, `modules/music/{dj-engine,windows-vm}.nix`, `modules/edge/edge-ingress-application.nix`, `modules/database/postgres.nix` with `postgres/_consumer.nix`), plus the `_` helpers `modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, and `modules/admin/homepage/_data.nix`
- `modules/flake/host-registry.nix` (typed `nixos.hosts.<id>` schema + generic materializer) and `modules/flake/registry.nix` (the `flake.bootstrap.nodes` projection)
- `modules/flake/tailscale.nix` (tailscale aspect service leaf)
- `modules/notifications/notify.nix` (notify aspect service leaf, carrying the notification-daemon body inline)
- `modules/admin/termix.nix`
- `modules/hosts/la-admin-1/_admin-runtime.nix` (the residual `/srv/data` operator ACL/reconcile unit and Quantum SSH registrations; the `admin/quantum` service leaf was deleted as disabled/deferred)

Maintenance requirement: changes to active architecture paths, trust boundaries, or operator/CI commands must update canonical docs in the same change window. For features that distinguish deployed infrastructure from end-to-end validated behavior (e.g. AudioMuse first-run setup, Navidrome plugin configuration, Symfonium validation), docs must clearly separate the deployment-complete state from the E2E-accepted state.

Current operator/validation entrypoints that docs should track when they change:

- `just check`
- `just tofu-sync`
- `just tofu-runtime`
- `tests/check-secret-scope.sh`
- `tests/check-web-services-policy.sh`
- `scripts/export-web-services-policy.sh`
- `scripts/render-opentofu-cloudflare-runtime.sh`
- `TD-21` (`resolved by modular-postgres-instances`, D-058) — the shared PostgreSQL substrate was a monolith: one consumer-shaped option block per database client (`niks3`/`paperless`/`audiomuse`/`litellm`), so a new consumer meant editing the substrate and a second cluster had no expression at all. It is now a mechanism (`modules/database/postgres.nix`, with the declaration-only contract `modules/database/postgres/_consumer.nix`) rendering from `instances.<name>` plus a consumer registry, with the cluster placed by the aspect published from that same file and consumers registering from their own modules. The retired `litellm` consumer is deleted; niks3 no longer double-declares its database; endpoints resolve per instance through `repo.internal.postgres.<instance>`; and a runbook namespace move (`services.postgres-shared` → `services.postgres`) accompanies it. Refined after review: the credential moved into the registration (`password = { file, key }`), so one file and key are authoritative for both sides; extension packages are contributed in nixpkgs' own shape (`extensions = ps: [ ps.pgvector ]`) and composed by the mechanism, with the SQL in an idempotent `setupSQL`; and AudioMuse's database moved to `home-forge` beside its compute, which removed the last cross-host registration and the hand-synced credential pair along with it (the operator migration path is `docs/runbooks/postgres-consumer-migration.md`). Remaining, recorded rather than hidden: out-of-repository consumers are a future `nix-fleet` registration policy question, and the retired provider-side secret file (`secrets/services/postgres-shared.yaml`) is now read by nothing — deleting it is an operator action.
