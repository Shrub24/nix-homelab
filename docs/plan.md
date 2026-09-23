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
- keep admin service composition in independently selected aspects: `identity-provider` (Kanidm), `cockpit`, and the individual workload aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`; there is no `admin-hub` bundle (D-054), and Quantum is fully retired (TD-07)
- keep the admin surface split between reusable service modules and host-owned inputs (Cockpit host overlays, per-workload secret sources, and the LA host-local `/srv/data` ACL/reconcile remainder)
- evolve Beets via native systemd-based inbox-to-library promotion under `home-forge` `/srv/storage/media/music/library` while keeping library and quarantine playback visibility
- support a secondary approved-quarantine promotion runner for manual re-attempt workflows

Track E: Future-ready evolution

- adopt the accepted staged Dendritic transition (D-047): Stage 1 scaffold (flake-parts + `denful/import-tree` + typed host registry under `modules/hosts/`) landed in `dendritic-stage-1-scaffold-hosts`; Stage 2 landed foundation-first in `dendritic-stage-2-foundation-aspects` (five foundation aspects with typed `fleet.foundation` facts, `modules/core/` + `modules/profiles/` removed) — implementation-complete but not deployed or archived; Stage 3 landed operational aspects in `dendritic-stage-3-operational-aspects` (`builder-access` and `observability-agent`, plus the then-combined `backups` aspect, selected by all three hosts, folding the five deferred operational leaves under them, D-049) — implementation-complete but not deployed or archived; Stage 4 (`dendritic-stage-4-source-model-realignment`, D-050) realigned the documented model: source ownership and deployment granularity are independent axes, the central `aspects.nix` was replaced by concern-owned contributors, the support trio is classified as infrastructure wiring, `dj` selection enables the application, and plain class-oriented leaves plus the filter are transitional; Stage 5 (`dendritic-stage-5-shared-source-contributors`, D-051) removed the `shared`/`storage` roots, relocated the remaining private leaves to the concern-owned `_aspects`/`_backups`/`_builder-access` paths, promoted `web-policy` to the all-host support quartet, merged the two identity contributors into the single `identity-client` aspect, and shrank the filter to four entries (D-059 later retired that bundle: the OIDC contract is the intrinsic `modules/identity/_oidc.nix` and the capability is `kanidm-host-auth`); Stage 6 (`dendritic-stage-6-music-composition`, D-052) converted the music stack into the discovered home-forge-only `music` aspect `modules/flake/music.nix`, moved Beets secret/template/CLI ownership plus the ingest and storage/permission mechanisms into private leaves in the then-current service tree, added the typed read-only `applications.music.contract` consumed by `dj` with a named assertion, and kept the four-root filter unchanged; Stage 7 (`dendritic-stage-7-placement-aspects`, D-053) published the remaining placement aspects (`oci`, `edge`, `cockpit`, `push-server`, `identity-provider`, `admin-hub`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, `omniroute`), relocated the admin/edge/DJ/OCI implementations beside their concern owners, deleted `modules/applications/` and `modules/providers/`, and shrank the filter to exactly `hosts` and `services` — the Stage 6 and Stage 7 changes (`dendritic-stage-6-music-composition`, `dendritic-stage-7-placement-aspects`) are archived, and the transition analysis's music-exemplar Stage 2 sequencing is superseded. The identity/admin decoupling change (`decouple-identity-admin-capabilities`, D-054) then dissolved `admin-hub` and `applications.admin` into the individual aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`, made identity consumption directional, and removed Quantum from the active module graph as disabled/deferred; Stage 8 (`dendritic-stage-8-host-identity-contracts`, D-056) then made host identity a typed discovered record with a generic materializer, reduced `modules/flake/bootstrap.nix` to the `flake.bootstrap.nodes` projection, added canonical-host-ID validation to deploy and web metadata, published the two internal transport contracts under `modules/fleet/`, and moved the settled concern contributors into domain directories — and the post-Stage-8 services-tree conversion then converted every remaining service leaf into a discovered contributor, emptying the import-tree exclusion entirely
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

- `TD-03` (`deferred`, partial `resolved`) — flat `modules/flake/` contributor bucket vs feature locality. Stage 8 task 5.1 landed the bounded move of settled touched concerns into domain directories (`modules/identity/`, `modules/notifications/`, `modules/cache/`, `modules/music/`, `modules/admin/`, `modules/web/`, `modules/oci/`, `modules/fleet/`); broader relocation remains deferred and must not become a repo-wide path-only shuffle. Retirement: an explicit semantic-locality decision driven by touched concerns after Stage 8.
- `TD-04` (`resolved by the post-Stage-8 services-tree conversion`) — the service-root import-tree exclusion held an empty list when the transition finished: every former leaf is now a discovered contributor, a sibling contributor of its owner aspect, or an underscore-private helper. The boundary file itself was deleted with the flake-file change (D-060): the generated `outputs` discovers `modules/` unfiltered, and the scaffold contract asserts the converted roots stay evacuated.
- `TD-05` (`resolved by split-state-backups-cache-publication`) — the combined `backups` aspect was split into independent `state-backups` and `cache-publisher` aspects (D-055); the Niks3 publication leaves are now the sibling contributors `modules/cache/cache-publisher/{upload-client,post-deploy}.nix` beside their owner (path corrected again by the post-Stage-8 services-tree conversion; D-055 recorded the pre-Stage-8 `modules/flake/_backups/` location and D-056 the intermediate `modules/cache/_backups/` one). The Stage 8 Niks3-write contract migration now consumes `cache-publisher` directly (`TD-02`).
- `TD-06` (`resolved by normalize-notification-policy`, revised by the principal-publisher contract) — the ntfy publisher policy is a typed map in `modules/notifications/push-server.nix`, keyed by ntfy principal (a fleet host, a dotfiles machine, a CLI) rather than by canonical host ID, and passed into the aspect by value. The module renders the map into `auth-access`; the encrypted auth file carries only credentials, and activation fails by name when a declared publisher has no `auth-users`/`auth-tokens` entry, when the file carries `auth-access`, or when an `auth-users` entry is malformed. LA's literal list is gone.
- `TD-07` (`resolved`) — Quantum residue is fully retired rather than reserved: the service and host modules, the `/srv/data` operator ACL/reconcile unit, the admin SSH SOPS registrations, the Kanidm catalog entry, the `policy/identity.json` client, and the `kanidm_oauth2_quantum_basic_secret` OIDC client registration are gone from `modules/` and `policy/`, the OIDC and admin secret templates no longer carry a Quantum stub, and `tests/check-identity-contract-directionality.sh` fails if any of those surfaces returns. Re-enablement, if it ever happens, lands as a self-contained aspect consuming canonical identity contracts without restoring `admin-hub` coupling. The operator's encrypted `secrets/applications/admin.yaml` / `secrets/hosts/<host>/oidc.yaml` may still carry the retired keys until their next re-encryption; nothing reads them.

**Follow-up**

- `TD-08` (`resolved`) — Termix is deselected on every host, so the low-priority experiment no longer ships; the aspect and its canonical `termix-admin` web-policy route remain for re-enablement.
- `TD-09` (`follow-up`) — Cockpit still resolves its published identity from the hardcoded canonical key `"cockpit-admin"` (`modules/admin/cockpit.nix`, `modules/admin/cockpit/loopback-tls.nix`), but the route was retired with the demoted cockpit during the edge cutover (it leaked LA-only TLS material into the edge's config): the module now treats the key as optional and requires a `services.admin.cockpit.publicHost` override when it is absent, and the dashboard entry is gone. Re-enablement must re-declare the route (or finish the typed/explicit route-key contract).
- `TD-10` (`follow-up`) — feature-owned monitoring residual semantics: `ExecStopPost` success labeling after failures, shallow composition/self-monitoring hardening, and the real-service predicate intentionally excluding arbitrary raw units. Provenance: completed `openspec/changes/feature-owned-service-monitoring/`; the residuals are deliberate follow-ups, not regressions.
- `TD-11` (`follow-up`) — `tests/check-identity-contract-directionality.sh` is becoming a monolithic second specification. After the current change, split it into focused contract tests with shared fixtures while retaining mutation-based non-vacuity. Included in the split: cumulative subset fixture purity (later subsets inherit mutations from earlier ones), the per-host aspect-selection expectations now duplicated across the three host records and the two contract suites (Stage 8 moved selections from `modules/flake/bootstrap.nix` into `modules/hosts/<host>/default.nix`), and optional coverage for the host-private `_admin-runtime.nix` scaffold fragment in `tests/check-dendritic-scaffold-contract.sh`.

**Superseded cleanup**

- `TD-12` (`superseded-reference`) — `openspec/changes/normalize-fleet-boundaries/` is superseded after its useful requirements were harvested by the landed stages, and it is not a live implementation source. It must not be archived: `openspec archive` would enter never-implemented requirements into the canonical specs, so it is retained deliberately as a reference record (`TD-23`).
- `TD-16` (`resolved`) — `services.identity.kanidm.dataDir` is a typed option carrying the conventional default in `modules/identity/kanidm-runtime.nix` and the provider body references the option rather than a literal, so a host storing identity state elsewhere declares the path instead of editing the provider.
- `TD-17` (`follow-up`) — support-quartet placement: `provenance`, `oci-images`, `fleet-packages`, and `web-policy` remain contributors in `modules/flake/` (recorded as accepted wiring by `TD-14`). Stage 8 task 5.1 deliberately left them there under the "no repo-wide path-only shuffle" rule; moving them into a fleet/materialization domain is a separate decision to take only when a real ownership pressure appears. Related evidence, not a resolution: the intrinsic OIDC contract (`modules/identity/_oidc.nix`, D-059) is now a working instance of the same shape — a shared surface its consumers import instead of a host selecting it — which is the candidate form for the quartet if a consumer-driven retirement is ever taken up.
- `TD-18` (`resolved`) — the scaffold contract's private-leaf ownership check was worse than layout-dependent: it grepped for `_oci/default.nix`, `_edge/edge-ingress.nix`, and `_dj/*.nix`, filenames retired by the services-tree conversion, so it could not fire and its mutation proved nothing. It is now a path-resolving pass (`private_leaf_strays` in `tests/check-dendritic-scaffold-contract.sh`): relative import expressions are resolved against the tree and an underscore entry under `modules/` is reachable only from inside its owning concern (the domain, or `hosts/<host>` for host fragments), with the three declared intrinsic contracts exempt (`database/postgres/_consumer.nix`, `backups/state-backups/_consumer.nix`, `identity/_oidc.nix`). Verified by measurement: the clean tree reports nothing, a cross-concern `_beets` import and a `homepage/_data.nix` import are both detected, an `identity/_kanidm-packages.nix` import is detected, and a cross-domain `identity/_oidc.nix` import stays allowed. The 7n-3f-2 mutation now exercises the predicate directly.
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
- `modules/identity/identity-provider.nix`, `modules/admin/{cockpit,termix,homepage,webhook}.nix` (the operator-tooling capability aspects; the `modules/applications/admin/default.nix` coordinator was deleted and `admin-hub` was dissolved by D-054, and the user-facing workloads later moved to `modules/apps/` and `modules/observability/`)
- `modules/music/` (canonical music service module subtree: `navidrome.nix`, `audiomuse.nix`, `syncthing.nix`, `slskd.nix`, `tagr.nix`, `beets.nix` with its asset directory `beets/files/` and runner helper `_beets/runners.nix`, and the `ingest.nix` and `storage.nix` contributors with `files/ffmpeg-preprocess.sh`)
- domain aspect contributors (`modules/identity/_oidc.nix` (the intrinsic OIDC contract) with `modules/identity/{kanidm-host-auth,identity-provider,kanidm-runtime}.nix` and the `modules/identity/_kanidm-packages.nix` release-family value, `modules/notifications/{notify,push-server}.nix`, `modules/backups/state-backups.nix` with `modules/backups/state-backups/_consumer.nix`, `modules/cache/{cache-publisher,niks3-cache}.nix`, `modules/music/{music,dj}.nix`, `modules/admin/{cockpit,termix,homepage,webhook}.nix`, `modules/apps/{paperless,karakeep,vaultwarden}.nix`, `modules/observability/{beszel,gatus,phoenix}.nix`, `modules/ai/{bifrost,omniroute}.nix`, `modules/web/web-policy.nix`, `modules/containers/oci-images.nix`, `modules/web/ingress.nix`, `modules/oci/oci.nix`, `modules/contracts/internal.nix`) plus the fleet-baseline and materialization contributors in `modules/flake/` (`base/foundation.nix`, `base/host-recovery.nix`, `shell.nix`, `networking.nix`, `tailscale.nix`, `builder-access.nix`, `observability-agent.nix`, `provenance.nix`, `fleet-packages.nix`, `host-registry.nix`, `bootstrap.nix`, `deploy.nix`) and the sibling contributors beside their owners (`modules/music/{dj-engine,windows-vm}.nix`, `modules/web/ingress.nix`, `modules/database/postgres.nix` with `postgres/_consumer.nix`), plus the `_` helpers `modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, `modules/admin/homepage/_data.nix`, `modules/backups/state-backups/_consumer.nix`, `modules/identity/_oidc.nix`, and `modules/identity/_kanidm-packages.nix`
- `modules/flake/host-registry.nix` (typed `nixos.hosts.<id>` schema + generic materializer) and `modules/flake/bootstrap.nix` (the `flake.bootstrap.nodes` projection)
- `modules/flake/tailscale.nix` (tailscale aspect service leaf)
- `modules/notifications/notify.nix` (notify aspect convention contributor: nix-fleet owns the daemon, the CLI, the `unit-notify` handler and the `services.notify.events` registration contract; this file binds the fleet's Telegram/ntfy policy, topics and secret-file conventions)
- `modules/admin/termix.nix`
- `modules/hosts/la-admin-1/_admin-runtime.nix` (the `/srv/data` operator ACL and its reconcile unit; the `admin/quantum` service leaf, its host file, and the Quantum SSH registrations were deleted with the workload's retirement, TD-07)

Maintenance requirement: changes to active architecture paths, trust boundaries, or operator/CI commands must update canonical docs in the same change window. For features that distinguish deployed infrastructure from end-to-end validated behavior (e.g. AudioMuse first-run setup, Navidrome plugin configuration, Symfonium validation), docs must clearly separate the deployment-complete state from the E2E-accepted state.

Current operator/validation entrypoints that docs should track when they change:

- `just check`
- `just tofu-sync`
- `just tofu-runtime`
- `tests/check-secret-scope.sh`
- `tests/check-web-services-policy.sh`
- `scripts/export-web-services-policy.sh`
- `scripts/render-opentofu-cloudflare-runtime.sh`
- `TD-24` (`open`, low) — the capture-ordering seam between backup producers and the capture backend is expressed by name: `modules/database/postgres.nix` orders its pg_dumpall export before capture by defining `systemd.services."restic-backups-${config.services.state-backups.backupName}"`, and producers write into `services.state-backups.stagingRoot` (vaultwarden does the same for its SQLite export). Both are neutral-half consumers gated on `services.state-backups.enable`, and the declaration surface lives in `modules/backups/state-backups/_consumer.nix`, so registration itself no longer depends on the aspect. A second capture backend would need a neutral capture-target contract (units to order before, staging area) instead of the restic job name. Retirement: a second backend, or that contract.
- `TD-21` (`resolved by modular-postgres-instances`, D-058) — the shared PostgreSQL substrate was a monolith: one consumer-shaped option block per database client (`niks3`/`paperless`/`audiomuse`/`litellm`), so a new consumer meant editing the substrate and a second cluster had no expression at all. It is now a mechanism (`modules/database/postgres.nix`, with the declaration-only contract `modules/database/postgres/_consumer.nix`) rendering from `instances.<name>` plus a consumer registry, with the cluster placed by the aspect published from that same file and consumers registering from their own modules. The retired `litellm` consumer is deleted; niks3 no longer double-declares its database; endpoints resolve per instance through `repo.internal.postgres.<instance>`; and a runbook namespace move (`services.postgres-shared` → `services.postgres`) accompanies it. Refined after review: the credential moved into the registration (`password = { file, key }`), so one file and key are authoritative for both sides; extension packages are contributed in nixpkgs' own shape (`extensions = ps: [ ps.pgvector ]`) and composed by the mechanism, with the SQL in an idempotent `setupSQL`; and AudioMuse's database moved to `home-forge` beside its compute, which removed the last cross-host registration and the hand-synced credential pair along with it (the operator migration path is `docs/runbooks/postgres-consumer-migration.md`). Remaining, recorded rather than hidden: out-of-repository consumers are a future `nix-fleet` registration policy question, and the retired provider-side secret file (`secrets/services/postgres-shared.yaml`) is now read by nothing — deleting it is an operator action.
- `TD-25` (`open`, low) — per-client identity credential files: one encrypted file currently serves every OAuth2 client of a host (`secrets/hosts/<host>/oidc.yaml`), so relocating a workload means re-encrypting that file and editing two explicit bindings — the provider's `services.identity.kanidm.secretFiles.oauth2Clients.<client>` map (`modules/identity/identity-provider.nix`) and the consuming host's `secretFiles.oidc`. The credential belongs to the provider↔client relationship, so a per-client file encrypted to the provider host plus the host running that client would make relocation a single re-encrypt. Operator-owned (secrets and `.sops.yaml` readership are the operator's to decide) and deliberately not coupled to the contract-topology change (`make-oidc-contract-intrinsic`, D-059, which retired the `identity-client` bundle — superseded rather than deprecated, so no compatibility alias exists — and left both credential bindings explicit). Trigger: the next workload move between hosts, or a new client whose secret would widen an existing file's readership.
- `TD-26` (`resolved`) — consuming the shared nix-fleet aspects: nix-fleet publishes `beszel-agent`, `builder-access`, `nh-gc`, `niks3-cache`, `niks3-publisher`, `notify`, `podman-prune` and `tailscale`; every one is now consumed through convention contributors (`modules/flake/tailscale.nix`, `modules/flake/observability-agent.nix` → `beszel-agent`, `modules/flake/builder-access.nix`, `modules/cache/niks3-cache.nix` → the shared `services.niks3-cache.s3.*` surface, `modules/cache/cache-publisher.nix` → `niks3-publisher`, `modules/notifications/notify.nix` → `notify`) — and the two maintenance capabilities `nh-gc` (fleet-wide, selected in `modules/flake/base/foundation.nix`, replacing the local `programs.nh.clean` wiring and its `nh-clean` registration) and `podman-prune`, verified per host on structured observables (option values, `sops.secrets`, systemd unit wiring) with only the intended deltas: the `beszel-agent` namespace rename, the newly bound `services.builder-access.hosts`, upstream's `ControlPath` socket name, `secretFiles.apiToken` replacing `hostSecretFile`, the retired activation-time post-deploy closure push with `pkgs/nix-path-filter`, and upstream's notification redesign (native `OnFailure=`/`OnSuccess=` events replacing `svc-monitor`, `services.notify.events.<unit>` replacing the local `monitor.units` registry, and the local daemon/CLI packages replaced by nix-fleet's).
- `TD-27` (`open`, low) — extraction candidates for nix-fleet: `modules/flake/networking.nix` is the strongest (it renders native networkd config from typed `fleet.networking` facts and names no host), followed by `modules/flake/base/foundation.nix` (boot-loader and `/build` tmpfs facts; needs its `policy/globals.nix` values turned into typed options first), `modules/flake/provenance.nix` (generic `environment.etc."nixos-source"` publication) and `modules/flake/base/host-recovery.nix` (generic reboot/rescue units; its secret and user conventions are homelab-shaped). Retirement: the mechanism lives in nix-fleet and the local file becomes a convention contributor, as with the six shared aspects.
- `TD-28` (`resolved`) — the internal-contract registry (`modules/contracts/internal.nix`, HIC-4, D-056) was retired in favour of the service policy's private-endpoint projection (D-062). It carried two contracts; PostgreSQL's half became dead when D-058 moved the fleet to per-host clusters and AudioMuse followed its compute, leaving one live endpoint and ~300 lines of reflective machinery (`capabilityPath`, `listen.{path,kind}`, cross-host configuration traversal, a 260-line suite, a flake output). `niks3-write` is now declared once in `policy/web-services.nix` (`tailscale-only`, `declarePublic = false`), reaching consumers as `repo.web.catalog."niks3-write".endpoint` with `publicUrl`/`publicHost = null`; the provider derives its listen address from the same declaration, so port drift is unrepresentable. The generic provider-capability check became a concrete assertion in `tests/check-web-service-catalog.sh`, and `modules/music/music.nix` lost its unreachable remote-PostgreSQL fallback in favour of a named assertion. Recorded rather than hidden: the private entry sits under the edge host's service key (the hosts axis means "ingress host that owns this topology"), and `policy/web-services.nix`'s name undersells its content — both tolerated to avoid churn without semantics (D-062).
- `TD-29` (`open`, low) — two bespoke tailnet fronts predate the provider-rendered mechanism (D-063): `modules/admin/cockpit/tailscale-serve.nix` and the `tailscale-serve-termix` unit inside `modules/admin/termix.nix` each hand-roll `tailscale serve --yes --bg --https=…` with their own teardown and daemon-wait semantics — the work the ingress origin-role contributor now owns for policy-declared routes. Converging them removes a duplicate mechanism; it was deferred because cockpit is live on `oci-melb-1` and both fronts expose loopback sockets on ports and shapes the general mechanism does not cover yet. Retirement: both local units deleted, their routes declared with `exposureMode = "tailscale-serve"`, and the fronts verified per host.
- `TD-30` (`open`, medium) — the build path is still deploy-rs plus nixbuild.net. The fleet inventory now declares every host's build capacity and the canonical `ci` builder set (nix-fleet, D-066), and nix-fleet ships per-set artifacts (`packages.ci` / `packages.<set>`) for its `build-push-cache` workflow template, but CI adoption is deferred: the workflow template, a GitHub Actions aarch64 runner, and the architecture-aware coordination between them are unwired, `lib/deploy/hosts.nix` still sets `remoteBuild = true` for two hosts, and `.github/actions/setup-nixbuild` with the nixbuild.net substituter entries in `policy/globals.nix` remains the CI build plane. Target: CI builds and coordinates by architecture (its own runners plus `oci-melb-1` for aarch64), deploy-rs only activates, and local builds are for iteration. Retirement: `remoteBuild` becomes the exception, the CI template installs the rendered bundle, and the nixbuild entries go in the same change if nothing consumes them.
- `TD-31` (`open`, medium) — the interim consumption of nix-fleet's fleet feature (D-066). `flakeModules.fleet` is published as a pre-evaluated module value, so a consumer importing it receives no inventory (`config.fleet.*` empty) while the feature's `perSystem` bundles and `config.fleet.realization` close over nix-fleet's own evaluation — measured: byte-identical `packages.ci`/`packages.fixture` drvs and `knownHosts = [builder-fixture-external, builder-nixbuild, host-fixture-host]`. `modules/flake/builder-access.nix` therefore imports nix-fleet's `modules/fleet/{schema,inventory}.nix` and constructs the realization from `lib/fleet-realization.nix` with our merged config. Retirement: upstream publishes the feature as a module function that imports its inventory; the contributor collapses to one `flakeModules.fleet` import plus `imports = [ config.fleet.realization ]`, the two path imports disappear, and the scaffold ratchet flips back to asserting the documented shape.
