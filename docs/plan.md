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
- `TD-07` (`resolved`) — Quantum residue is fully retired rather than reserved: the service and host modules, the `/srv/data` operator ACL/reconcile unit, the admin SSH SOPS registrations, the Kanidm catalog entry, the `policy/identity.nix` client, and the `kanidm_oauth2_quantum_basic_secret` OIDC client registration are gone from `modules/` and `policy/`, the OIDC and admin secret templates no longer carry a Quantum stub, and `tests/check-identity-contract-directionality.sh` fails if any of those surfaces returns. Re-enablement, if it ever happens, lands as a self-contained aspect consuming canonical identity contracts without restoring `admin-hub` coupling. The operator's encrypted `secrets/applications/admin.yaml` / `secrets/hosts/<host>/oidc.yaml` may still carry the retired keys until their next re-encryption; nothing reads them.

**Follow-up**

- `TD-08` (`resolved`) — Termix is deselected on every host, so the low-priority experiment no longer ships; the aspect and its canonical `termix-admin` web-policy route remain for re-enablement.
- `TD-09` (`follow-up`) — Cockpit still resolves its published identity from the hardcoded canonical key `"cockpit-admin"` (`modules/admin/cockpit.nix`, `modules/admin/cockpit-loopback-tls.nix`), but the route was retired with the demoted cockpit during the edge cutover (it leaked LA-only TLS material into the edge's config): the module now treats the key as optional and requires a `services.admin.cockpit.publicHost` override when it is absent, and the dashboard entry is gone. Re-enablement must re-declare the route (or finish the typed/explicit route-key contract).
- `TD-10` (`follow-up`) — feature-owned monitoring residual semantics: `ExecStopPost` success labeling after failures, shallow composition/self-monitoring hardening, and the real-service predicate intentionally excluding arbitrary raw units. Provenance: completed `openspec/changes/feature-owned-service-monitoring/`; the residuals are deliberate follow-ups, not regressions.
- `TD-11` (`follow-up`) — `tests/check-identity-contract-directionality.sh` is becoming a monolithic second specification. After the current change, split it into focused contract tests with shared fixtures while retaining mutation-based non-vacuity. Included in the split: cumulative subset fixture purity (later subsets inherit mutations from earlier ones), the per-host aspect-selection expectations now duplicated across the three host records and the two contract suites (Stage 8 moved selections from `modules/flake/bootstrap.nix` into `modules/hosts/<host>/default.nix`), and optional coverage for the host-private `_admin-runtime.nix` scaffold fragment in `tests/check-dendritic-scaffold-contract.sh`.

**Superseded cleanup**

- `TD-12` (`superseded-reference`) — `openspec/changes/normalize-fleet-boundaries/` is superseded after its useful requirements were harvested by the landed stages, and it is not a live implementation source. It must not be archived: `openspec archive` would enter never-implemented requirements into the canonical specs, so it is retained deliberately as a reference record (`TD-23`).
- `TD-16` (`resolved`) — `services.identity.kanidm.dataDir` is a typed option carrying the conventional default in `modules/identity/kanidm/server.nix` and the provider body references the option rather than a literal, so a host storing identity state elsewhere declares the path instead of editing the provider.
- `TD-17` (`follow-up`) — support-quartet placement: `provenance`, `oci-images`, `fleet-packages`, and `web-policy` remain contributors in `modules/flake/` (recorded as accepted wiring by `TD-14`). Stage 8 task 5.1 deliberately left them there under the "no repo-wide path-only shuffle" rule; moving them into a fleet/materialization domain is a separate decision to take only when a real ownership pressure appears. Related evidence, not a resolution: the intrinsic OIDC contract (`modules/identity/_oidc.nix`, D-059) is now a working instance of the same shape — a shared surface its consumers import instead of a host selecting it — which is the candidate form for the quartet if a consumer-driven retirement is ever taken up.
- `TD-18` (`resolved`) — the scaffold contract's private-leaf ownership check was worse than layout-dependent: it grepped for `_oci/default.nix`, `_edge/edge-ingress.nix`, and `_dj/*.nix`, filenames retired by the services-tree conversion, so it could not fire and its mutation proved nothing. It is now a path-resolving pass (`private_leaf_strays` in `tests/check-dendritic-scaffold-contract.sh`): relative import expressions are resolved against the tree and an underscore entry under `modules/` is reachable only from inside its owning concern (the domain, or `hosts/<host>` for host fragments), with the three declared intrinsic contracts exempt (`database/postgres/_consumer.nix`, `backups/state-backups/_consumer.nix`, `identity/_oidc.nix`). Verified by measurement: the clean tree reports nothing, a cross-concern `_beets` import and a `homepage/_data.nix` import are both detected, an `identity/kanidm/_packages.nix` import is detected, and a cross-domain `identity/_oidc.nix` import stays allowed. The 7n-3f-2 mutation now exercises the predicate directly.
- `TD-19` (`resolved by restrict-provenance-source-copy`, D-057) — the `/etc/nixos-source` provenance copy shipped the whole working tree, including `.git`, `opentofu/**/.terraform`, `.hp-forge-esp-backup`, editor caches, and plaintext credential files, at ~440 MB per host closure. Resolved by evaluating the flake through the Git-tree form `.#`, which publishes the tracked configuration set (~5.5 MB) and restores a non-null `system.configurationRevision`; the fallback `cleanSourceWith` exclusion list was deleted so tracking stays the single filtering authority.
- `TD-20` (`operational-constraint`) — the `.#` Git-tree form reads the Git index, so a tracked file missing from the index is silently absent from evaluation and from the published provenance. Colocated jj keeps the index in sync and `tests/check-flake-source-tracking.sh` (in `just checks all`) fails with the repair (`git add -A`) when it diverges; index-mutating Git commands (`git reset`, `git checkout`, `git stash`) must not be used in this repository (D-057).

- `TD-22` (`resolved`) — the 20 placeholder capability Purposes are replaced with real sentences derived from each capability's requirements, and one further canonical scenario that the PostgreSQL migration had made false (AudioMuse's database described as remote OCI) now states the local-cluster shape. `openspec validate --all --strict` reports 54 passed, 0 failed, so the repo-wide strict gate is again a usable signal; a stale delta in `navidrome-m3u-itunes-worker` that would have dropped five canonical scenarios was repaired in the same pass.

- `TD-23` (`superseded-reference`) — `openspec/changes/normalize-fleet-boundaries` remains active with 0/22 tasks by its own status header, because it was superseded by the staged Dendritic transition before implementation. Its ownership findings were harvested into the follow-up changes that did execute (notification policy, identity/admin decoupling, host identity and internal contracts, state-backup/cache-publication split) and into the ledger entries above. It is kept as a reference record rather than archived: `openspec archive` applies every delta spec to the canonical capabilities, which would enter requirements the repository never implemented.

**Accepted boundaries — not completion debt**

- `TD-14` (accepted support wiring, not debt) — all-host support contributors (`modules/flake/provenance.nix`, `oci-images.nix`, `fleet-packages.nix`, `web-policy.nix`). Retirement is consumer-driven and optional; recorded here to prevent misclassification as transition completion debt.

**Explicit non-gates**

- `TD-15` (not-a-gate) — full conversion of every service leaf, Den/flake-file adoption, universal service topology, internal DNS, and premature `nix-fleet` extraction are explicitly not completion gates.

## Outstanding Work

Current open items, newest first. Each names the artifact that closes it.

### Deployments pending

- `oci-melb-1`: the deployed generation predates the `auth.shrublab.xyz` route, so the edge answers that hostname with an empty body; redeploying closes the identity staging step as well as the meilisearch qualification below. It was rolled back on `podman-karakeep-meilisearch` (unqualified image reference), now `docker.io/getmeili/meilisearch`.
- **Paperless pin (D-117)** — `nixpkgs-paperless` holds paperless at 3.3.1, the revision the fleet already runs, because 3.3.3 has no aarch64 build upstream and costs hours on the A1. Remove the input and the overlay in `modules/apps/paperless.nix` once a newer paperless substitutes or the fleet cache holds it, then re-evaluate the host to confirm the path moved.
- `home-forge`: rolled back at `navidrome.service` (226/NAMESPACE). The fix — bundling the AudioMuse plugin via `services.navidrome.withPlugins` and dropping the bind whose target the package did not ship — is staged and evaluated; the host also carries the `docker.io` Langfuse image refs and `stopIfChanged = false` on the Windows VM unit. Redeploy closes it.
- `la-admin-1`: last in the queue behind the two above; nothing blocks it.
- `la-admin-1` also carries the identity projection changes since the last activation: the
  Authentik `web.base_url` seed, the invitation stage and enrollment flow, the group chain,
  and the redirect after confirmation.

### Machine access to Access-gated routes (operator-gated)

- The monitoring service token is declared but not created yet: `just tofu-apply` in
  `opentofu/cloudflare` creates it, `tofu output -json machine_access_token` reads it, and
  `just secrets edit secrets/services/gatus.yaml` stores `cf_access_client_id` /
  `cf_access_client_secret` for `owner_age` and `la-admin-1`. LA already binds the path, and
  Gatus switches from accepting the Access login page as healthy to expecting the real status
  as soon as the file exists.
- Turn on **strict service token authentication** (Zero Trust → Settings) once the token is in
  use. Organisations created before 2026-10-05 have it off; organisations created on or after
  that date cannot turn it off. With it on, only Service Auth policies authorise a request
  carrying token headers — Allow policies and any `CF_Authorization` cookie are ignored for that
  request — failures return `401`/`403` instead of a redirect to the login page, and no cookie is
  issued. That converts a token that is silently falling back to cookie auth, or one whose policy
  was mis-shaped, into a loud failure the Gatus conditions already treat as down.

### Gatus probes and route health paths

- Every route in `policy/web-services.nix` still declares `health.path = "/"` with
  `expectedStatus = 200`, which the token does not make more meaningful: behind a service token
  `/` is the application's own login page — `200` for Grafana, Homepage and Cockpit, but a `302`
  to `/accounts/login/` for Paperless. Landing the token before this refactor turns those routes
  red for a reason that is not an outage.
- Refactor each route's `health.path` toward an endpoint that answers without application
  authentication and reflects a dependency where the app offers one — Grafana `/api/health`
  reports its database, Syncthing `/rest/noauth/health` reports the daemon. A route with no such
  endpoint keeps its login-page `200`; that is a truthful "up" signal and must not be read as
  "healthy".
- Decide the second probe class explicitly. The public URL through the edge is the only probe
  that can see DNS, certificate, Authenticated Origin Pulls, the edge-to-origin front and the
  origin listener; `repo.web.catalog.<id>.endpoint` sees the application and skips all of it.
  Default is public-only, with the endpoint probe added where an edge fault would otherwise
  page for an application that is fine.

### Identity cutover (operator-gated)

- `<app>-user` / `<app>-admin` roles are declared and bound, but no client reads them yet:
  application role mappings still name fleet groups. Migrate them one application at a time
  once a live token proves the claim carries both, so a per-app role becomes a binding
  change rather than a group-tree change.

- The tree names Authentik as the active provider and no host selects Kanidm; `kanidm-admin`
  (`id.shrublab.xyz`) is deleted from policy, so the next `just tofu apply` destroys its DNS
  record. The Kanidm code stays for the observation window, dormant.
- Deploy `oci-melb-1`, then `home-forge`, then `la-admin-1`. The provider host last, because its
  deploy carries the blueprint.
- Operator steps before the deploys: add `Access: Service Tokens → Edit` to the Cloudflare API
  token, delete geopulse's `authentik` row from `oidc_providers` (a database row shadows the
  declarative configuration), and move `beszel` and `bookorbit` to the Authentik issuer in
  their own admin UIs.
- Accept the replacement email-code flows live: invitation enrollment, unverified login, and
  verification after an address change. Link-based address recording was observed; native-code
  integration still needs its own acceptance. Follow `docs/runbooks/identity-migration.md`.

### Email verification enforcement (partly landed)

- **Implemented, awaiting acceptance — email codes.** One native code stage serves enrollment,
  login gating and signed-in re-verification. Proof must match the user, current address and
  verification stage before activation/recording; its temporary device is then consumed.
  The code is entered in the original browser, replacing link-based continuation.
- **Outstanding — the application policy.** The gate withholds a *session*; a session that
  predates an address change still passes into applications. The enforcement point for that is an
  application-level policy (`email and email_verified_address == email`) with
  `policy_engine_mode = "all"`, so it ANDs with the group policy. Off for the console clients
  (grafana, beszel, termix) and `cloudflare-access`, so whoever holds the console can repair an
  account. Not blocking the cutover; the login gate already keeps new sessions verified.
- **Outstanding — the courtesy prompt.** An authorize attempt by an already-signed-in unverified
  user is denied by the application policy with the stock access-denied screen. A nicer path
  needs a dynamic `next` back into the authorize URL, which a redirect stage cannot express
  (no templating), so this stays as-is unless custom code is ever justified.
- **Deferred — MFA enrolment at registration.** An authenticator-validate stage at order 150 in
  `enrollment` with `not_configured_action = configure` was attempted and reverted: the apply
  failed because `configuration_stages` is a many-to-many to **Stage**, not to the
  `default-authenticator-*-setup` flows, and the configure path either inserts one configuration
  stage directly or presents a chooser. Wiring it means declaring or referencing the webauthn and
  totp authenticator stages and choosing single-versus-chooser. Until then enrolment ends logged in
  with MFA available from user settings.
- Groups are the wrong lever for either: they carry no policies, and verification is a property of
  the person, not of membership. A change-email flow reuses `verify-email` unchanged — the recorded
  address stops matching, so the gates close and re-verification reopens them.
- **Deferred — resend controls.** The pinned native code-entry screen has no Resend button, so
  accidental repeated clicks are not a current risk. The operator accepts the remaining scripted
  send/restarted-flow risk; no backend patch or send limiter blocks rollout. Revisit if a resend
  action is added or actual abuse appears. Link-page polling/continuation is superseded by code entry.
- **Implemented, awaiting acceptance — passkeys.** Enrollment requires discoverable credentials
  and user verification; identification offers passkeys plus username/email password fallback.
  Test a new credential and fresh passwordless sign-in before cutover. Automatic enrollment
  during registration remains deferred; credentials are enrolled in user settings.

### Perimeter topology (to review, not blocking)

- Whether Cloudflare Access should carry per-route authorization at all. Today the twelve gated
  routes split into thirteen Access applications whose policies (`allow_admins` email constant,
  `allow_users` OIDC group claim) restate a decision the identity provider already makes in its
  own vocabulary — `admins`, `service-admins`, per-app entitlements. Cloudflare's own guidance
  points the other way from a collapse: use multiple domains in one application only for genuine
  cross-domain dependencies, and otherwise one primary domain per application with automated
  policy management, which is what the current shape already does. So the question is not
  topology but authority: either Access stays a perimeter and its policy becomes one coarse
  household rule, or route-level authz moves to the origin (`forward_auth` in Caddy against
  Authentik) and Access keeps the per-host applications. Revisit when a second person enrolls or
  a route genuinely diverges; nothing here blocks the cutover.

### Shared assets publication (awaiting validation and deployment)

- The existing `shrublab-assets` R2 bucket serves `assets.shrublab.xyz`. The
  `publish-shared-assets` change adds central source policy, per-asset runtime publication and
  all twelve routed dashboard icons, plus the consumed brand vectors. The three-app pilot
  was approved; the expanded rollout still needs deployment acceptance.
  Complete the repository gates, deploy oci-melb-1 and home-forge, then la-admin-1, and record live acceptance
  using [the asset runbook](runbooks/assets.md). Termix's source is configured but its publisher remains dormant until its aspect is selected.
- Wallpaper stays manually uploaded. Bucket/domain ownership stays outside this change;
  publishers do not prune objects or change Cloudflare Access.

### Follow-ups agreed in review

- `publish` / `declarePublic` / `exposureMode` overlap: `resolveCloudflareHosts` ignores `publish`, so a draft route still emits a DNS record. Collapse into one `posture` value after the cutover. (Session note #275.)
- GeoPulse's source build is a historical default, not a decision. `pkgs/geopulse/` predates the OCI image policy and carries two hand-verified fixed-output hashes (`mvnHash`, `npmDepsHash`) plus a Maven-version assertion, so every nixpkgs Maven bump or upstream release is a manual hash regeneration across two ecosystems. Its original justification is gone: the PKCE patch was removed (D-108) and the last local artifact, `pkgs/geopulse/migrations/R__Add_oidc_session_code_verifier.sql`, installs a column the pinned 2.1.1 sources never read. Upstream publishes multi-arch images for the exact compose tags (`tess1o/geopulse-backend:<v>-native` and `tess1o/geopulse-ui:<v>` are both amd64+arm64), so `aarch64-linux` is first-class. Moving it to digest-pinned containers costs a two-container shape (backend + UI nginx, or our Caddy front proxying the UI container) and a mount rewrite (`/app/keys`, `/data/geopulse-import`, `/data/geopulse-backups`), while PostgreSQL stays ours. Worth doing as its own change.
- Service-scoped secret defaults: about 25 `secrets/services/*.yaml` and `secrets/applications/*.yaml` paths are still bound in host records (paperless, bifrost, langfuse, degoog, homarr, tududi, the ntfy and notification-daemon files, music, and others). Each belongs in its owning module as a default through `secretHelpers.mkSecretFileOptionWithDefault`, so moving or adding an aspect edits no host. Host-scoped paths (`secrets/hosts/<host>/...`) stay in host records. Governed by the CONVENTIONS.md secret-ownership rule. Migrate as one change with the gates rerun, since a default makes its file required wherever the aspect is selected.
- Grafana sits inside the `victoria` aspect and option namespace. D-074 placed the store and its front end in one file so Grafana's provisioned datasource uids and listener ports come from the same declarations as the stores, and that is still sound. The namespace is not: Grafana's OIDC switch, `secretFiles.oidc`, and the break-glass `secretFiles.admin` are all `services.victoria.*`, although the Grafana service is `services.grafana` and nixpkgs' own module owns that namespace. Fix: a `grafana` aspect in `modules/observability/grafana.nix` that owns `services.grafana` options and the Grafana secret defaults, consuming the store's datasource contract (uids, ports, endpoints) as read-only data published by `victoria`, so `victoria` keeps only the three stores. Constraints for the change: datasource uids are provisioned state, so changing one needs Grafana's provisioned state cleared before activation (ARCHITECTURE.md, Observability); `services.victoria.oidc.enable` and its binding move with the option, so the Grafana identity client and the home-forge OIDC secret binding must move in the same change. Recorded before the Grafana SSO deployment so the rename happens before anyone relies on the `services.victoria.*` paths.
- Route-derived module defaults: `karakeep.publicUrl`, Paperless' `PAPERLESS_URL`, `niks3-cache.cacheUrl` and Cockpit's `publicHost` restate a host a route already declares. Deriving them from `repo.web.catalog` needs a policy for a route that is not yet published (D-116).
- Runbook sweep under the new `AGENTS.md` rule: `actual-memos-tududi.md`, `homarr.md`, `home-assistant.md` and `postgres-consumer-migration.md` still carry mechanism prose that belongs in `docs/`.
- Windows VM lifecycle: an idle reaper plus socket-activated RDP, gated first on proving a graceful `windows-vm-stop` (the deploy stall showed the guest did not stop inside its 180 s window).

### Known ceilings, no action planned

- `authentik-nix` tracks upstream `main` with no `follows` and no Renovate manager: a `nix flake update` can move it, and upstream may reshape blueprint fields that only fail at apply time. Accepted for now (six of seven components substitute from nix-community's cache; `gopkgs` builds locally when upstream touches Go).
- Senders share one domain and one relay, so a blocklist or reputation hit takes all of them. Revisit if one service's volume starts affecting the others' delivery (`docs/mail.md`).

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
- domain aspect contributors (`modules/identity/_oidc.nix` (the intrinsic OIDC contract) with `modules/identity/{kanidm-host-auth,identity-provider,kanidm-runtime}.nix` and the `modules/identity/kanidm/_packages.nix` release-family value, `modules/notifications/{notify,push-server}.nix`, `modules/backups/state-backups.nix` with `modules/backups/state-backups/_consumer.nix`, `modules/cache/{cache-publisher,niks3-cache}.nix`, `modules/music/{music,dj}.nix`, `modules/admin/{cockpit,termix,homepage,webhook}.nix`, `modules/apps/{paperless,karakeep,vaultwarden}.nix`, `modules/observability/{beszel,gatus,phoenix}.nix`, `modules/ai/{bifrost,omniroute}.nix`, `modules/web/web-policy.nix`, `modules/containers/oci-images.nix`, `modules/web/ingress.nix`, `modules/oci/oci.nix`, `modules/contracts/internal.nix`) plus the fleet-baseline and materialization contributors in `modules/flake/` (`base.nix`, `base-host-recovery.nix`, `shell.nix`, `networking.nix`, `tailscale.nix`, `builder-access.nix`, `observability-agent.nix`, `provenance.nix`, `fleet-packages.nix`, `host-registry.nix`, `bootstrap.nix`, `deploy.nix`) and the sibling contributors beside their owners (`modules/music/{dj-engine,windows-vm}.nix`, `modules/web/ingress.nix`, `modules/database/postgres.nix` with `postgres/_consumer.nix`), plus the `_` helpers `modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, `modules/admin/homepage/_data.nix`, `modules/backups/state-backups/_consumer.nix`, `modules/identity/_oidc.nix`, and `modules/identity/kanidm/_packages.nix`
- `modules/flake/host-registry.nix` (typed `nixos.hosts.<id>` schema + generic materializer) and `modules/flake/deploy.nix` (deploy-rs wiring plus the published `fleet` facts, including each host's `bootstrap` slice)
- `modules/flake/tailscale.nix` (tailscale aspect service leaf)
- `modules/notifications/notify.nix` (notify aspect convention contributor: nix-fleet owns the daemon, the CLI, the `unit-notify` handler and the `services.notify.events` registration contract; this file binds the fleet's Telegram/ntfy policy, topics and secret-file conventions)
- `modules/admin/termix.nix`
- `modules/hosts/la-admin-1/_admin-runtime.nix` (the `/srv/data` operator ACL and its reconcile unit; the `admin/quantum` service leaf, its host file, and the Quantum SSH registrations were deleted with the workload's retirement, TD-07)

Maintenance requirement: changes to active architecture paths, trust boundaries, or operator/CI commands must update canonical docs in the same change window. For features that distinguish deployed infrastructure from end-to-end validated behavior (e.g. AudioMuse first-run setup, Navidrome plugin configuration, Symfonium validation), docs must clearly separate the deployment-complete state from the E2E-accepted state.

Current operator/validation entrypoints that docs should track when they change:

- `just check`
- `just tofu-sync`
- `just tofu-runtime`
- `tests/check-web-services-policy.sh`
- `scripts/export-web-services-policy.sh`
- `scripts/render-opentofu-cloudflare-runtime.sh`
- `TD-24` (`open`, low) — the capture-ordering seam between backup producers and the capture backend is expressed by name: `modules/database/postgres.nix` orders its pg_dumpall export before capture by defining `systemd.services."restic-backups-${config.services.state-backups.backupName}"`, and producers write into `services.state-backups.stagingRoot` (vaultwarden does the same for its SQLite export). Both are neutral-half consumers gated on `services.state-backups.enable`, and the declaration surface lives in `modules/backups/state-backups/_consumer.nix`, so registration itself no longer depends on the aspect. A second capture backend would need a neutral capture-target contract (units to order before, staging area) instead of the restic job name. Retirement: a second backend, or that contract.
- `TD-21` (`resolved by modular-postgres-instances`, D-058) — the shared PostgreSQL substrate was a monolith: one consumer-shaped option block per database client (`niks3`/`paperless`/`audiomuse`/`litellm`), so a new consumer meant editing the substrate and a second cluster had no expression at all. It is now a mechanism (`modules/database/postgres.nix`, with the declaration-only contract `modules/database/postgres/_consumer.nix`) rendering from `instances.<name>` plus a consumer registry, with the cluster placed by the aspect published from that same file and consumers registering from their own modules. The retired `litellm` consumer is deleted; niks3 no longer double-declares its database; endpoints resolve per instance through `repo.internal.postgres.<instance>`; and a runbook namespace move (`services.postgres-shared` → `services.postgres`) accompanies it. Refined after review: the credential moved into the registration (`password = { file, key }`), so one file and key are authoritative for both sides; extension packages are contributed in nixpkgs' own shape (`extensions = ps: [ ps.pgvector ]`) and composed by the mechanism, with the SQL in an idempotent `setupSQL`; and AudioMuse's database moved to `home-forge` beside its compute, which removed the last cross-host registration and the hand-synced credential pair along with it (the operator migration path is `docs/runbooks/postgres-consumer-migration.md`). Remaining, recorded rather than hidden: out-of-repository consumers are a future `nix-fleet` registration policy question, and the retired provider-side secret file (`secrets/services/postgres-shared.yaml`) is now read by nothing — deleting it is an operator action.
- `TD-25` (`open`, low) — per-client identity credential files: one encrypted file currently serves every OAuth2 client of a host (`secrets/hosts/<host>/oidc.yaml`), so relocating a workload means re-encrypting that file and editing two explicit bindings — the provider's `services.identity.kanidm.secretFiles.oauth2Clients.<client>` map (`modules/identity/identity-provider.nix`) and the consuming host's `secretFiles.oidc`. The credential belongs to the provider↔client relationship, so a per-client file encrypted to the provider host plus the host running that client would make relocation a single re-encrypt. Operator-owned (secrets and `.sops.yaml` readership are the operator's to decide) and deliberately not coupled to the contract-topology change (`make-oidc-contract-intrinsic`, D-059, which retired the `identity-client` bundle — superseded rather than deprecated, so no compatibility alias exists — and left both credential bindings explicit). Trigger: the next workload move between hosts, or a new client whose secret would widen an existing file's readership.
- `TD-26` (`resolved`) — consuming the shared nix-fleet aspects: nix-fleet publishes `beszel-agent`, `builder-access`, `nh-gc`, `niks3-cache`, `niks3-publisher`, `notify`, `podman-prune` and `tailscale`; every one is now consumed through convention contributors (`modules/flake/tailscale.nix`, `modules/flake/observability-agent.nix` → `beszel-agent`, `modules/flake/builder-access.nix`, `modules/cache/niks3-cache.nix` → the shared `services.niks3-cache.s3.*` surface, `modules/cache/cache-publisher.nix` → `niks3-publisher`, `modules/notifications/notify.nix` → `notify`) — and the two maintenance capabilities `nh-gc` (fleet-wide, selected in `modules/flake/base.nix`, replacing the local `programs.nh.clean` wiring and its `nh-clean` registration) and `podman-prune`, verified per host on structured observables (option values, `sops.secrets`, systemd unit wiring) with only the intended deltas: the `beszel-agent` namespace rename, the newly bound `services.builder-access.hosts`, upstream's `ControlPath` socket name, `secretFiles.apiToken` replacing `hostSecretFile`, the retired activation-time post-deploy closure push with `pkgs/nix-path-filter`, and upstream's notification redesign (native `OnFailure=`/`OnSuccess=` events replacing `svc-monitor`, `services.notify.events.<unit>` replacing the local `monitor.units` registry, and the local daemon/CLI packages replaced by nix-fleet's).
- `TD-27` (`open`, low) — extraction candidates for nix-fleet: `modules/flake/networking.nix` is the strongest (it renders native networkd config from typed `fleet.networking` facts and names no host), followed by `modules/flake/base.nix` (boot-loader and `/build` tmpfs facts; needs its `policy/globals.nix` values turned into typed options first), `modules/flake/provenance.nix` (generic `environment.etc."nixos-source"` publication) and `modules/flake/base-host-recovery.nix` (generic reboot/rescue units; its secret and user conventions are homelab-shaped). Retirement: the mechanism lives in nix-fleet and the local file becomes a convention contributor, as with the six shared aspects.
- `TD-28` (`resolved`) — the internal-contract registry (`modules/contracts/internal.nix`, HIC-4, D-056) was retired in favour of the service policy's private-endpoint projection (D-062). It carried two contracts; PostgreSQL's half became dead when D-058 moved the fleet to per-host clusters and AudioMuse followed its compute, leaving one live endpoint and ~300 lines of reflective machinery (`capabilityPath`, `listen.{path,kind}`, cross-host configuration traversal, a 260-line suite, a flake output). `niks3-write` is now declared once in `policy/web-services.nix` (`tailscale-only`, `declarePublic = false`), reaching consumers as `repo.web.catalog."niks3-write".endpoint` with `publicUrl`/`publicHost = null`; the provider derives its listen address from the same declaration, so port drift is unrepresentable. The generic provider-capability check became a concrete assertion in `tests/check-web-service-catalog.sh`, and `modules/music/music.nix` lost its unreachable remote-PostgreSQL fallback in favour of a named assertion. Recorded rather than hidden: the private entry sits under the edge host's service key (the hosts axis means "ingress host that owns this topology"), and `policy/web-services.nix`'s name undersells its content — both tolerated to avoid churn without semantics (D-062).
- `TD-29` (`open`, low) — two bespoke tailnet fronts predate the provider-rendered mechanism (D-063): `modules/admin/cockpit-tailscale-serve.nix` and the `tailscale-serve-termix` unit inside `modules/admin/termix.nix` each hand-roll `tailscale serve --yes --bg --https=…` with their own teardown and daemon-wait semantics — the work the ingress origin-role contributor now owns for policy-declared routes. Converging them removes a duplicate mechanism; it was deferred because cockpit is live on `oci-melb-1` and both fronts expose loopback sockets on ports and shapes the general mechanism does not cover yet. Retirement: both local units deleted, their routes declared with `exposureMode = "tailscale-serve"`, and the fronts verified per host.
- `TD-30` (`resolved`, D-082) — the build path was deploy-rs plus nixbuild.net. The fleet inventory declared every host's build capacity and the canonical `ci` builder set (nix-fleet, D-066) while CI still remote-built host toplevels against `ssh-ng://eu.nixbuild.net` and the deploy workflows prebuilt profiles the same way. CI now builds the nix-standard `.#checks` target through nix-fleet's reusable `build-push-cache` workflow, with the canonical coordinator key authorized by the `build-account` aspect on all three hosts and publication to the fleet cache; each host's activatable profile is published as `checks.<system>.host-<host>` (with `packages.host-*` mirroring the same derivations unfiltered, which is what `just prebuild-local` resolves) so CI's target and the deploy surface cannot drift; and the deploy path only activates, verifying the exact profile is substitutable before it does. `.github/actions/setup-nixbuild` is deleted, and the `nix flake check --no-build` gate is gone because evaluating the flake realises degoog's unsubstitutable bun2nix import-from-derivation. Host scheduling stays off (`nix.buildMachines` unpopulated, as upstream also leaves it), and `trusted-substituters` keeps nix-fleet's `ssh-ng://eu.nixbuild.net` entry with no local consumer — an upstream leftover rather than local debt. Outstanding evidence, tracked by the change rather than by this entry: the first manual dispatch must show a real uncached build on each architecture followed by signature-checked substitution, since a green workflow alone cannot distinguish "CI built it" from "CI found it cached".
- `TD-31` (`resolved`) — the interim consumption of nix-fleet's fleet feature is gone twice over: nix-fleet v2 deleted the cross-class realization entirely and publishes facts plus pure projections (`flake.lib.buildProfile`). The contributor imports `flakeModules.fleet`, closes over this evaluation's `config.fleet`, and projects trust for the hosts that offer build capability (D-068); the scaffold ratchet asserts that shape. The feature also contributes `checks.fleet-render` and the CI builder bundles (`packages.ci`, `packages.arm-expensive`) in this repository's evaluation; adopting those bundles as the CI build path is `TD-30`. One upstream leak remains: `packages.fixture` still arrives from nix-fleet's own fixture profile.
