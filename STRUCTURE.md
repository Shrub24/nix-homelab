# Codebase Structure

## Directory Layout

```
nix-homelab/
├── .github/         # CI/CD workflows, actions, and skill prompts
│   ├── actions/     # Composite GitHub Actions (setup-nixbuild)
│   ├── prompts/     # OpenAgentsControl skill prompts (opsx-*)
│   ├── skills/     # OpenAgentsControl skill definitions
│   └── workflows/   # CI/CD pipeline definitions
├── .just/          # Modular justfile includes (ops, checks, backups, host-age, deps, dev)
├── docs/            # Human-facing architecture, planning, and runbook docs
├── generated/       # Committed generated artifacts (e.g., web policy JSON)
├── lib/             # Reusable Nix library functions
├── modules/             # Flake-parts modules + NixOS modules (domain aspect contributors + private leaves, canonical host contributors, fleet contracts, services, flake materialization)
├── pkgs/            # Custom Nix packages/derivations (notification-daemon, notify CLI, _sources/)
├── openspec/        # OpenSpec change management artifacts
├── opentofu/        # OpenTofu infrastructure-as-code (Cloudflare)
├── policy/          # Canonical fleet-wide defaults and web service policy
├── scripts/         # Operator-facing shell utilities
├── secrets/         # SOPS-encrypted secrets with blast-radius scoping
├── tests/           # Validation scripts and contract checks
├── certs/          # TLS certificate material
├── flake.nix        # Minimal flake-parts entrypoint: input pins + import-tree discovery of modules/
├── flake.lock      # Pinned flake input revisions
├── .sops.yaml      # Central SOPS recipient policy with path-scoped rules
├── nvfetcher.toml   # nvfetcher config for non-flake upstream sources
├── renovate.json    # Renovate config (flake inputs + OCI image refs)
├── justfile        # Task runner with modular sub-module imports
├── deploy.sh       # nixos-anywhere bootstrap script
├── CONVENTIONS.md  # Module structure and naming conventions
├── ARCHITECTURE.md # Architecture documentation (this file)
├── STRUCTURE.md     # Codebase structure documentation (this file)
└── README.md       # Project orientation
```

## Directory Purposes

**`.github/workflows/`:**

- Purpose: CI/CD automation
- Contains: `ci.yml` (lightweight automatic validation + manual host remote-builds), `deploy.yml` (manual full deploy pipeline), `deploy-host.yml` (reusable host deploy), `nvfetcher-refresh.yml` (scheduled non-flake source regeneration)
- Key files: `.github/workflows/deploy.yml`, `.github/workflows/ci.yml`, `.github/workflows/nvfetcher-refresh.yml`

**`.github/actions/`:**

- Purpose: Reusable composite GitHub Actions
- Contains: `setup-nixbuild/` — configures nixbuild.net SSH key and remote builder for CI
- Key files: `.github/actions/setup-nixbuild/action.yml`

**`.github/prompts/`:**

- Purpose: OpenAgentsControl skill prompts for agent workflows
- Contains: `opsx-propose.prompt.md`, `opsx-explore.prompt.md`, `opsx-archive.prompt.md`, `opsx-apply.prompt.md`
- Used by: OpenAgentsControl agent execution flows

**`.github/skills/`:**

- Purpose: OpenAgentsControl skill definitions for spec-driven change workflows
- Contains: `openspec-apply-change/`, `openspec-archive-change/`, `openspec-explore/`, `openspec-propose/`

**`.just/`:**

- Purpose: Modular justfile includes — each file covers one domain
- Contains: `ops.just`, `checks.just`, `backups.just`, `host-age.just`, `deps.just`, `dev.just` (the orphaned `deploy.just` was deleted; the root justfile owns the `deploy` recipe directly)
- Imported by: `justfile` via `mod` directives

**`docs/`:**

- Purpose: Canonical human-facing architecture, planning, and runbook documentation
- Contains: `architecture.md`, `decisions.md`, `plan.md`, `context-history.md`, `runbooks/`
- Key files: `docs/architecture.md`, `docs/decisions.md`, `docs/runbooks/host-initialization.md` (generic host bring-up), `docs/runbooks/admin-host-migration.md` (LA transfer facts)

**`modules/flake/`:**

- Purpose: What remains after the Stage 8 relocation — flake output/materialization concerns, the fleet baseline, and the infrastructure support quartet; discovered by `denful/import-tree` from `flake.nix` exactly like every other domain contributor
- Contains: `host-registry.nix` (the typed `nixos.hosts.<id>` schema plus the generic materializer into `flake.nixosConfigurations` through `inputs.nixpkgs.lib.nixosSystem`, with named `host-registry:` validation errors), `registry.nix` (reduced to the `flake.bootstrap.nodes` projection over `config.nixos.hosts`), `deploy.nix` (deploy-rs wiring plus canonical-host-ID validation), `packages.nix`, `dev.nix`, `scaffold.nix`, the infrastructure support quartet `provenance.nix`, `oci-images.nix`, `fleet-packages.nix`, `web-policy.nix`, the foundation aspects `base/` (`foundation.nix` + `host-recovery.nix`), `shell.nix` (with `shell/p10k.zsh`), `networking.nix`, `tailscale.nix`, `builder-access.nix`, `observability-agent.nix`, the remaining placement aspects `paperless.nix`, `ai-gateway.nix`, `karakeep.nix`, `phoenix.nix`, `omniroute.nix` (each owning its capability's top-level enablement), and `_unconverted-nixos-dirs.nix` (the enumerated `filterNot` boundary, now an empty list: the post-Stage-8 services-tree conversion converted the last root, and an entry returns only when a genuinely transitional plain-module directory appears)
- Key files: `modules/flake/host-registry.nix`, `modules/flake/registry.nix`, `modules/flake/deploy.nix`, `modules/flake/web-policy.nix`, `modules/flake/base/foundation.nix`, `modules/flake/base/host-recovery.nix`, `modules/flake/_unconverted-nixos-dirs.nix`

The former `modules/core/`, `modules/profiles/`, `modules/shared/`, and `modules/storage/` directories no longer exist: dendritic Stage 2 (`dendritic-stage-2-foundation-aspects`) converted the core/profile contents into the foundation aspects above (with typed `fleet.foundation` host facts), and dendritic Stage 3 (`dendritic-stage-3-operational-aspects`) converted the five deferred operational leaves into the `builder-access` and `observability-agent` aspects plus the combined `backups` aspect (since split by D-055 into `state-backups` and `cache-publisher`); no host imports the deleted wrappers or the five leaves directly. Dendritic Stage 4 (`dendritic-stage-4-source-model-realignment`) replaced the central `aspects.nix` publication file with concern-owned discovered contributors and classified `provenance`/`oci-images`/`fleet-packages` as infrastructure support (D-050). Dendritic Stage 5 (`dendritic-stage-5-shared-source-contributors`, D-051) deleted the `shared`/`storage` roots, relocated the remaining private leaves beside their aspect owners (`_aspects`, `_backups`, `_builder-access`), promoted `web-policy` to a discovered all-host support contributor, merged `identity-oidc`/`kanidm-host-auth` into the single `identity-client` aspect, and shrank the filter from six entries to four (D-059 later retired that bundle: the OIDC contract is the intrinsic `modules/identity/_oidc.nix` and the capability is `kanidm-host-auth`). Dendritic Stage 6 (`dendritic-stage-6-music-composition`, D-052) converted the music stack from the directly host-imported `modules/applications/music/default.nix` coordinator into the discovered home-forge-only `music` aspect (now `modules/music/music.nix`; selection provides `applications.music.enable`), moved Beets secret/template/CLI ownership plus the ingest and storage/permission mechanisms into sibling contributors under `modules/music/**`, and gave `dj` a typed read-only `applications.music.contract` with a named assertion; the four-root filter is unchanged, and the change landed as `dendritic-stage-6-music-composition` (archived 2026-09-13). Dendritic Stage 7 (`dendritic-stage-7-placement-aspects`, D-053) converted every remaining deployed product/platform capability into a discovered placement aspect, relocated the admin/edge/DJ/OCI implementations beside their concern owners, deleted `modules/applications/` and `modules/providers/`, and shrank the filter to `hosts` and `services`; `decouple-identity-admin-capabilities` (D-054) then dissolved `admin-hub` into individual aspects. Dendritic Stage 8 (`dendritic-stage-8-host-identity-contracts`, D-056) made host identity a typed discovered record, reduced `modules/flake/registry.nix` to the bootstrap projection, removed `hosts` from the filter (now exactly `[ "services" ]`), added canonical-host-ID validation to deploy and web metadata, added the two internal transport contracts under `modules/fleet/`, and moved the settled concern contributors from the flat `modules/flake/` bucket into their domain directories.

**`modules/identity/`:**

- Purpose: Identity domain — the intrinsic OIDC contract, the Kanidm host-auth capability, and the Kanidm provider
- Contains: the intrinsic OIDC contract (`_oidc.nix`, imported by its readers instead of selected), the `kanidm-host-auth` capability (`kanidm-host-auth.nix` with the Kanidm client/unix/PAM/SSH wiring), and `identity-provider.nix` (the Kanidm server/provisioning aspect; selected on `la-admin-1`)
- Key files: `modules/identity/_oidc.nix`, `modules/identity/_kanidm-packages.nix`, `modules/identity/kanidm-host-auth.nix`, `modules/identity/identity-provider.nix`, `modules/identity/kanidm-runtime.nix`

**`modules/notifications/`:**

- Purpose: Notification domain — dispatch baseline and the LA ntfy publisher
- Contains: `notify.nix` (the foundation aspect, which carries the notification-daemon body inline) and `push-server.nix` (LA ntfy)
- Key files: `modules/notifications/notify.nix`, `modules/notifications/push-server.nix`

**`modules/cache/`:**

- Purpose: Cache domain — closure publication and the cache server
- Contains: `cache-publisher.nix` (Niks3 closure publication: the upload client and post-deploy leaves published as siblings in `cache-publisher/`, the typed `nix-path-filter` injection, the host secret gate), `niks3-cache.nix` (the OCI cache server capability, whose body carries the former cache-server leaf inline)
- Key files: `modules/cache/cache-publisher.nix`, `modules/cache/cache-publisher/post-deploy.nix`, `modules/cache/niks3-cache.nix`

**`modules/backups/`:**

- Purpose: Mutable-state recovery domain — one capture mechanism with a shared declaration surface
- Contains: `state-backups.nix` (the restic mechanism: capture job rendering, derived bucket, host secret gate, restore-staging helper) and `state-backups/_consumer.nix` (declaration-only: the `services.state-backups.services.<name>` registry plus the capture settings a producer reads, imported by the mechanism and by every registering feature so registration does not require the aspect)
- Key files: `modules/backups/state-backups.nix`, `modules/backups/state-backups/_consumer.nix`

**`modules/music/`:**

- Purpose: Music domain — the home-forge music stack and the DJ application
- Contains: `music.nix` (home-forge-only composition aspect; selection provides `applications.music.enable`), `dj.nix` (application aspect consuming the read-only `applications.music.contract`), and the private DJ implementation `_dj/default.nix` + `_dj/engine-dj.nix`
- Key files: `modules/music/music.nix`, `modules/music/dj.nix`, `modules/music/dj-engine.nix`

**`modules/admin/`:**

- Purpose: Admin surface domain — the self-contained admin capability aspects
- Contains: `cockpit.nix`, `termix.nix`, `vaultwarden.nix`, `homepage.nix`, `gatus.nix`, `beszel.nix`, `webhook.nix` (each owning its capability's enablement, runtime wiring, and secret contract; all selected individually on `la-admin-1` since `admin-hub` was dissolved by D-054)
- Key files: `modules/admin/cockpit.nix`, `modules/admin/termix.nix`, `modules/admin/homepage.nix`

**`modules/edge/`:**

- Purpose: Edge/origin ingress domain
- Contains: `edge.nix` (the discovered role-based proxy aspect), `edge-ingress-application.nix` (the routes projection), and `edge-ingress-runtime.nix` (the Caddy runtime)
- Key files: `modules/edge/edge.nix`, `modules/edge/edge-ingress-application.nix`, `modules/edge/edge-ingress-runtime.nix`

**`modules/oci/`:**

- Purpose: Provider domain — OCI/Oracle Cloud host-safe defaults
- Contains: `oci.nix` (the provider aspect, with the provider body inline)
- Key files: `modules/oci/oci.nix`

**`modules/fleet/`:**

- Purpose: Fleet-wide cross-host contracts
- Contains: `internal-contracts.nix` (the two internal transport contracts — shared PostgreSQL and the private Niks3 write API — publishing `flake.internalContracts` and the per-host `repo.internal` surface)
- Key files: `modules/fleet/internal-contracts.nix`

**`modules/hosts/`:**

- Purpose: Canonical host identity — one discovered flake-parts contributor per host declaring a typed `nixos.hosts.<id>` record, plus the host-private NixOS composition that record selects
- Contains: `default.nix` (the record: `system`, `tailscale.{hostname,tailnetSuffix}`, `composition.{extraModules,aspects,fragments}`, and reimage `bootstrap` metadata projected to `flake.bootstrap.nodes`), the private `_nixos.nix` composition, underscore-prefixed fragments (`_disko-*.nix`, `_cockpit-auth.nix`, `_admin-runtime.nix`), and committed `facter.json` (`hardware.facter.reportPath`; kept un-prefixed because its path is a host-derivation input)
- Key files: `modules/hosts/oci-melb-1/default.nix`, `modules/hosts/la-admin-1/default.nix`, `modules/hosts/home-forge/default.nix`, `modules/hosts/oci-melb-1/_nixos.nix`

**`modules/applications/` (deleted in dendritic Stage 7, D-053):**

- Purpose: former evaluator-class root for multi-service feature composition
- Contains: nothing; the root was deleted after every implementation moved beside its discovered concern owner. The music stack became the `music` aspect (Stage 6, D-052); the admin split became the `identity-provider` and `cockpit` contributors and was then dissolved further into individual workload aspects (`termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`) by D-054, edge became the `edge` aspect (+ private `_edge/edge-ingress.nix`), and DJ became `dj` (+ private `_dj/`). Stage 8 (D-056) then moved those owners from `modules/flake/` into their domain directories (`modules/music/`, `modules/admin/`, `modules/identity/`, `modules/edge/`). No compatibility wrapper or underscore-renamed replacement root exists.

**Service leaves (beside the owning aspect):**

- Purpose: Leaf service implementation modules — individual workloads with enable flags and secrets
- Contains: the former service root no longer exists. Every leaf is now a discovered contributor beside its domain: the cache server `modules/cache/niks3-cache.nix`, `modules/flake/{tailscale,ai-gateway,paperless,karakeep,phoenix,omniroute}.nix`, `modules/notifications/{notify,push-server}.nix`, `modules/database/postgres.nix`, `modules/edge/edge-ingress-runtime.nix`, and the admin workloads under `modules/admin/`. Music services (Syncthing, Navidrome, Beets, slskd, Tagr, AudioMuse, ingest, storage) live under `modules/music/` with the Beets asset directory `beets/files/` and the private runner helper `_beets/runners.nix`
- `modules/database/postgres.nix` is both the `postgres` aspect and the mechanism for the fleet's PostgreSQL substrate: it renders provisioning (databases, roles, `pg_hba`, credential application, extension composition, setup SQL, backup export) from `services.postgres.instances.<name>` and `services.postgres.consumers.<name>` and names no consumer; port and data directory are declared per host by the enabling record, consumers register from their own modules through the declaration-only contract `modules/database/postgres/_consumer.nix`, and a co-located consumer resolves the local cluster through `services.postgres.localEndpoint` (D-058)
- Key files: `modules/flake/tailscale.nix`, `modules/music/syncthing.nix`, `modules/music/navidrome.nix`, `modules/music/beets.nix`, `modules/music/_beets/runners.nix`, `modules/music/beets/files/beets-config.yaml`, `modules/music/ingest.nix`, `modules/music/storage.nix`, `modules/music/files/ffmpeg-preprocess.sh`, `modules/music/slskd.nix`, `modules/music/tagr.nix`, `modules/music/audiomuse.nix`, `modules/notifications/push-server.nix`, `modules/flake/ai-gateway.nix`, `modules/flake/paperless/core.nix`, `modules/flake/paperless/gpt.nix`, `modules/database/postgres.nix`, `modules/admin/cockpit.nix`
- **ai-gateway.nix** (the bifrost gateway): AI gateway service with OpenRouter and CrofAI provider support

**`pkgs/`:**

- Purpose: Custom Nix packages/derivations
- Contains: `default.nix` (package set aggregator), `_sources/` (nvfetcher output: `generated.nix`, `generated.json`), `notification-daemon/` (Python FastAPI daemon source, `pyproject.toml`, `default.nix`), `notify/` (CLI wrapper that POSTs to the daemon)
- Key files: `pkgs/default.nix`, `pkgs/_sources/generated.nix`, `pkgs/notification-daemon/default.nix`, `pkgs/notify/default.nix`

**`modules/providers/` (deleted in dendritic Stage 7, D-053):**

- Purpose: former evaluator-class root for provider-specific defaults
- Contains: nothing; the OCI provider body now sits inline in the discovered `oci` aspect (`modules/oci/oci.nix`) selected on `oci-melb-1`.

**Private implementation leaves (`_` helpers beside their owner):**

- Purpose: Concern-owned private files reached only through their aspect owner's imports; underscore semantics keep them out of import-tree discovery and they publish no `flake.modules.nixos.<name>` (D-051). Since the post-Stage-8 services-tree conversion they are no longer a directory form for module bodies: a second contributor publishes the same aspect name from a sibling file, and `_` is left for a value-imported helper, an asset directory, or host-private data (`modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, `modules/admin/homepage/_data.nix`, `modules/hosts/<host>/_disko-*.nix`)
- Contains: `modules/flake/shell/p10k.zsh` (prompt theme beside `modules/flake/shell.nix`), `modules/music/_beets/runners.nix` (Beets runner units beside `modules/music/beets.nix`), `modules/admin/homepage/_data.nix` (dashboard data value-imported by `modules/admin/homepage.nix`)
- Key files: `modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, `modules/admin/homepage/_data.nix`

**`policy/`:**

- Purpose: Canonical source of truth for fleet-wide non-secret defaults and web service definitions
- Contains: `globals.nix` (S3, Nix substituters, AI gateway, music/admin/defaults), `web-services.nix` (SSOT endpoint routing), `oci-images.nix` (Renovate-managed OCI image refs, tag+digest), `identity.json` (Kanidm OIDC client config), `bifrost-config.json` (AI gateway model config)
- Key files: `policy/globals.nix`, `policy/web-services.nix`, `policy/oci-images.nix`

**`lib/`:**

- Purpose: Reusable Nix library functions
- Contains: `secrets.nix` (secret option helpers), `deploy/default.nix` (deploy-rs node wiring), `deploy/hosts.nix` (physical deploy topology SSOT — node facts, `edgeHost`, `deployOrder`; referenced by canonical host ID and validated in `modules/flake/deploy.nix`), `policy.nix` (web policy resolution)
- Key files: `lib/secrets.nix`, `lib/deploy/default.nix`, `lib/deploy/hosts.nix`, `lib/policy.nix`

**`secrets/`:**

- Purpose: SOPS-encrypted values organized by blast radius
- Contains: `common.yaml`, `applications/<name>.yaml`, `services/<name>.yaml`, `hosts/<host>/system.yaml`, `hosts/<host>/oidc.yaml`, `identity/`, `opentofu/`, `.templates/`
- Key files: `.sops.yaml` (recipient policy), `secrets/common.yaml` (fleet-shared), `secrets/hosts/oci-melb-1/system.yaml`

**`scripts/`:**

- Purpose: Operator-facing shell utilities
- Contains: `resolve-host-config.sh`, `export-web-services-policy.sh`, `render-opentofu-cloudflare-runtime.sh`, `edge-ingress-operational-checks.sh`, `gha-oidc.biscuit`
- Key files: `scripts/export-web-services-policy.sh`, `scripts/resolve-host-config.sh`

**`tests/`:**

- Purpose: Contract validation scripts
- Contains: `check-secret-scope.sh`, `check-web-services-policy.sh`, phase contract tests (`phase-*.sh`), `fixtures/` (test fixture data including `secret-scope.nix` — canonical scope definitions for secret scope validation)
- Key files: `tests/check-secret-scope.sh`, `tests/check-web-services-policy.sh`

**`opentofu/`:**

- Purpose: Infrastructure-as-code for Cloudflare DNS and Access
- Contains: `cloudflare/` directory with OpenTofu config and backend
- Key files: `opentofu/cloudflare/`

## Key File Locations

**Entry Points:** `flake.nix`: Minimal flake-parts entrypoint; outputs — `nixosConfigurations`, `devShells`, `packages`, `deploy`, `checks`, `bootstrap` — are composed by the flake-parts modules under `modules/flake/`. Local evaluation uses the Git-tree form `.#`; `path:` appears only in tests whose copies have no Git repository (D-057)

**Published Provenance:** `modules/flake/provenance.nix`: publishes the evaluated source to `/etc/nixos-source`. With the `.#` reference form that copy is the tracked configuration set rather than the working directory, and `system.configurationRevision` is populated from `self.rev`/`self.dirtyRev`. `tests/check-flake-source-tracking.sh` guards the Git index the form depends on

**Configuration:** `.sops.yaml`: SOPS recipient policy with path-scoped secret rules

**Host Definitions:** `modules/hosts/oci-melb-1/default.nix` (Oracle Cloud aarch64), `modules/hosts/la-admin-1/default.nix` (LA x86_64 admin/edge/identity), `modules/hosts/home-forge/default.nix` (home workloads): discovered contributors declaring one typed `nixos.hosts.<id>` record each; the schema and generic materializer live in `modules/flake/host-registry.nix`

**Deploy Metadata:** `lib/deploy/hosts.nix`: Hostname, SSH user, system architecture, remote-build flag per host; `edgeHost` and `deployOrder` are the only physical deployment facts (serial order `la-admin-1` → `oci-melb-1`). Every referenced name must be a declared canonical host ID — `modules/flake/deploy.nix` fails closed with `deploy: unknown host reference …` otherwise

**Core Logic:** `modules/`: domain aspect contributors with their sibling contributors (`modules/identity/`, `modules/notifications/`, `modules/cache/`, `modules/backups/`, `modules/music/`, `modules/admin/`, `modules/edge/`, `modules/oci/`, `modules/database/`), fleet contracts (`modules/fleet/`), canonical host contributors (`modules/hosts/`), and flake materialization plus the fleet baseline (`modules/flake/`)

**Internal Contracts:** `modules/fleet/internal-contracts.nix`: the two typed cross-host transport contracts (shared PostgreSQL, private Niks3 write API) with provider ID, port, and resolved private endpoints; validated by `flake.internalContracts` and exercised by `tests/check-internal-contracts.sh`

**Policy SSOT:** `policy/web-services.nix`: All public web service endpoint definitions with origin, exposure mode, and Cloudflare config (plain data; host-backed origins are validated against canonical host records in `modules/flake/web-policy.nix`). `policy/globals.nix` `tailnet.suffix` is the single tailnet suffix authority

**Secrets Policy:** `.sops.yaml`: Path-scoped age recipient rules for encrypting/decrypting all secret files

**Task Runner:** `justfile`: All operator commands — bootstrap, deploy, SSH, logs, backups, secrets, checks, OpenTofu. Modular structure delegates domains to `.just/*.just`, `opentofu/justfile`, and `secrets/justfile`.

**Bootstrap Script:** `deploy.sh`: nixos-anywhere bootstrap driver with host config resolution and age recipient derivation

**Notification Daemon:** `pkgs/notification-daemon/notification_api/main.py`: FastAPI app with `/health`, `/notify`, `/debug/test-notify` endpoints

**Notify CLI:** `pkgs/notify/default.nix`: Python stdin-pipe wrapper that POSTs to the notification daemon

## Naming Conventions

**Files:** `kebab-case.nix` for Nix files: `disko-root.nix`, `edge-ingress.nix`, `kanidm-host-auth.nix`

**Directories:** `kebab-case` for module directories: `notification-daemon/`, `edge-ingress/`, `host-recovery/`

**Flake attributes:** `camelCase` for flake outputs: `nixosConfigurations`, `devShells`

**Nix options:** `dot.separated.namespaces`: `applications.music.enable`, `services.bifrost-gateway.enable`, `services.admin.kanidm.enable`

- `applications.<name>` for composition root stacks
- `services.<domain>.<name>` for grouped services
- `services.<name>` for top-level standalone services
- `fleet.<name>` for fleet-wide module options
- `nixos.hosts.<id>` for the canonical host records (flake-parts level, not a NixOS option namespace)
- `repo.internal.<contract>` for resolved internal transport contract endpoints; `repo.web.*` for resolved web policy

**Host names:** `kebab-case`: `oci-melb-1`, `la-admin-1`

**Secret file names:** `kebab-case`: `system.yaml`, `oidc.yaml`, `edge-ingress.yaml`, `bifrost-gateway.yaml`

- Host secrets: `secrets/hosts/<host>/system.yaml`
- Host OIDC secrets: `secrets/hosts/<host>/oidc.yaml`
- Application secrets: `secrets/applications/<name>.yaml`
- Service secrets: `secrets/services/<name>.yaml`

## Where to Add New Code

**New host:** `modules/hosts/<host-name>/default.nix` — a discovered contributor declaring `nixos.hosts.<host-name>` with `system`, `tailscale.{hostname,tailnetSuffix}` (suffix read from `policy/globals.nix`), and `composition.extraModules` (input-provided NixOS modules), `composition.aspects` (the support quartet `provenance`/`oci-images`/`fleet-packages`/`web-policy`, the foundation aspects `base`/`shell`/`networking`/`tailscale`/`notify`, the operational aspects `state-backups`/`cache-publisher`/`builder-access`/`observability-agent`, `internal-contracts`, any host-facing application aspects such as `dj`/`music`/`kanidm-host-auth`, and the host's placement aspects as applicable), and `composition.fragments = [ ./_nixos.nix ]`. Keep every host-private fragment underscore-prefixed and never import a workload implementation. Add the physical entry to `lib/deploy/hosts.nix` (its host IDs are validated against the record keys), add host-scoped `.sops.yaml` rules, and add the host's `bootstrap` metadata to the record when it is reimaged via `nixos-anywhere`.

**New application/product aspect:** `modules/<domain>/<aspect>.nix` publishing `flake.modules.nixos.<aspect>` — composition with the app's `enable` flag supplied by selection, shared paths, and sub-service wiring; put a helper or a second contributor beside the owner under `modules/<domain>/` (a sibling file publishing the same aspect name, or a `_`-prefixed value-imported helper). Use `secretFiles.host` for secret passthrough. Then select the aspect in each deploying host's `nixos.hosts.<id>` record and assert the placement in `tests/check-dendritic-scaffold-contract.sh`. Put a contributor in `modules/flake/` only when it is a flake materialization, fleet-baseline, or infrastructure support concern (D-056).

**New edge ingress host:** select `aspects.edge` in the host record — role-based (edge/origin/none) with the implementation at `modules/edge/edge-ingress-application.nix` over `modules/edge/edge-ingress-runtime.nix`; the host keeps only `role` and the application-scoped secret binding.

**New paperless stack deployment:** `modules/hosts/<host>/default.nix` — set `services.paperless.enable = true` and bind `services.paperless.secretFiles.host` and `.oidc` to host-scoped secret files. Optionally enable paperless-gpt via `services.paperless.paperless-gpt = { docling.enable = true; instances.llm.enable = true; instances.docling.enable = true; }` for AI document enhancement with docling-serve sidecar. Ensure the target host selects the `postgres` aspect (or another instance aspect) so the database role can be provisioned, and that paperless registers its database in that instance's consumer registry.

**New service:** `modules/<domain>/<name>.nix` — leaf module with `enable` flag, `secretFiles.*` contracts, and `sops.secrets` ownership, publishing its own `flake.modules.nixos.<name>` aspect or joining an existing one. Use `lib/secrets.nix` helpers.

**New foundation/operational aspect:** add a concern-owned contributor under `modules/flake/` (e.g. `base/foundation.nix`) or a domain directory (`modules/backups/state-backups.nix`) that publishes a `flake.modules.nixos.<name>` record and imports the contributor beside it (Stages 7 and the admin decoupling added the `oci`/`edge`/`cockpit`/`push-server`/`identity-provider`/`termix`/`vaultwarden`/`homepage`/`gatus`/`beszel`/`webhook`/`paperless`/`postgres`/`ai-gateway`/`karakeep`/`niks3-cache`/`phoenix`/`omniroute` placement aspects this way). Several contributors may define the same aspect name when a capability is composed from independent source files (the `cache-publisher` pattern); each contributor nests its own body inline with no wrapper or cross-contributor import. A file whose whole body is a contract or value importable by consumers is underscore-prefixed instead (`modules/identity/_oidc.nix`, `modules/database/postgres/_consumer.nix`, `modules/backups/state-backups/_consumer.nix`), because a non-underscore file under `modules/` is discovered and evaluated as a flake-parts module. Host registry records select the aspect explicitly; selection is enablement. Aspect relationships follow the three composition modes (intrinsic composition, policy co-selection, optional integration); direct public-aspect imports require intrinsic-composition justification. No transitional root remains: every contributor is discovered, so no private implementation leaf is reachable only through a transition path.

**New provider:** add a discovered `modules/<provider>/<provider>.nix` aspect publishing `flake.modules.nixos.<provider>` with its private implementation under `modules/<provider>/_<provider>/` (the `oci` domain is the existing example), then select it in that provider's host record. Do not recreate `modules/providers/`.

**New storage layout:** place the underscore-private layout beside its host (e.g., `modules/hosts/oci-melb-1/_disko-single-disk-split.nix`, `modules/hosts/home-forge/_disko-two-disk.nix`); there is no shared storage menu. Add sizing options following the pattern in `_disko-single-disk-split.nix`.

**New web service route:** `policy/web-services.nix` — add service entry under the relevant host's `services` attribute with subdomain, origin, exposure mode, and Cloudflare config.

**New secret file:** `secrets/<scope>/<name>.yaml` — add corresponding path-scoped rule in `.sops.yaml`. Encrypt with `sops`.

**New script:** `scripts/<name>.sh` — operator-facing utility. Add `just` recipe in `justfile` or a `.just/<domain>.just` module.

**New CI workflow:** `.github/workflows/<name>.yml` — add job with nixbuild setup and Tailscale connectivity.

**New GitHub Action:** `.github/actions/<name>/action.yml` — reusable composite action. Reference the `setup-nixbuild` action for the nixbuild SSH key pattern.

**New test:** `tests/<name>.sh` — contract validation script with clear pass/fail output. Add to `just checks all` if it should run in CI. Add fixture data to `tests/fixtures/` if needed.

**New custom package:** `pkgs/<name>/default.nix` — standard `callPackage`-compatible derivation with source alongside it. Register in `pkgs/default.nix` (the package set aggregator). Add entry in `flake.nix` packages output via `pkgs.callPackage ./pkgs/<name> { }`.

**New non-flake upstream source:** Add a `[[package]]` entry to `nvfetcher.toml` with the source name, fetcher, and version query. Run `just deps refresh` to regenerate `pkgs/_sources/generated.nix`. Import generated metadata from `pkgs/_sources/generated.nix` in the consuming derivation. (Do not hand-edit version/hash pairs.)

**New OCI image reference:** Add the image in `image:tag@sha256:digest` form to `policy/oci-images.nix`. The image is available to service modules via `config.repo.ociImages.<name>` (typed policy aspect from the `oci-images` flake module; no `specialArgs`). Renovate proposes digest and tag updates on its scheduled runs.

**New notification daemon feature:** `pkgs/notification-daemon/notification_api/main.py` — add new handler or endpoint in the FastAPI app. Update `pkgs/notification-daemon/pyproject.toml` for new dependencies.

**New justfile module:** `.just/<domain>.just` — create domain-specific recipe file. Import in main `justfile` with `mod <name> '.just/<name>.just'`.

**Local dev workflow:**

1. Create a local config: `just dev setup` (decrypts to `/tmp/notification-daemon.json`)
2. Enter the devShell: `nix develop` (daemon auto-starts if config exists)
3. Use `notify` CLI directly: `echo "test" | notify info "test" test system`
4. Exit the devShell — daemon auto-stops via trap
