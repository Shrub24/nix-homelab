# Decisions

This document captures architecture and planning decisions agreed so far. It is intentionally high signal and should be updated as decisions change.

## Decision Register

## D-001: Repository mission changed from dev VPS to fleet infrastructure

Status: Accepted

Decision:

- this repository now targets modular multi-host NixOS infrastructure
- prior single-purpose `dev-vps` framing is legacy and scheduled for cleanup

Rationale:

- current goals are infrastructure reproducibility and service deployment across hosts
- old direction mixed personal environment and app-specific concerns that are now out of focus

## D-002: First host identity

Status: Accepted

Decision:

- first host is `oci-melb-1`

Rationale:

- establishes a concrete anchor for initial architecture and secrets policy

## D-003: Initial service scope

Status: Accepted

Decision:

- initial active services are `navidrome`, `syncthing`, and `tailscale`
- `k3s`, `keda`, and cloud-worker details are explicitly deferred

Rationale:

- native service baseline provides faster validation with lower complexity

## D-004: Secrets model uses blast-radius scoping

Status: Superseded by D-019

Decision:

- maintain split between:
  - `secrets/common.yaml`
  - `hosts/<hostname>/secrets.yaml`
- define recipients in `.sops.yaml` with explicit path-scoped rules

Rationale:

- minimizes unnecessary decryption access across hosts
- aligns with future fleet growth and service mobility decisions

## D-005: Tailscale enrollment tokens are host-scoped

Status: Accepted

Decision:

- prefer per-host enrollment secrets over one reusable shared key

Rationale:

- better auditability and smaller blast radius on token exposure

## D-006: Syncthing operating mode starts bidirectional with safety controls

Status: Accepted

Decision:

- start with bidirectional sync
- include versioning/conflict protections in configuration posture

Rationale:

- matches current peer-style workflow
- retains flexibility before authority centralization with later `rclone` direction

## D-007: Storage model starts with one persistent mount

Status: Accepted

Decision:

- use one data mount for now and organize service paths under it
- avoid duplicate datasets/staging initially

Rationale:

- simplest operational model
- avoids unnecessary storage overhead during early stages

## D-008: Media path is direct for now

Status: Accepted

Decision:

- Navidrome reads directly from Syncthing-managed path initially

Rationale:

- reduces complexity and storage duplication
- delayed ingest/pipeline split can be introduced when processing needs are concrete

## D-032: `oci-melb-1` uses a recovered single-disk runtime layout with dedicated `/nix`

Status: Accepted

Decision:

- `oci-melb-1` now runs with `/`, `/srv/data`, `/nix`, and `/srv/media` as labeled filesystems on the OCI boot volume
- `modules/storage/disko-single-disk.nix` is the canonical declarative layout for that host shape
- `/nix` remains a dedicated filesystem rather than a bind-mount into another service-data path

Rationale:

- the previous root-only layout was too small for real host operation and recovery
- the validated rescue flow proved the single-disk labeled-filesystem shape is workable and recoverable on OCI

## D-033: Shared music/media roots have one declarative directory owner

Status: Accepted

Decision:

- `modules/applications/music.nix` owns creation of shared media roots such as `/srv/media/inbox`, `/srv/media/library`, and `/srv/media/quarantine`
- leaf modules like Syncthing and Beets may add marker files, ACLs, or service-specific children, but do not redefine the same shared directory ownership contract

Rationale:

- avoids duplicate tmpfiles warnings and ownership drift
- keeps cross-service storage policy in the application composition layer where shared media semantics are already defined

## D-009: Deployment tooling sequence

Status: Accepted

Decision:

- bootstrap with `nixos-anywhere`
- adopt fleet deployment tooling after first host stabilization

Rationale:

- keeps first-host bring-up simpler
- avoids early operational overhead while preserving future compatibility

## D-010: Secrets bootstrap default is two-step

Status: Accepted

Decision:

- default to two-step bootstrap for secrets on new host bring-up

Rationale:

- lower risk in early bootstrap
- less pre-install handling of sensitive identity material

## D-011: Pre-generated host identity is allowed but treated as advanced

Status: Accepted (conditional)

Decision:

- pre-generated host key material can be used when first-boot secret decryption is required
- this is not the baseline path

Rationale:

- valid approach with deterministic first-boot identity
- higher operational sharpness and identity-coupling complexity than two-step bootstrap

## D-012: Cleanup posture

Status: Accepted

Decision:

- perform aggressive cleanup of legacy `dev-vps` direction on migration branch

Rationale:

- reduces confusion and maintenance burden
- reinforces clear repository mission

## D-013: Access exposure policy

Status: Accepted

Decision:

- keep service origins private-first and Tailscale-first by default
- allow explicit public edge exposure only through the designated Cloudflare + Caddy edge bastion
- use Cloudflare Access-gated policy for approved admin web routes at the edge
- keep `direct` transport limited to explicit edge-local localhost exceptions

Rationale:

- preserves a narrow public surface while retaining encrypted/private-origin upstream posture
- keeps admin access policy explicit and consistent as ingress complexity grows

## D-014: Full repository cutover now (no long-lived bridge)

Status: Accepted

Decision:

- use `nixosConfigurations.oci-melb-1` as the active flake output now
- keep host identity in `hosts/oci-melb-1/default.nix`
- remove legacy `nixosConfigurations.dev-vps` and associated personal-tooling outputs from active wiring

Rationale:

- avoids dual-mission drift and broken references in active workflows
- keeps operator and CI surfaces aligned to a single canonical host target

## D-015: Reusable module boundaries are explicit in active paths

Status: Accepted

Decision:

- baseline shared policy lives in the `base` foundation aspect (`modules/flake/_aspects/base.nix`; formerly `modules/core/base.nix`)
- common-baseline composition happens by explicit foundation-aspect selection in the typed host registry (concern-owned `modules/flake/*.nix` contributors + `modules/flake/registry.nix`; formerly the `modules/profiles/base-server.nix` wrapper)
- service boundary for private access starts in `modules/services/tailscale.nix` (now the `tailscale` foundation aspect's service leaf) (file now `modules/flake/tailscale.nix`, post-Stage-8 services-tree conversion)

Rationale:

- separates host identity from reusable logic for future host growth
- keeps provider-specific concerns out of reusable modules

## D-016: Documentation authority and derivation contract

Status: Accepted

Decision:

- `docs/` is canonical for architecture, decisions, and migration direction
- `README.md` remains orientation-only with links to canonical docs
- `CLAUDE.md` is a derived mirror and must not conflict with canonical `docs/`

Rationale:

- prevents conflicting migration narratives during aggressive cutover
- keeps implementation and operator guidance synchronized

## D-017: Add a narrow applications composition layer for current host systems

Status: Accepted

Decision:

- add `modules/applications/music.nix` to compose Syncthing, Navidrome, and slskd for `oci-melb-1`
- add `modules/applications/admin/default.nix` to compose private admin access through Tailscale plus Termix
- keep low-level implementation in `modules/services/*.nix` and avoid broad repository reorganization (path now `modules/<domain>/<name>.nix`; the service root was converted post-Stage-8)

Rationale:

- introduces an explicit logical application boundary without disrupting existing host behavior
- preserves service-level reuse while making host composition easier to reason about

## D-018: Termix runs as a Tailscale-only admin application on la-admin-1

Status: Accepted

Decision:

- implement Termix with a dedicated low-level module `modules/services/termix.nix` using Podman OCI containers (`termix` + `guacd`) (file now `modules/admin/termix.nix`)
- persist Termix state under `/srv/data/termix`
- expose Termix only through declared edge route policy (Cloudflare Access-gated at public edge, private-origin transport preference)
- Termix is hosted on `la-admin-1` (LA x86_64); `oci-melb-1` does not run Termix

Rationale:

- adds controlled remote admin capability while preserving private-origin boundaries and explicit edge policy
- keeps runtime/container specifics isolated from host composition and canonical docs

Historical note:

- Termix was originally hosted on the decommissioned DigitalOcean admin host and moved to `la-admin-1` with the LA migration.

## D-030: Homepage authenticated widgets use host-scoped caller-owned machine-auth env wiring

Status: Accepted

Decision:

- Homepage authenticated widgets consume credentials via a dedicated host-scoped SOPS template environment file (`homepage-auth.env`)
- credential ownership stays with Homepage caller wiring (`modules/services/admin/homepage/**`) instead of route policy metadata (path now `modules/admin/homepage/**`)
- keep explicit auth exceptions minimal:
  - Caddy widget remains local no-auth (loopback admin API)
  - Gatus widget remains URL-only/read-only
  - Quantum widget auth remains out of scope in this wave
- Beszel Homepage integration uses a dedicated read-only account, with visibility only to explicitly shared systems

Rationale:

- preserves separation of concerns between route exposure policy and caller integration auth
- keeps secret blast radius host-scoped and avoids new shared secrets
- provides practical day-1 machine-auth coverage for Homepage without forcing unnecessary credentials

Operational notes (one-time Beszel bootstrap):

1. Sign in to Beszel at `https://beszel-admin.shrublab.xyz` as admin.
2. Create a dedicated Homepage read-only user (non-admin) with a strong generated password.
3. Share only required systems with that user (explicit system list; no global sharing).
4. Store the username/password in `secrets/hosts/la-admin-1/system.yaml` under:
   - `homepage/beszel/username`
   - `homepage/beszel/password`
5. Re-encrypt with `sops` and deploy so `homepage-auth.env` is regenerated.

## D-019: Music app owns generic ingest boundary and slskd is confined to service subtree

Status: Accepted

Decision:

- `modules/applications/music.nix` owns `/srv/media/inbox` as a generic ingest boundary through `music-ingest`
- `slskd` is confined to `/srv/media/inbox/slskd` for completed downloads and `/srv/media/slskd/incomplete` for partial data
- Syncthing and Navidrome remain anchored on `/srv/data/media` as the authoritative library path

Rationale:

- keeps cross-service ingest ownership at the application layer instead of expanding core user/module scope
- allows future ingest producers to share one boundary while preventing slskd path sprawl
- preserves the direct authoritative media flow without reintroducing duplicate staging ownership

## D-020: OCI media authority moves to dedicated `/srv/media` mount

Status: Accepted

Decision:

- `hosts/oci-melb-1/bootstrap-config.nix` declares a dedicated `mediaDisk = "/dev/sdb"`
- OCI provider defaults bind `bootstrapConfig.mediaDisk` into `disko.devices.disk.media.device`
- `modules/storage/disko-root.nix` mounts the media filesystem at `/srv/media`
- Syncthing, Navidrome, and slskd shared-library references move from `/srv/data/media` to `/srv/media`
- `/srv/data` remains responsible for service-state paths (`/srv/data/syncthing/config`, `/srv/data/navidrome`)
- `/srv/media` now owns the media library plus ingest/download paths (`/srv/media`, `/srv/media/inbox`, `/srv/media/slskd`)
- introduce `music-library` group so `/srv/media` is writable by Syncthing and the `dev` operator account without changing service ownership to a human user

Rationale:

- separates authoritative media storage from service-state and ingest data to reduce path-coupling drift
- keeps the existing app-owned ingest boundary and state layout stable while introducing explicit media disk contract checks
- aligns phase-03/phase-04 contracts and canonical docs with the storage split so regressions fail quickly

## D-021: Beets remains inbox-only singleton worker with no promotion behavior

Status: Superseded by D-022

Decision:

- add an inbox-only Beets worker for `oci-melb-1` that runs singleton imports against `/srv/media/inbox/slskd`
- trigger routine runs automatically through `systemd.path` file events
- keep all Beets runtime state and reports under `/srv/data/beets`
- enforce no promotion behavior: no copy/move/link/hardlink flow out of inbox

Rationale:

- satisfies MEDI-02, MEDI-03, and MEDI-04 without changing established `/srv/media` authority
- keeps ingestion automation conservative so unmatched/weak candidates remain in place for manual follow-up
- avoids accidental scope creep into a future authority/promotion pipeline before that phase is explicitly planned

## D-022: Beets runs all-inbox native auto-promotion into /srv/media/library

Status: Accepted

Decision:

- evolve the Beets worker to scan `/srv/media/inbox` broadly using native album import semantics
- auto-promote successful files into `/srv/media/library/<top-level>/<release>/<original filename>`
- keep filename preservation as a strict contract during move/promotion
- keep Beets runtime state and built-in import logs under `/srv/data/beets`
- preserve broad playback visibility by keeping Navidrome rooted on `/srv/media`

Rationale:

- advances MEDI-01 with a native systemd and Beets-based promotion path (`singletons: no`, `group_albums: yes`) without introducing app-based review complexity
- keeps hard failures visible and playable from inbox while successful files become canonical library entries
- maintains the `/srv/media` authority model and service-state/report separation under `/srv/data`

## D-023: Beets worker is transfer-safe, serialized, and performs post-run demotion sweep

Status: Accepted

Decision:

- trigger Beets worker from inbox modification events under `/srv/media/inbox`
- require transfer-lock behavior: if any `.tmp` file exists under inbox, worker exits without invoking Beets
- apply a fixed settle/debounce delay after transfer lock clears before import starts
- rely on native systemd single-instance service behavior so overlapping path/timer triggers do not create concurrent workers
- keep Beets headless album import execution (`-q`, `singletons: no`, `group_albums: yes`) and preserve original filenames via native Beets path templating
- after Beets completes, sweep any remaining inbox audio into `/srv/media/quarantine/untagged` to prevent recursive loops and restore zero-state inbox for eligible files

Rationale:

- aligns implementation with operational acceptance criteria for robust mobile-first ingest automation
- avoids partial-transfer races and repeated loop triggers caused by residual inbox files
- preserves playlist safety by keeping downloaded basenames unchanged during both promotion and demotion

## D-024: Quarantine uses music-ingest ownership with explicit media read-only ACLs and dedicated approved promotion config

Status: Accepted

Decision:

- Syncthing sync scope includes both `/srv/media/library` and `/srv/media/quarantine`
- quarantine paths (`/srv/media/quarantine`, `untagged`, `approved`) are owned by `music-ingest`
- apply ACLs so `media` has explicit read-only (`r-x`/`r-X`) access to quarantine paths while `syncthing` retains explicit write access for sync operations
- codify Syncthing marker files (`.stfolder`) at `/srv/media/library/.stfolder` and `/srv/media/quarantine/.stfolder` with `syncthing:syncthing` ownership via tmpfiles
- add a secondary Beets runner that targets `/srv/media/quarantine/approved` for manual re-attempt promotions with a dedicated approved-flow config
- keep Navidrome rooted on `/srv/media` so quarantine visibility remains explicit alongside promoted library content
- remove Navidrome playlist injection hacks and rely on media-root scanning for visibility

Rationale:

- preserves a permission-safe, reviewable quarantine flow without introducing public exposure or ad-hoc scripts
- keeps approved reprocessing native to systemd + Beets while avoiding recursive demotion behavior in the approved lane
- aligns quarantine ownership with ingest boundaries while keeping media-library review access read-only and Syncthing write-capable where needed

## D-025: Second host `do-admin-1` is added as a DigitalOcean x86_64 admin node

Status: Accepted

Decision:

- add `nixosConfigurations.do-admin-1` with `x86_64-linux`
- compose the host in `hosts/do-admin-1/default.nix` with shared `dev` user model
- isolate provider defaults in `modules/providers/digitalocean/default.nix`
- use `modules/storage/disko-single-disk.nix` for single-disk DO layout

Rationale:

- validates multi-provider, mixed-architecture fleet shape without perturbing `oci-melb-1`
- keeps provider and storage concerns modular instead of coupling to OCI bootstrap metadata

## D-026: Host age recipient bootstrap defaults to live SSH host key derivation

Status: Accepted

Decision:

- default bootstrap workflow derives the host age recipient only after the live SSH ed25519 host key is compared with the provider-console fingerprint (`host-generic` pattern)
- keep advanced injected-key workflow available for cases where live retrieval is not possible
- enforce host-scoped `.sops.yaml` rules per host (`hosts/<host>/secrets.yaml`)

Rationale:

- preserves the host-key identity guarantee while avoiding a separately managed age private key
- keeps a deterministic fallback for restricted network/bootstrap scenarios

## D-027: deploy-rs is the primary deployment workflow for both active hosts

Status: Accepted

Decision:

- add `deploy-rs` as a flake input and publish `deploy.nodes` for `oci-melb-1` and `do-admin-1`
- define host deploy metadata in `lib/deploy/hosts.nix` and reusable wiring in `lib/deploy/default.nix`
- set each node to `sshUser = "dev"`, host hostname, and `profiles.system.path` from the matching `nixosConfigurations.<host>`
- wire `deploy-rs` deployment checks into `flake checks` for both `aarch64-linux` and `x86_64-linux`
- make `just deploy`, `just _activate`, and `just checks all` the primary operator workflow

Rationale:

- keeps deployment behavior host-centric and extensible as more nodes are added
- removes ad-hoc per-command deployment drift while preserving bootstrap/secrets flows
- ensures deployment schema validation is part of normal flake checks

## D-028: nixpkgs baseline is unstable-default with exception-only fallback

Status: Accepted

Decision:

- set the primary flake `nixpkgs` input to `github:NixOS/nixpkgs/nixos-unstable`
- remove pre-provisioned `nixpkgs-unstable` split wiring from active code paths
- allow additional stable fallback inputs only as targeted, explicitly documented exceptions
- keep host `system.stateVersion` unchanged by this policy shift

Rationale:

- reduces split-package-set complexity and exception churn in active development
- keeps package provenance consistent across hosts/modules while preserving explicit rollback via future documented exceptions
- avoids incorrectly coupling package baseline changes to state-version migration semantics

## D-029: SoulSync is primary ingest; beets is fallback rescue

Status: Accepted

Decision:

- make SoulSync the primary ingest/promotion control-plane service for `oci-melb-1`
- retain canonical media paths:
  - download inbox: `/srv/media/inbox/slskd`
  - canonical library: `/srv/media/library`
  - unresolved lane: `/srv/media/quarantine/untagged`
  - approved rescue/staging lane: `/srv/media/quarantine/approved`
- keep beets installed as operator-controlled fallback rescue tooling; beets no longer owns default automated ingest
- scope Navidrome to `library + quarantine` and exclude inbox from playback surface
- publish SoulSync as an approved public service via canonical edge policy (`tailscale-upstream`, Cloudflare Access, AOP)
- keep day-1 SoulSync public posture control-plane-first with best-effort playback suppression/hiding and documented residual behavior if upstream player controls cannot be fully disabled without forking
- keep optional provider integrations optional-by-secret so missing provider credentials do not break host convergence

Rationale:

- aligns ingest behavior with track-first DJ workflows and mixed singles/partial-release handling
- preserves existing `/srv/media` contracts and review lanes while replacing beets-first ingestion ownership
- keeps public exposure aligned with existing edge security posture instead of ad-hoc origin exposure
- avoids high-risk upstream patching while still constraining day-1 public UI behavior

Supersedes/updates:

- supersedes D-022 default beets auto-promotion ownership
- supersedes D-023 as the default ingest automation model (beets path/timer model retained only for fallback tooling)
- supersedes D-024 Navidrome media-root visibility assumption (`/srv/media` broad root) with explicit `library + quarantine` scope

## D-030: Feature-oriented host topology with topology-aligned secret scopes

Status: Accepted

Decision:

- adopt a feature-oriented architecture where:
  - application modules (`modules/applications/<name>/default.nix`) are canonical composition roots for multi-service stacks
  - leaf service modules (`modules/services/**/*.nix`) own their own enablement, secret contracts, and runtime wiring (files now live beside their owning aspect, e.g. `modules/cache/niks3-cache.nix`)
  - host modules (`hosts/<host>/default.nix`) are thin assembly layers declaring identity, facts, feature enables, and narrow overrides
- single services that do not participate in multi-service composition remain standalone leaf services (applications are not wrappers only for taxonomy)
- every application entrypoint exposes a canonical `applications.<name>.enable` option; standalone services expose `services.<domain>.<name>.enable`
- replace the old `common + host-monolith` secret model with a topology-aligned bucket model:
  - `secrets/applications/<name>.yaml` for application-scoped secrets
  - `secrets/services/<name>.yaml` for standalone service-scoped secrets
  - `secrets/hosts/<host>/system.yaml` for host-only bootstrap/system secrets
  - `secrets/hosts/<host>/oidc.yaml` for cross-host OIDC identity-handshake secrets
- leaf service modules own their own `secretFiles.*` / `secretKeys.*` contract options, `sops.secrets` registrations, and `sops.templates` assembly
- application modules pass through `secretFiles.*` values to sub-services but do not own sub-service secret internals
- hosts only set feature-enable flags and explicit secret-file-path bindings (e.g. `applications.music.secretFiles.host`)
- normal secret scope derives from normalized host feature enablement rather than a separately maintained consumer inventory; only explicit exception readers (e.g. cross-host OIDC) are declared separately
- keep plain explicit `flake.nix` architecture (no `flake-parts` or Dendritic Nix adoption in this change)
- perform a clean cutover without backward-compatibility aliases or migration shims
- use `lib/secrets.nix` as a light reusable helper library for common secret-contract option declarations
- keep `.sops.yaml` as recipient-policy source of truth, with secret-scope validation implemented as repo-owned checks under `tests/`

Rationale:

- hosts previously owned too much service wiring, secret registrations, and template assembly, making host files heavyweight and feature ownership ambiguous
- monolithic host-scoped secret buckets made feature-scope reasoning harder and kept secret ownership host-centric even when runtime ownership was feature-centric
- explicit feature enablement provides a single source of truth for topology and simplifies reasoning about which readers should decrypt which secrets
- keeping application composition boundaries meaningful (multi-service stacks only) avoids taxonomical indirection for singleton services
- a clean cutover avoids prolonged confusion from dual model co-existence

Supersedes/updates:

- supersedes D-004's `secrets/common.yaml` + `hosts/<host>/secrets.yaml` model with the topology-aligned four-bucket model
- supersedes D-010's bootstrap default assumption that secrets are only common + host-monolith
- updates the canonical host composition pattern to thin assembly layers

## D-031: Remote network-owner cutovers are boot-time deploys

Status: Accepted

Decision:

- treat remote networking ownership changes as boot-time cutovers rather than live `switch` activations over SSH
- keep ordinary host convergence on `deploy-rs`, but use `deploy-rs --boot` plus an operator-triggered reboot when a change stops old network units and hands control to a different stack
- `do-admin-1` uses declarative `systemd-networkd` with explicit static addresses on `ens3` and `ens4`, with `cloud-init` retained for metadata only and `dhcpcd` disabled

Rationale:

- a live SSH deployment can lose transport while activation stops the old network owner, even if the target generation itself is valid
- applying the cutover at boot keeps the current session stable until the new generation takes control during early boot, where console rollback remains available
- `do-admin-1`'s current provider-assigned addresses are stable enough for explicit declaration and matched the observed healthy runtime state better than the attempted DHCP handoff

## D-034: Remote hosts keep a console-only rescue baseline with weekly exercise

Status: Accepted

Decision:

- active remote hosts keep a declarative `rescue` user for provider or serial console break-glass access when normal SSH/Tailscale paths are unavailable
- the `rescue` user is console-only, password-authenticated, separate from the normal identity-backed admin flow, and requires sudo with password rather than inheriting the default passwordless wheel posture
- the recovery feature owns its own secret contract and reads the host-scoped rescue password hash from `secrets/hosts/<host>/system.yaml`, while host files remain thin and only enable/bind the feature
- active hosts run a weekly reboot exercise through the shared recovery module so the break-glass baseline is exercised routinely

Rationale:

- the practical outage gap was lack of a local password-authenticated console path after network or SSH failure, not lack of another routine SSH identity
- keeping the rescue user separate from normal admin access preserves the private-first identity model while making the break-glass path auditable and easy to rotate
- module-owned secret wiring matches the repository's feature-oriented composition model better than host-owned `sops.secrets` declarations for recovery internals
- a routine reboot exercise provides earlier feedback on boot/login regressions than waiting for a real outage

## D-035: GitHub Actions uses nixbuild.net as the canonical CI build plane

Status: Superseded by D-082 — the CI build plane is the fleet's own machines, reached through nix-fleet's build-account, `ci` profile and reusable build workflow, and `.#checks` is what CI builds

Decision:

- GitHub Actions is the canonical hosted validation surface for this repository
- CI installs Nix with `nixbuild/nix-quick-install-action` and configures nixbuild with `nixbuild/nixbuild-action`
- nixbuild authentication in CI uses GitHub OIDC plus an attenuated `NIXBUILD_TOKEN`
- validation workflows reserve host toplevel remote-build checks for manual `workflow_dispatch` runs only; automatic PRs to `main` and pushes to non-`main` stay on lightweight validation only
- OpenTofu validation is intentionally deferred from CI in this change until a separate CI credential model is introduced

Rationale:

- keeps mixed-architecture validation reproducible without maintaining a custom runner fleet
- reduces CI secret sharpness versus SSH-key-only nixbuild auth
- keeps the change focused on Nix host validation and deploy flow first

## D-036: GitHub Actions deploys use Tailscale SSH-first auth with reusable workflow structure

Status: Accepted

Decision:

- deploy workflows join the tailnet temporarily with `tailscale/github-action@v4` using GitHub OIDC workload identity
- full deploys run only when operators invoke the deploy workflow manually via `workflow_dispatch`, using the canonical serial order `do-admin-1` then `oci-melb-1`
- deploy auth is intended to succeed via Tailscale SSH policy for the `dev` user rather than a repository-stored CI deploy SSH private key
- workflow structure keeps shared deploy logic in reusable GitHub Actions surfaces so host changes do not require copying large job blocks, with host prebuild + deploy owned by the reusable per-host workflow
- CI-specific SSH client relaxations are passed inline to `deploy-rs` rather than written to a generated SSH config file
- CI deploys pass `deploy-rs --remote-build` inline so the target host realizes the deployment and fetches directly from configured substituters instead of using the GitHub runner as a store-path relay
- host-side substitute/trust defaults remain policy-driven for hosts and are not reused for GitHub deploy access

Rationale:

- preserves the private-first network model while removing a separate CI deploy private key contract
- avoids overloading host-scoped machine auth for CI concerns
- makes deploy order explicit so edge/admin dependencies fail early instead of drifting silently
- reduces CI bandwidth/storage waste and one extra failure hop when hosts already have equivalent substituter access

## D-037: Shared host Nix substitute defaults live in policy and common host profile composition

Status: Accepted

Decision:

- canonical host-side substitute/trust defaults live in `policy/globals.nix`
- the `base` foundation aspect applies those defaults for active hosts as part of common host composition
- host files should not need separate build-profile imports or enable flags just to inherit the shared substitute baseline

Rationale:

- keeps `flake.nix` focused on wiring rather than embedding fleet policy
- reduces host boilerplate while preserving one canonical policy source
- keeps future host exceptions available through normal NixOS module override behavior if needed

## D-038: Sovereign binary cache uses niks3 with native S3 read path

Status: Accepted

Decision:

- niks3 (Mic92/niks3) is the fleet sovereign Nix binary cache, chosen over Attic/Celler for native S3 read path (no public HTTP endpoint required)
- cache runs on `oci-melb-1` with PostgreSQL and Cloudflare R2 backend
- only hosts push, post-deploy, via host-scoped API tokens; CI never pushes
- server-side Ed25519 signing with key only on cache host; consumers trust public key from `policy/globals.nix`
- substituter priority: nixbuild.net → sovereign S3 → cache.nixos.org
- reference-tracking GC with 30-day retention

Rationale:

- native S3 consumer reads avoid exposing a public homelab HTTP cache endpoint, preserving private-first posture
- host-only push authority aligns cache contents with known-good deployed states
- server-side signing reduces key exposure vs per-pusher keys
- niks3's GC and signing provide governance that plain S3 lacks

## D-039: Dependency management ownership split between Renovate and nvfetcher

Status: Accepted

Decision:

- Renovate owns flake input updates (`flake.lock`) and OCI image reference updates (`policy/oci-images.nix`); both are human-authored dependency references that benefit from Renovate's PR update model with changelog context.
- nvfetcher owns non-flake upstream source metadata for custom package derivations (`pkgs/_sources/generated.nix`, configured from `nvfetcher.toml`); these need generated version/hash metadata that fits nvfetcher's source-generation model.
- OCI image references are centralized in `policy/oci-images.nix` in `image:tag@sha256:digest` form and consumed by service modules via `ociImages.<name>` (passed through `specialArgs`).
- Scheduled CI automation (`.github/workflows/nvfetcher-refresh.yml`) regenerates nvfetcher outputs weekly and opens or updates a PR; generated source updates never push directly to `main`.
- Each tool has one clear ownership boundary with no overlap on the same dependency class.

Rationale:

- split ownership by dependency type avoids overlapping automation and keeps each source of truth unambiguous
- centralized OCI manifest gives Renovate a single target and makes image auditing routine
- digest-pinned OCI references from the first rollout ensure reproducible image pulls
- PR-based nvfetcher automation preserves reviewability and mirrors Renovate's update model
- documented operator workflow ensures one clear update path per dependency class

## D-040: AudioMuse is optional Navidrome extension with music-service file rehome and Postgres-only backup

Status: Accepted

Decision:

- AudioMuseAI is added as an explicit optional Navidrome similarity extension under `applications.music.audiomuse.enable`; it is not an implicit always-on dependency of the music stack
- The repository owns declarative service topology, OCI container images, SOPS-backed bootstrap secrets, plugin binary placement (`audiomuseai.ndp` release v8), and Navidrome runtime flags; remaining AudioMuse setup wizard and Navidrome plugin UI configuration are documented as operator steps
- Music service modules are regrouped under `modules/services/music/` as a file-layout-only move; existing option paths (`services.navidrome`, `services.beets`, `services.slskd`, etc.) remain unchanged (path now `modules/music/`; the tree converted to discovered contributors post-Stage-8)
- AudioMuse durable state scope is Postgres-only (`/srv/data/audiomuse/postgres`); Redis queue/cache and temp audio working files are excluded from canonical backup scope
- AudioMuse follows the current internal-service-first exposure model; no new public ingress route is added unless existing edge policy explicitly composes one
- Infrastructure deployed (containers running, plugin binary placed, flags active) is distinguished from E2E validated (Symfonium actual similar/radio behavior); the feature is not accepted as working until E2E validation passes

Rationale:

- AudioMuse is a supporting music-intelligence service for the Navidrome listening path, not a standalone app surface; making it optional avoids unnecessary deployment coupling
- Upstream AudioMuse persists setup in application-managed database state and Navidrome plugin configuration in Navidrome-managed state; full declarative state injection is not practical without a stable upstream import/export interface
- A file move improves navigability for the now-substantial music stack without multiplying risk through option namespace migration
- Excluding Redis/temp from backup preserves meaningful backup scope and avoids promoting cache/queue/temp data as authoritative recovery state

Supersedes/updates:

- updates the music service module layout under `modules/services/music/` without changing any public option namespace (path now `modules/music/`)
- documents AudioMuse backup scope separately from other music stack services (Postgres-only vs. full state backup)

References:

- AM-1, AM-2, AM-3, AM-5 from audiomuse-navidrome-integration design

## D-041: Traktor playlist sync starts as a manual upstream-module worker

Status: Superseded by D-045 (Traktor stack deleted)

Decision:

- Add `traktor-m3u-sync` as an upstream flake input and use its NixOS module/package instead of vendoring local Python packaging.
- Compose it from `applications.music` as an optional worker for `oci-melb-1`, with `collection.nml` expected at `/srv/media/traktor/collection.nml`.
- Keep playlist export and import paths separate under `/srv/media/playlists/traktor/export` and `/srv/media/playlists/traktor/import`.
- Keep `traktor-m3u-sync-export.service` and `traktor-m3u-sync-import.service` manual-only; do not add timers, path watches, or Syncthing-triggered automation in the first iteration.
- Treat import as sandbox-only (`Imported Playlists` by default) and rely on upstream timestamped backups before writing `collection.nml`.
- Make the Traktor-side library root mapping explicit and placeholder-driven until the real Traktor path roots are verified from the synced NML.

Rationale:

- Upstream owns the Python package, `traktor-nml-utils` dependency, and systemd units; this repo should own fleet paths, ACLs, and operational policy.
- Manual triggers keep the first integration reversible and observable while path translation and import behavior are tested against real Traktor data.
- Separate import/export directories prevent accidental feedback loops between generated playlists and operator-curated import files.
- Using the existing `music-ingest`/`media` ACL model keeps playlist workspace permissions consistent with the rest of the music stack.

References:

- traktor-m3u-sync-worker design decisions TMS-1 through TMS-5

## D-042: `la-admin-1` becomes the active admin/edge/identity host via non-destructive adoption

Status: Accepted

Decision:

- `la-admin-1` is the active x86_64 admin, edge, and Kanidm/OIDC host; `do-admin-1` remains an undeployed deploy-rs rollback node, absent from `deployOrder` and CI, until the LA backup/recovery gates pass and it is decommissioned
- serial deploy order is `la-admin-1` before `oci-melb-1`
- `docs/runbooks/host-initialization.md` is the canonical generic bring-up runbook (adoption vs reimage selection, fact capture, verified host-key-to-age derivation, operator-key and outbound-key ownership, SOPS/Tailscale/recovery handoff, source-controlled first boot, deploy-rs steady state, no manual users outside the flake); `docs/runbooks/admin-host-migration.md` references it and records LA transfer facts only
- LA is adopted non-destructively from its preinstalled NixOS system: `nixos-facter` report consumed directly, only observed root/ESP by-UUID mounts hand-maintained, preserved UEFI `systemd-boot`, first generation applied with `nixos-rebuild boot --target-host <initial-user>@<addr> --use-remote-sudo --flake .#<host>` plus console reboot
- cross-host consumers resolve stable service IDs through the policy catalog (`config.repo.web.catalog`); physical deployment facts (`edgeHost`, `deployOrder`) live only in `lib/deploy/hosts.nix` and must never be interpreted as NixOS nodes
- LA adoption is separate from later AU edge and US-East workload work
- source freeze/rollback: DO stays authoritative until the planned freeze, LA restore is read-only until then, and DO remains startable/routable for rollback during the 24-hour soak window after cutover
- secret values are preserved while readers and paths change: the operator creates and re-encrypts LA ciphertext from templates after fingerprint-verifying the host key, removes the DO recipient immediately from moved LA-only/admin/identity scopes, retains it only on scopes the still-running rollback host actively reads, and grants host-scoped Tailscale/R2/ntfy access
- Open WebUI deployment is deferred until the migration cutover and backup gates pass
- D-031 remains the historical networking lesson for remote network-owner cutovers

Rationale:

- preserves identity, edge, and state contracts with a real rollback path while retiring the expiring-credit provider
- one canonical runbook prevents the next host from recreating this discovery work
- catalog-versus-physical separation keeps runtime routes decoupled from host replacement
- operator-owned secret actions keep blast radius and provenance unambiguous

References:

- MIG-1 through MIG-9 from the migrate-admin-host-to-la change design

Supersedes/updates:

- supersedes D-036's serial deploy order (`do-admin-1` then `oci-melb-1`) with `la-admin-1` before `oci-melb-1`, and removes DO from regular deploy and CI until decommission

## D-043: Native systemd-networkd is the fleet networking baseline

Status: Accepted

Decision:

- fleet hosts own physical networking through the import-activated `networking` foundation aspect (published in `modules/flake/networking.nix`; private leaf `modules/flake/_aspects/networking.nix`), which renders native `systemd.network.{networks,netdevs}` units from required `fleet.networking` host facts and retires scripted networking/dhcpcd fleet-wide
- physical addressing is DHCPv4 with MAC-based client identity so provider/router leases and reservations survive migration
- `systemd-resolved` is the fleet resolver mechanism; per-link provider/DHCP DNS stays primary for routing domains, with safe defaults (`DNSOverTLS = opportunistic`, `DNSSEC = allow-downgrade`, `FallbackDNS`)
- `home-forge` runs an always-on host-owned `br0` bridge over `eno1` pinned to `84:a9:3e:6b:94:44` so the router reservation holds
- `oci-melb-1` disables `IPv6AcceptRA` on its uplink until the provider provisions IPv6; its VCN resolver and `homelabvcn.oraclevcn.com` route domain stay primary via per-link DHCP DNS
- `la-admin-1` gains `systemd-resolved`; Tailscale switches from `/etc/resolv.conf` overwrite to D-Bus split-DNS
- network-owner cutovers stay boot-staged (`deploy-rs --boot`), console-backed, with a second ordinary reboot proving repeatability

Rationale:

- the fleet ran NixOS scripted networking by omission, not decision, and it failed opaquely in production on 2026-08-25: the home-forge bridge cutover left `br0` addressless because dhcpcd silently ignores bridge-master interfaces without an explicit config section and NixOS never emits one
- D-031 already proved declarative `systemd-networkd` viable on do-admin-1; this change makes native networkd the fleet baseline before the Engine DJ change rebases on top and consumes host-owned bridge topology
- live result: all three hosts passed two-boot validation (staged boot, console reboot, second ordinary reboot) — reserved `.100` lease and pinned bridge MAC on home-forge, `*.oraclevcn.com` resolution and RA-off posture on oci-melb-1, key-only SSH and MagicDNS via resolved on la-admin-1
- LA cutover validation also exposed two pre-existing cold-boot defects, now corrected: Cockpit certificate material gates `cockpit.service` without ordering `cockpit.socket`, and both repo-owned Tailscale Serve publishers gate on native `tailscale wait` before programming Serve state (fixing the `NoState` race)

References:

- D-031 for the boot-time cutover discipline, and the change specs/design `openspec/changes/adopt-native-systemd-networkd/{design,specs/host-networking/spec,specs/network-access/spec}.md`

## D-044: Windows workloads run in a declarative libvirt VM layer; Engine DJ library stays on Linux ext4

Status: Accepted

Decision:

- `modules/services/virtualisation/windows-vm.nix` provides a reusable layer: declarative instances (vcpu, memory, disk, autostart, SPICE port, TPM, install ISO), virtiofs shares keyed by mount tag, and per-instance systemd controller units over libvirt domains (file now `modules/music/windows-vm.nix`)
- guests attach to the host-owned always-on `br0` bridge over `eno1` (fleet networking aspect, D-043); the VM layer only consumes the bridge and never creates or owns physical networking — macvtap and VFIO passthrough are rejected because Remote Library discovery needs same-L2 broadcast and host↔guest reachability
- SPICE binds to loopback only; operators tunnel over Tailscale via SSH
- Engine DJ (`modules/applications/dj/`) is the first consumer: the Engine library (including the SQLite database) is the real `Engine Library` directory inside the host music root `/srv/storage/media/music`, exposed read-write through the single `M:` virtiofs share as `M:\Engine Library` (no separate share, mount tag, or guest junction)
- single-writer discipline is enforced by unit dependencies: future Linux sync workers bind to `dj-library-writers.target`, which conflicts with the VM controller unit; restic backups quiesce the VM through state-backups prepare/cleanup hooks and conflict with the writer target
- guest software installation (Windows, virtio-win drivers, Engine DJ ≥ 4.3.4) is operator-driven per `docs/runbooks/engine-dj-guest-setup.md`; `setup.ps1` registers `M:`/`S:` and removes the legacy `L:` Engine-library share, while the operator points the Windows Music known-folder directly at `M:`
- live validation confirmed the single-share virtiofs layout across track import, SC6000 Remote Library, guest/host reboots, and SQLite integrity checks; guest-local database copy-in/copy-out remains the fallback if a future virtiofs regression appears

Rationale:

- keeps the library database readable by libdjinterop workers without foreign filesystem mounts, while the SC6000 consumes it as a native Engine Remote Library source
- a shared VM layer prevents each future Windows-only workload (e.g. Lexicon/rekordbox USB export) from spawning ad-hoc virtualization
- kernel-mediated mutual exclusion beats lockfiles and hooks for write-authority discipline

References:

- windows-vm-engine-dj change proposal/design/specs

## D-045: Music application is owned by home-forge with the AudioMuse database in OCI

Status: Accepted

Decision:

- the complete music application (Navidrome, AudioMuse compute, Syncthing, slskd/Beets/Tagr ingest) composes on `home-forge` through `applications.music`
- the canonical media root on `home-forge` is `/srv/storage/media` with sibling `library/`, `quarantine/`, `inbox/`, and `.versions/`; Navidrome, Engine DJ's `M:` share, and Syncthing all use `library/`
- `oci-melb-1` disables `applications.music`, retains the shared PostgreSQL cluster (AudioMuse database + backup), and keeps its copied `/srv/media` tree and prior music service state on disk only as rollback insurance
- AudioMuse reaches its database in OCI's shared Postgres over Tailscale/MagicDNS (tailnet-only + SCRAM); availability coupling is accepted: an OCI/tailnet outage degrades AudioMuse, not core Navidrome
- database-side role password lives in the OCI-only `secrets/services/postgres-shared.yaml` at `roles/audiomuse/password`; home-forge AudioMuse reads the client-side password from `secrets/applications/music.yaml` at `audiomuse/postgres_password`
- LA edge routes `music`, `slskd`, and `tagr` to `home-forge` (`tailscale-upstream`)
- Syncthing hub is `home-forge` with sendreceive `library/`, `quarantine/`, and `inbox/` folders shared with the `arch` and `windows` devices and staggered version archives under `.versions/`
- Navidrome stays the stock package: the packaged AudioMuseAI `.ndp` is symlinked into the data directory via tmpfiles and bind-mounted into nixpkgs' fixed plugin folder, avoiding Navidrome rebuilds
- legacy Traktor/NML playlist wiring remains deleted; `home-forge` uses the externally maintained `traktor-m3u-sync` module only for the engine-direct Navidrome M3U → Engine library playlist flow (the engine export job writes into the Engine library DB), with no Traktor configuration or synchronization

Rationale:

- Engine DJ is the active library authority on `home-forge`; colocating the whole music stack with the canonical media tree gives Engine a direct import path from `M:` without Syncthing staging or manual copies
- keeping the AudioMuse database in OCI reuses the accepted shared-Postgres pattern (as Arch workstation clients already do) and keeps database-side secret ownership with the database host
- a downtime cutover with the edge route moved last and the OCI generation retained provides a clean rollback path

Supersedes/updates:

- supersedes D-041 (Traktor manual playlist worker) — its Traktor/NML scope remains deleted; the external module is now used only for the separate Navidrome M3U export path
- updates D-040's OCI-local AudioMuse placement: AudioMuse compute now runs on `home-forge` with its Postgres database in OCI's shared cluster
- updates D-019/D-020/D-029/D-033 `/srv/media` path contracts: canonical media paths are now `home-forge` `mediaRoot`-derived (`/srv/storage/media/...`), while OCI keeps its copied tree for rollback only

References:

- openspec change `navidrome-itunes-engine-sync` (proposal/design/specs)

## D-046: Music application root is host-selected; Engine DJ shares the music root

Status: Accepted

Decision:

- hosts own their physical storage roots: `applications.music` requires explicit `storageRoot` and `dataRoot` bindings with no fleet defaults, and `policy/globals.nix` no longer carries music paths
- the music application root on `home-forge` is `/srv/storage/media/music` (`musicStorageRoot` in `hosts/home-forge/default.nix`) with the conventional layout beneath it: `library/` (Beets directory, Navidrome MusicFolder, Syncthing `library` folder), `playlists/`, `inbox/` (`dropbox/`, `slskd/`), `quarantine/` (`untagged/`, `approved/`), and `.versions/` (Syncthing staggered version archives)
- Engine DJ's `M:` virtiofs share maps the whole music root, not `library/` alone; the guest sees `M:\library`, `M:\playlists`, `M:\Engine Library`, `M:\inbox`, and `M:\quarantine`. `M:\Engine Library` is a real directory on the share (host `<storageRoot>/Engine Library`) — no separate share, mount tag, or guest junction; the operator points the Windows Music known-folder directly at `M:` so Engine resolves `Music\Engine Library` to `M:\Engine Library`
- playlists sync engine-direct: the `traktor-m3u-sync` engine export job (chained from the Navidrome M3U import) writes playlists straight into the Engine library database at `<storageRoot>/Engine Library/Database2/m.db` (guest `M:\Engine Library\Database2\m.db`) with `track_path_prefix=../library`, resolving tracks relative to the Engine Library dir on `M:`

Rationale:

- one share root keeps host and guest viewing the same layout; synced playlist output lands in the Engine library DB under `Engine Library/Database2`, never inside `library/`, so it cannot surface as audio in Navidrome or Syncthing sync scope
- a required binding instead of a default prevents a new host from silently inheriting home-forge's physical path
- the Engine DJ main library database still references pre-move `M:\Artist...` paths; synced playlists avoid the XML re-import cost because the engine export writes `../library`-relative locations directly into the Engine library DB (see `docs/runbooks/engine-dj-guest-setup.md`)

Supersedes/updates:

- refines D-044's `M:` source wording: the music root is the host-selected `applications.music.storageRoot` binding with the conventional layout beneath it, not a pre-normalization flat library root
- supersedes D-045's canonical-path claim: the host-selected music application root `/srv/storage/media/music` (with a `playlists/` sibling) replaces the `mediaRoot=/srv/storage/media` option and its sibling directories

References:

- D-044, D-045, `docs/runbooks/engine-dj-guest-setup.md`, and the `normalize-music-storage-topology` and `navidrome-m3u-itunes-worker` change designs

## D-047: Staged Dendritic transition supersedes D-030's plain-flake restriction

Status: Accepted

Decision:

- retire the D-030 (feature-oriented host topology) clause "keep plain explicit `flake.nix` architecture (no `flake-parts` or Dendritic Nix adoption in this change)"; the fleet adopts Dendritic-style flake-parts composition through staged OpenSpec changes, with `dendritic-stage-1-scaffold-hosts` as the next change
- Stage 1 uses flake-parts plus `denful/import-tree` (underscore-prefixed path components are excluded by its default filter), publishes aspects through `flake.modules.nixos.<aspect>`, and constructs all three hosts atomically through a typed `nixos.configurations.<host>` registry, moving host composition to `modules/hosts/<host>/`
- host-private/raw data files stay out of import-tree; plain leaf NixOS modules remain temporarily behind an explicit `import-tree.filterNot` boundary until their feature converts to an aspect, and each conversion shrinks that boundary
- Stage 1 removes every lower-level `self`, `inputs`, and `ociImages` consumer rather than introducing a compatibility `specialArgs` bridge: flake-input consumers close over their owning aspect, custom packages use flake-parts `perSystem`/`withSystem`, OCI image references become typed policy data instead of an argument bus, and source provenance closes over `inputs.self`
- `flake-file`, Den, and topology extraction are deferred; `flake-file` returns only if explicit input management becomes a demonstrated maintenance problem
- `nix-fleet` is recorded as a future code-only shared library, not a dependency of this transition. Candidates — not commitments: Tailscale, SSH, builder access, Nix defaults, selected shell defaults, notification daemon/dispatch, niks3 post-build/post-deploy integration, and Beszel agent. Code moves only after a local aspect is verified and both repositories require materially identical behavior
- concrete topology/inventory values, `policy/web-services.nix`, domains/exposure/Cloudflare policy, OpenTofu, deploy-rs metadata and ordering, `.sops.yaml` readership, and encrypted secrets remain owned by `nix-homelab`; a cross-repository topology SSOT is a separate future decision

Rationale:

- D-030's plain-flake clause was scoped to that change's cutover, not a permanent architecture veto; the transition analysis revalidated 2026-09-09 established aspect composition as the direction, and Stage 0 cleanup must not optimize for the architecture being retired
- eliminating the argument bus in the same change as the scaffold prevents a compatibility bridge from institutionalizing the `self`/`inputs`/`ociImages` wiring Stage 1 exists to remove
- keeping topology, web policy, and secrets local preserves the D-004/D-030 blast-radius model and the D-042 catalog-versus-physical split while code organization changes

Supersedes/updates:

- supersedes D-030's plain-flake architecture restriction; D-030's feature-oriented composition, topology-aligned secret buckets, and thin-host principles remain in force and are carried into the aspect model
- settles `docs/dendritic-transition-analysis.md`'s Stage 1 boundary: host dirs move to `modules/hosts/<host>/` (not top-level `hosts/`), the temporary `filterNot` leaf boundary is explicit and enumerable, and consumer removal replaces any specialArgs bridging

References:

- `openspec/changes/dendritic-stage-0-pre-clean/{proposal,design}.md` (PC-3, PC-4)
- `docs/dendritic-transition-analysis.md` (Revalidation 2026-09-09)

These are known but intentionally unresolved until implementation and operational learning justify final decisions.

- when to introduce service-scoped secret files for movable workloads
- when and how to introduce `rclone`/VFS into media flow
- hook/event framework for future processing pipeline
- backup policy timing once host authority increases
- fleet tool choice and operating model once host count grows

## D-048: Dendritic Stage 2 ships foundation-first; the music-exemplar Stage 2 is superseded

Status: Accepted

Decision:

- the transition analysis's "Stage 2 — music exemplar" sequence is superseded/historical; Stage 2 shipped instead as foundation-first under `dendritic-stage-2-foundation-aspects`, because `modules/core/` (base/users) and `modules/profiles/` (four legacy wrappers plus p10k data) contained only the small duplicated fleet foundation
- five foundation aspects are published through `flake.modules.nixos.{base,shell,networking,tailscale,notify}` (`modules/flake/aspects.nix`); selection is enablement — every host registry record imports all five explicitly and no aspect imports another aspect
- `base` owns policy, users, and the typed per-host facts `fleet.foundation.bootLoader` (`grub` | `systemd-boot`) and `fleet.foundation.buildTmpfsSize` (required string); `oci-melb-1` declares `grub`/`8G`, `la-admin-1` and `home-forge` declare `systemd-boot`/`50%`; boot loader and `/build` render from the facts with no `mkForce`
- `shell` owns interactive tooling including the nix-index comma input (the former `cli` aspect is deleted); `networking` publishes the existing native networkd contract unchanged; `tailscale` owns the conventional host-secret auth-key registration and nullable `services.tailscale.debugMtu` (1200 on OCI/LA, unset on forge); `notify` enables the notification daemon with withSystem-resolved packages
- `modules/core/` and `modules/profiles/` are deleted and removed from the `_unconverted-nixos-dirs.nix` exclusion; deferred operational behavior remains explicit raw-leaf imports in host records (niks3-post-deploy, niks3-upload-client via `modules/shared/niks3-upload-client.nix`, nixbuild-ssh, beszel-agent-auth, state-backups, web-policy), with no compatibility wrapper or composition bus
- `dendritic-stage-2-foundation-aspects` is implementation-complete but is neither deployed nor archived; equivalence validation and archival remain separate pending gates

Rationale:

- the live tree made foundation-first cheaper and safer than the music exemplar: the whole legacy foundation was two core files plus four profile wrappers, while music is a large, placement-coupled application whose conversion belongs with a real placement move
- typed facts remove the old boot-loader and `/build` override conflicts at the source instead of changing priorities, matching the Stage 1 no-`mkForce` discipline

Supersedes/updates:

- supersedes the music-exemplar "Stage 2" sequencing in `docs/dendritic-transition-analysis.md` (Stage 3's per-need conversions and the future music-aspect work remain staged)
- updates D-015, D-037, and D-043 to name the foundation-aspect locations for the paths they originally recorded

References:

- `openspec/changes/dendritic-stage-2-foundation-aspects/{proposal,design}.md` (FND-1–FND-7)
- `docs/dendritic-transition-analysis.md` (Stages)

## D-049: Dendritic Stage 3 publishes the operational aspects; the five deferred leaves are no longer host imports

Status: Accepted

Decision:

- three operational aspects are published through `flake.modules.nixos.{backups,builder-access,observability-agent}` (`modules/flake/aspects.nix`); selection is enablement — every host registry record imports all five foundation aspects plus all three operational aspects (eight aspects total) and no aspect imports another aspect
- `backups` owns the host-egress capability: it imports `modules/services/state-backups.nix`, the upstream `inputs.niks3.nixosModules.niks3-auto-upload` module, `modules/shared/niks3-upload-client.nix`, and `modules/shared/niks3-post-deploy.nix`; it derives the conventional host secret path `secrets/hosts/${hostName}/system.yaml` and the `shrublab-backup-${hostName}` bucket, defaults `services.state-backups.secretFile` to the derived path, gates state-backups and post-deploy enablement on the file's existence (two-step sops bootstrap preserved on every host), and injects the required `services.niks3-post-deploy.filterPackage` per system via `withSystem` (no hidden `fleet-packages` dependency) (paths now `modules/backups/state-backups.nix` with its declaration surface `modules/backups/state-backups/_consumer.nix`, and `modules/cache/cache-publisher/{upload-client,post-deploy}.nix`)
- `backups` asserts `services.notification-daemon.monitor.enable` via `lib.attrByPath` and never imports `notify`; `notify` owns monitor composition (canonical apprise contract) and the state-backups leaf no longer defaults `monitor.enable`
- the existing `nix.settings.post-build-hook = lib.mkForce ""` is classified as currently necessary (OPS-6): upstream `niks3-auto-upload` sets the hook whenever enabled and has no separate hook-disable option, so the suppression is required while the activation-triggered post-deploy send reuses the upstream daemon/socket; no new `mkForce` is introduced
- `builder-access` owns only nixbuild.net SSH trust (`programs.ssh.knownHosts.nixbuild` + `extraConfig`); substituter policy remains in the `base` aspect and the `fleet.nixbuild-ssh.enable` option is retired
- `observability-agent` owns Beszel agent authentication and enrollment: it derives the conventional host secret path, sets `services.beszel-agent-auth.secretFiles.host` to it, and gates enrollment on the file's existence; the Beszel hub (`modules/services/admin/beszel.nix`) remains an admin-service leaf (hub file now `modules/admin/beszel.nix`; the agent-auth body is `modules/flake/observability-agent.nix`)
- the five deferred leaves (`state-backups`, `niks3-upload-client`, `niks3-post-deploy`, `nixbuild-ssh`, `beszel-agent-auth`) are no longer imported directly by host records, and the registry no longer imports `inputs.niks3.nixosModules.niks3-auto-upload` (the `backups` aspect owns that import); OCI keeps the niks3 server module import (`inputs.niks3.nixosModules.niks3`) and its loopback cache endpoint
- the OCI cache server (`modules/services/niks3.nix`) stays a leaf; `services/` and `shared/` remain temporarily excluded from import-tree discovery (`_unconverted-nixos-dirs.nix`) because both roots still contain unconverted leaves (both exclusions are now removed — `shared` in Stage 5, `services` in the post-Stage-8 services-tree conversion — and the boundary file holds an empty list)
- the transition analysis's "forge may never get builder access" note is superseded: all three hosts, including home-forge, select `builder-access`

Rationale:

- the five leaves had clear boundaries after Stage 2 (backups + cache upload = host egress, nixbuild SSH trust = builder access, Beszel agent = observability), so publishing them as explicit aspects makes operational capabilities host selections instead of repeated raw-leaf imports
- deriving the secret path and bucket from `networking.hostName` removes three identical host literals while preserving the exact evaluated values and the two-step bootstrap gate
- explicit selection plus assertion (never hidden transitive imports) keeps the no-composition-bus discipline from D-047/D-048

Supersedes/updates:

- supersedes the Stage 2 "deferred operational behavior remains explicit raw-leaf imports in host records" statements for these five leaves in `docs/dendritic-transition-analysis.md`, `docs/context-history.md`, `docs/plan.md`, `STRUCTURE.md`, `CONVENTIONS.md`, and `ARCHITECTURE.md`
- updates D-048's retained-leaf wording for the five converted leaves; the remaining shared/service leaves (`web-policy`, `kanidm-host-auth`, `identity-oidc`, and the rest of the service tree) stay staged (D-059 later made the OIDC contract the intrinsic `modules/identity/_oidc.nix` and the capability the `kanidm-host-auth` aspect)

References:

- `openspec/changes/dendritic-stage-3-operational-aspects/{proposal,design}.md` (OPS-1–OPS-11)
- `docs/dendritic-transition-analysis.md` (Stages)

## D-050: Source ownership and deployment aspects are independent axes; Stage 4 realigns the documented model

Status: Accepted

Decision:

- top-level source ownership and public deployment variability are independent axes: an import-tree-discovered file is a top-level flake-parts contributor, while a deployment aspect is a deferred NixOS module explicitly selected by a host; several source modules may contribute to one coherent aspect, and discovery registers contributions without deploying them
- the central `modules/flake/aspects.nix` publication file is replaced by concern-owned contributors discovered under `modules/flake/` — support (`provenance.nix`, `oci-images.nix`, `fleet-packages.nix`), foundation (`base.nix`, `shell.nix`, `networking.nix`, `tailscale.nix`, `notify.nix`), operational (`backups.nix`, `builder-access.nix`, `observability-agent.nix`), and the existing `dj.nix` — preserving every `flake.modules.nixos.<name>` contract
- `provenance`, `oci-images`, and `fleet-packages` are infrastructure support modules (typed repository data, package projections, provenance for lower-level consumers), not host-facing deployment capabilities; they remain only until consumers migrate to native projections (feature-owned lexical capture, intrinsic registry/base composition, feature contributors injecting their own packages)
- `dj` is a host-facing selected deployment aspect: selecting it enables `applications.dj`, while Engine DJ enablement, paths, and secret inputs remain host-configurable; home-specific variants remain host-owned
- aspect relationships are modeled by semantics rather than a universal no-aspect-import rule: intrinsic composition (the owner directly imports a required implementation or aspect with no meaningful independent placement), policy co-selection (independently placeable capabilities selected together by host policy, optionally with a named assertion), and optional integration (activates only when both contracts are present; neither selects the other); direct public-aspect imports are not globally forbidden but require intrinsic-composition justification — Stage 4 adds none
- conventional plain class-oriented NixOS leaves and the six-directory enumerated import-tree filter are transitional, not the endpoint: the filter must shrink as converted roots empty, and underscore-renaming whole roots solely to hide unchanged code is not completion; genuine private implementation/data may remain private with underscore-prefixed or otherwise explicit private paths
- Stage 4 is a realignment only: web, identity, and music conversions are deferred

Rationale:

- the documented endpoint conflated source-file granularity with deployment-aspect granularity, producing a central publication file, a permanent-hybrid narrative, and a `dj` selection that did not itself enable DJ
- classifying support modules separately prevents them from becoming permanent ambient buses and gives each a concrete retirement path
- relationship-specific composition rules match how capabilities actually relate (backups→notify is policy co-selection, not a hidden import) while keeping optional integrations free of hidden activation

Supersedes/updates:

- supersedes D-047's "plain leaf NixOS modules remain temporarily behind an explicit `import-tree.filterNot` boundary until their feature converts to an aspect" endpoint framing: plain class-oriented leaves and the six-directory filter are transitional, and private lower-level modules are justified exceptions rather than the default endpoint
- supersedes D-048's and D-049's universal "no aspect imports another aspect" rule with the three composition modes (intrinsic composition, policy co-selection, optional integration)
- updates D-048's and D-049's central `modules/flake/aspects.nix` publication location: aspect definitions now live in concern-owned discovered contributors under `modules/flake/`
- reclassifies the `provenance`, `oci-images`, and `fleet-packages` modules published since Stage 1 as infrastructure support rather than deployment capabilities
- supersedes the "80% plain leaves" endpoint framing in `docs/dendritic-transition-analysis.md`: conventional leaves and the filter are transitional, not the permanent target

References:

- `openspec/changes/dendritic-stage-4-source-model-realignment/{proposal,design}.md` (S4-1–S4-6)

## D-051: Stage 5 removes the shared/storage roots and proves the multi-contributor aspect

Status: Accepted

Decision:

- the last two legacy evaluator-class roots leave the import-tree exclusion boundary: `modules/storage/` is deleted (both `disko-root.nix` and `disko-single-disk.nix` were zero-consumer templates) and `modules/shared/` is emptied and removed with no default or wrapper contributor; sole-consumer disk layouts remain host-local (`modules/hosts/oci-melb-1/disko-single-disk-split.nix`, `modules/hosts/home-forge/disko-two-disk.nix`; LA is a preinstalled-NixOS adoption with no disko layout)
- the four private implementation leaves relocate beside their aspect owners under underscore-private concern paths, which is the recorded private-path convention: `_aspects/host-recovery.nix` (base), `_backups/niks3-upload-client.nix` and `_backups/niks3-post-deploy.nix` (backups), and `_builder-access/nixbuild-ssh.nix` (builder-access); each remains reachable only through its owner's imports, publishes no `flake.modules.nixos.<name>`, and is not discovered as a top-level contributor (`niks3-upload-client.nix` adjusts its conventional secret read `../../secrets/hosts` → `../../../secrets/hosts` for the deeper path; the other three have no relative repo reads)
- the three private paths split by owner concern and are not normalized or reorganized later without a new decision: `_aspects` holds foundation private implementations, `_backups` holds backups private leaves, and `_builder-access` holds builder-access private leaves
- `web-policy` becomes the discovered top-level contributor `modules/flake/web-policy.nix`, publishing `flake.modules.nixos.web-policy` and carrying the existing `repo.web` options/defaults unchanged; it is classified as an infrastructure support module alongside `provenance`, `oci-images`, and `fleet-packages` (the support quartet), not a deployable edge capability, and all three hosts select `aspects.web-policy` because all three consume `config.repo.web` (the notification-daemon ntfy default derives from the policy catalog)
- `identity-client` is the first production instance of D-050's multi-contributor single-aspect merge: two separately discovered top-level contributors — `modules/flake/identity-oidc.nix` and `modules/flake/kanidm-host-auth.nix` — each nest their existing NixOS option/config body directly inside their own `flake.modules.nixos.identity-client` definition, with no `_identity-client/` private leaves, no central wrapper, and no cross-contributor import; `aspects.identity-client` is selected on `oci-melb-1` and `la-admin-1` only, and the host-auth body reads `config.services.identity.oidc.providerUrl` through config rather than importing the OIDC contributor (D-059 retired this bundle: the OIDC contract became the intrinsic `modules/identity/_oidc.nix` and the capability is `kanidm-host-auth`)
- the one temporary import-tree filter shrinks from six entries to exactly four — `applications`, `hosts`, `providers`, `services` — and both removed directories are deleted rather than merely unlisted

Rationale:

- the shared root mixed already-private leaves with directly host-imported modules, so the source/deployment separation D-050 describes could not be proven while they stayed behind the filter; relocating the leaves beside their owners and converting the three importable modules into a support contributor plus two collector contributors removes the root without a compatibility wrapper
- the two identity contributors demonstrate the collector pattern in production: selecting one aspect enables both bodies, and deleting either contributor removes its own OIDC or host-auth/Kanidm configuration, with the sibling still publishing the aspect
- recording the private-path split now prevents a later cleanup from "normalizing" `_backups`/`_builder-access` back into a generic private directory and re-hiding ownership

Supersedes/updates:

- supersedes only D-050's deferral clause for `web-policy` and `identity-client` ("web, identity, and music conversions are deferred"): web-policy and identity-client are now converted, while **music remains deferred**; D-050's separation of source ownership from deployment granularity, its support-module classification, and its composition modes remain in force
- updates D-049's `modules/shared/niks3-upload-client.nix` / `modules/shared/niks3-post-deploy.nix` and D-048/D-049's `modules/shared/` leaf locations to the concern-owned private paths above without changing the aspects' evaluated behavior; D-020/D-025/D-032's `modules/storage/disko-*.nix` references are historical decision bodies and remain unchanged — those templates are now deleted and the layouts live host-local
- updates the Stage 4 "`services`/`shared` remain temporarily excluded" statements in `docs/dendritic-transition-analysis.md`, `docs/context-history.md`, `docs/plan.md`, `STRUCTURE.md`, `CONVENTIONS.md`, and `ARCHITECTURE.md`

References:

- `openspec/changes/dendritic-stage-5-shared-source-contributors/{proposal,design}.md` (S5-1–S5-10)

## D-052: Stage 6 converts music into a home-forge-only deployment aspect with a typed DJ contract

Status: Accepted

Decision:

- the music application converts from the directly host-imported evaluator-class coordinator `modules/applications/music/default.nix` (deleted with its `files/` directory) into the discovered top-level contributor `modules/flake/music.nix`, which publishes `flake.modules.nixos.music`; selecting the aspect is its top-level enablement (`applications.music.enable = true`), and only `home-forge` selects `aspects.music` in `modules/flake/registry.nix`; `music` and `dj` remain separately selected aspects and neither imports or enables the other
- the aspect keeps composition ownership only: the public `applications.music.*` options (`enable`, `dataRoot`, `storageRoot`, `syncthingDevices`, `syncthingFolders`, `audiomuse.*`, `navidrome.enable`, `secretFiles.host`, `slskdDomain`, `configFiles`) plus the read-only `contract`, `mediaPaths` derivation, secret-file passthrough with the required-secret assertion, service selection/wiring for Syncthing/Navidrome/AudioMuse/Beets/slskd/Tagr, runner-instance selection, backup policy contracts, `users.users.dev.extraGroups`, `programs.zsh.shellAliases.b`, and the success-chain intent (`services.beets.onSuccessUnits`, `services.beets.importReadyFlag`, `services.musicIngest.onSuccessUnit`)
- concrete implementation ownership moves into private leaves under `modules/services/music/**`, imported only by `modules/flake/music.nix`, publishing no aspects, and never host-imported: the Beets owner (`modules/services/music/beets/default.nix`) owns the Beets SOPS secrets/templates, the read-only `services.beets.renderedConfigFiles.{standard,quarantine}` interface (option declaration and value outside the secret-file gate), the four operator CLIs (`beets-interactive`, `beets-dupes`, `beets-merge-splits`, `beets-prune-empty`), the moved config assets (`modules/services/music/beets/files/beets-{config,quarantine-config}.yaml`), and its own Beets-state tmpfiles; the new private ingest leaf (`modules/services/music/ingest.nix`, options `services.musicIngest`) owns `ffmpeg-preprocess` plus the dropbox path/poke/settle units, the slskd completion hook, and the scoped slskd-settle polkit rule (`modules/services/music/files/ffmpeg-preprocess.sh`); the new private storage leaf (`modules/services/music/storage.nix`, options `services.musicStorage`) owns the `music-ingest` (990) and `media` (987) GIDs, the media root/layout tmpfiles and ACL rules, `media-permission-reconcile`, and the `media-fixperms` CLI; `modules/services/music/beets/runners.nix` is unchanged (paths now `modules/music/{beets,ingest,storage}.nix` with `modules/music/_beets/runners.nix`; every leaf is a discovered contributor since the post-Stage-8 conversion)
- the composition exposes the read-only typed `applications.music.contract.{storageRoot,libraryDir,playlistsDir}`; `dj` consumes it with `config.applications.music.contract or null`, keeps `applications.dj.engine.{sharePath,musicStorageRoot}` typed `lib.types.str` with contract-derived `""`-safe defaults (never `nullOr`), and enforces one named assertion (`musicContract != null || (sharePath != "" && musicStorageRoot != "")`, active only when the engine is enabled), so DJ without music is permitted only with both explicit values and otherwise fails the named assertion; `home-forge` drops the duplicate DJ root/share literals and keeps only `enable`, `traktorStateDir`, and `secretFiles.navidrome`
- behavior is frozen for the conversion: every public option namespace, path, unit name, timer, script, ACL, secret key/path/owner/mode, package name, backup path, and the playlist/Traktor worker logic/input is unchanged; worker adoption of `contract.libraryDir`/`contract.playlistsDir` inside the Engine export job paths is deferred
- the four-root import-tree filter stays exactly `applications`, `hosts`, `providers`, `services` (`modules/flake/_unconverted-nixos-dirs.nix`), so the private music leaves remain reachable only through the discovered music owner. This does not make `services` permanent; the retirement criterion for the transitional `services` root is that when `modules/services/` is scheduled for conversion these leaves either move beside the music contributor under a concern-owned underscore path (`modules/flake/_music/**`) or become top-level contributors if they gain independent placement (the filter is now empty; the retirement criterion was discharged by the post-Stage-8 services-tree conversion, and the music leaves became discovered contributors under `modules/music/` rather than an underscore path)
- no secret bootstrap change: no `secrets/**`, `.sops.yaml`, key, ciphertext, or SOPS recipient edit is part of this conversion; the change is implementation-complete but not deployed and not archived

Rationale:

- the deleted coordinator doubled as composition root and implementation owner: Beets secret/template assembly, operator binaries, concrete runner/timer/path/polkit mechanics, the permission-reconcile body, and the media tmpfiles/ACL implementation all lived in it, while `dj` reached music through host-supplied path literals rather than an explicit contract
- moving mechanisms to their owners makes each independently reviewable while a thin aspect keeps the placement decision (`home-forge` only) and the cross-service wiring visible in one place
- an explicit typed contract plus a named assertion removes the hidden host-literal coupling and keeps DJ-without-music evaluation safe (`types.str` with `""` defaults), preserving the behavior-freeze requirement
- keeping the leaves under the transitional `services` root with a recorded retirement criterion matches D-050's source/deployment separation without forcing a filter shrink as part of this change

Supersedes/updates:

- supersedes only D-050's and D-051's music-deferral clause ("web, identity, and music conversions are deferred" / "music remains deferred"): `music` is now converted, while D-050's separation of source ownership from deployment granularity, its support-module classification, its composition modes, and D-051's web-policy/identity-client conversion and private-path split remain in force
- updates the current-state music paths in `docs/architecture.md`, `docs/plan.md`, `docs/context-history.md`, `docs/dendritic-transition-analysis.md`, `STRUCTURE.md`, `ARCHITECTURE.md`, and `CONVENTIONS.md`; historical decision bodies (D-019, D-033, D-040, D-044–D-046) remain unchanged

References:

- `openspec/changes/dendritic-stage-6-music-composition/{proposal,design}.md` (S6-1–S6-13)

## D-053: Stage 7 completes the public placement surface and removes the application/provider roots

Status: Accepted

Decision:

- every remaining deployed product and platform capability is published as a named discovered deployment aspect and placed by explicit host selection in `modules/flake/registry.nix`: `oci` (OCI provider boot/serial console, OCI only), `edge` (edge application and proxy leaf, role stays host-set, selected by the OCI origin and the LA edge), `cockpit` (OCI + LA, host variants stay explicit), `push-server` (LA ntfy), `identity-provider` (LA Kanidm server/provisioning composition), `admin-hub` (LA Termix, Vaultwarden, Homepage, Gatus, Beszel hub, Webhook, Quantum policy, shared admin-root/SSH wiring), and the OCI workloads `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, plus `omniroute` on home-forge. The Stage 2-6 aspects are unchanged, so the discovered publication set is exactly twenty-eight
- selection supplies each capability's existing top-level enablement (`applications."edge-ingress".enable`, `services.ntfy.enable`, `services.paperless.enable`, `applications.admin.enable`, …) while genuine host variants stay host-set: edge role, cockpit `publicHost`/`urlRoot` mkForce pair (OCI) and `loopbackTls.enable` (LA), Postgres consumer roles, product data roots/secret sources/OIDC wiring, the Music/DJ paths, and OmniRoute's two-step secret gate. `admin-hub` declares `applications.admin.enable` outside its `lib.mkIf cfg.enable` gate because the gate reads that option
- the evaluator-class roots are evacuated and deleted with no compatibility wrapper and no underscore-renamed replacement: the admin coordinator is split across the `identity-provider`/`cockpit`/`admin-hub` concerns, `applications/edge-ingress.nix` moves to `modules/flake/_edge/edge-ingress.nix` (relative paths recomputed for the deeper location), `applications/dj/{default,engine-dj}.nix` move to `modules/flake/_dj/`, and `providers/oci/default.nix` moves verbatim to `modules/flake/_oci/default.nix`. `services/` stays the explicit incremental-conversion backlog
- the temporary import-tree filter shrinks from four entries to exactly `hosts` and `services` (`modules/flake/_unconverted-nixos-dirs.nix`); `hosts` stays excluded until Stage 8 converts host assemblies into discovered contributors, and `services` remains the recorded backlog
- edge-role projection is harvested into the `edge` aspect (S7-7): routes, primary domain, ACME identity, and Authenticated Origin Pulls derive from `policy/web-services.nix` plus the repo CA certificate, gated on `role == "edge"` so an origin host renders no routes and a non-web host cannot force policy values. Cockpit harvests only the common service-user wiring and the common service-user secret registration, kept behind the conventional `secrets/hosts/<hostName>/system.yaml` existence gate. `normalize-fleet-boundaries` topology, CI generation, ntfy publisher, OIDC registry, adopted-host, and test-hygiene work is explicitly deferred to Stage 8 or independent product changes; `open-webui`, the unmerged iTunes/NML variants, the pre-merge OmniRoute variants, and the deployment tasks of `omniroute-home-forge`/`fix-paperless-group-seed-environment` are not absorbed
- `admin-hub` and `identity-provider` are policy co-selection (D-050): `identity-provider` reads `applications.admin` (owned by `admin-hub`) and `services.identity.oidc` (owned by `identity-client`) through config without importing either, and `admin-hub` writes `services.admin.kanidm.*` owned by `identity-provider`. `la-admin-1` selects all three, so placement stays explicit; a lone selection fails evaluation loudly rather than silently reconfiguring a sibling. No new transitive aspect selection, compatibility bus, or `mkForce` workaround is introduced (D-059 retired the bundle: the OIDC contract is intrinsic and no aspect owns it)
- behavior is frozen for the conversion: no product, route, secret path/readership, permission, unit, package, backup, worker, provider, or deployment-topology change, and no `secrets/**`, `.sops.yaml`, recipient, ciphertext, flake-input, or `flake.lock` edit. Validation realizes `la-admin-1` and `home-forge`: structured observables are identical to the Stage 6 baseline apart from source provenance plus two classified deltas (the tmpfiles rule _order_, whose multiset, per-path sequences, and every descendant/ancestor relation are preserved, and the LA cockpit secret `owner`/`group` names, which sops-nix resolves to the same uid/gid 0). The realized closures change 20 store objects on `la-admin-1` and 8 on `home-forge`; each is enumerated and classified (the flake-source path; the toplevel/`etc`/`tmpfiles.d`/unit/trigger objects derived from it; an inert `environment.systemPackages` order swap whose `system-path` output is byte-identical; the LA sops manifest and Caddyfile, both identical modulo the source path). Because `nix store diff-closures` reports only added/removed names and size deltas, it is paired with a requisite-set comparison (`nix-store -q --requisites` + `comm`) and per-object content checks rather than used as the sole closure gate. `oci-melb-1` is verified by full evaluation, structured observables, and a derivation JSON that is structurally identical modulo store-path hashes, because no aarch64 builder or emulator is available. The change is implementation-complete but not deployed and not archived

Rationale:

- after Stage 6 the placement surface was still split: the registry owned foundation/operational/identity/DJ/music aspects while hosts imported applications, providers, and workload services directly, so adding a deployed product was inconsistent with adding a converted one
- the thirteen boundaries follow the observable placement matrix rather than a one-aspect-per-file ritual or a host-role mega-aspect: Cockpit, edge roles, identity clients, and per-product placement already differ across hosts, and the coupled LA admin remainder has no real internal placement difference
- relocating the implementations beside their concern owners makes source ownership and deployment granularity genuinely independent (D-050) and removes the last evaluator-class taxonomy, while keeping `services/` filtered preserves the explicit migration backlog instead of forcing a wholesale conversion

Supersedes/updates:

- supersedes the Stage 6 "four-root filter" statement and the "Stage 8 converts hosts; applications/providers/platform/workload conversion remains deferred" framing in `docs/dendritic-transition-analysis.md`, `docs/context-history.md`, `docs/plan.md`, `docs/architecture.md`, `STRUCTURE.md`, `ARCHITECTURE.md`, and `CONVENTIONS.md`; D-050's source/deployment separation, support-module classification, and composition modes and D-051/D-052's private-path conventions remain in force
- supersedes D-050/D-051's `applications`/`providers` retention in the temporary boundary; their historical bodies are unchanged

References:

- `openspec/changes/dendritic-stage-7-placement-aspects/{proposal,design}.md` (S7-1-S7-11) and its five delta specs
- `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, `docs/context-history.md`, `docs/dendritic-transition-analysis.md`

## D-054: Identity consumes admin directionally; admin capabilities decompose into self-contained placement aspects

Status: Accepted

Decision:

- capability independence follows a revised boundary criterion: independent placement is sufficient but not necessary for a separate aspect; security ownership (who may read which secret), lifecycle (enable/upgrade/recover independently), portability (can move hosts without sibling rewiring), and independently evaluable contracts justify separate aspects even when capabilities are currently co-located. Convenience bundling is not a justification; a multi-service composition exists only where shared implementation or aggregation behavior is intrinsic
- `admin-hub` and the `applications.admin` namespace are removed with no replacement bundle and no compatibility wrapper. Termix, Vaultwarden, Homepage, Gatus, Beszel hub, and Webhook are self-contained placement aspects selected individually; Cockpit moves to canonical web policy inputs; the residual `/srv/data` operator ACL/reconcile unit and Quantum SSH secret registrations are explicit `la-admin-1` host-local configuration
- `identity-provider` solely owns Kanidm runtime, provisioning, provider data paths, and the client-keyed OIDC provisioning secret-source map; `identity-client` and `identity-provider` both read the canonical Kanidm URL from web policy and neither writes the other's namespace; admin workloads consume the identity-client contract and never configure the provider (D-059: the contract is intrinsic, imported by its consumers, and the capability is `kanidm-host-auth`)
- the mandatory `admin-hub`/`identity-provider`/`identity-client` policy co-selection on `la-admin-1` is dissolved; LA host policy selects the capabilities it wants and real cross-aspect dependencies fail through named contract assertions, not missing-option errors (D-059: the OIDC contract is intrinsic and the capability is `kanidm-host-auth`)
- Quantum is recorded as removed from the active module graph and deferred: `modules/flake/admin-hub.nix`, `modules/hosts/la-admin-1/quantum.nix`, and `modules/services/admin/quantum.nix` were deleted by this change, so Quantum is not force-disabled in composition and not an extraction or completion gate; the Quantum SSH registrations survive only as `la-admin-1` host-local debt. Any re-enable lands as a self-contained concern/aspect consuming canonical identity contracts and never restores admin-hub coupling

Supersedes/updates:

- supersedes D-053's `admin-hub` placement aspect, its `applications.admin` enablement flag, its "discovered publication set is exactly twenty-eight" count, and the mandatory co-selection of `admin-hub`/`identity-provider`/`identity-client` on `la-admin-1`; D-053's placement-surface completion, source relocation, and validation history remain in force (D-059 later retired the `identity-client` bundle itself)
- narrows D-050's policy co-selection interpretation: co-location alone no longer justifies the mode; only security ownership, lifecycle, portability, or independently evaluable contracts (or explicit shared placement policy) does; D-050's source/deployment separation and composition-mode framework remain in force
- updates the current-state aspect enumeration and counts in `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, and `docs/dendritic-transition-analysis.md`; `docs/context-history.md` receives an appended entry; historical decision bodies are unchanged

References:

- `openspec/changes/decouple-identity-admin-capabilities/{proposal,design}.md` (IDB-1-IDB-4) and its four delta specs
- `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, `docs/context-history.md`, `docs/dendritic-transition-analysis.md`

## D-055: State backups and cache publication are independent operational aspects

Status: Accepted

Decision:

- the combined `backups` aspect is deleted with no compatibility bundle; restic mutable-state recovery and Niks3 closure publication are separate placement aspects: `state-backups` (owns `modules/services/state-backups.nix`, the derived `shrublab-backup-<host>` bucket convention, and the host secret gate for restic) and `cache-publisher` (owns the upstream `niks3-auto-upload` module import, the private upload-client and post-deploy leaves, the typed `withSystem` `nix-path-filter` injection, and the host secret gate for publication) (paths now `modules/backups/state-backups.nix` with its declaration surface in `modules/backups/state-backups/_consumer.nix`, and `modules/cache/cache-publisher/`, whose siblings `upload-client.nix` and `post-deploy.nix` replaced the private leaves)
- both aspects derive their own `hasHostSecrets` gate from the conventional `secrets/hosts/<host>/system.yaml` path (two-step sops bootstrap preserved per capability) and assert the notify-owned `services.notification-daemon.monitor.enable` option without importing `notify` (D-049 monitoring convention)
- all three hosts co-select `aspects.state-backups` and `aspects.cache-publisher` explicitly in the registry; neither aspect imports the other and no sibling public-aspect import exists
- the private Niks3 leaves stay beside their owner under `modules/flake/_backups/` per D-051 — this change performs no source-folder relocation
- Stage 8 (`dendritic-stage-8-host-identity-contracts`) owns the canonical host IDs and the `niks3Write` internal-contract migration of the `cache-publisher` upload client; this change deliberately preserves the literal Niks3 endpoint/credential flow

Supersedes/updates:

- supersedes D-049's combined `backups` operational-aspect composition (the D-049 monitoring and builder-access guarantees remain in force, now carried by the split aspects)
- updates the aspect enumerations in `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, and `docs/plan.md` from three to four operational aspects

References:

- `openspec/changes/split-state-backups-cache-publication/` (OPSPLIT-1..4)

## D-056: Canonical host identity, discovered host contributors, and internal transport contracts

Status: Accepted

Decision:

- host identity is a typed record: each host declares `nixos.hosts.<id>` from its own discovered contributor `modules/hosts/<host>/default.nix`, owning the target system, the Tailscale identity (`hostname` plus a `tailnetSuffix` read from the single suffix authority), the deferred NixOS composition (`composition.extraModules` / `.aspects` / `.fragments`), and its reimage bootstrap metadata. The schema and the generic materializer (`inputs.nixpkgs.lib.nixosSystem` per record) live in `modules/flake/host-registry.nix`, which names no concrete host. Duplicate host IDs, malformed IDs, ID/key mismatches, duplicate Tailscale identities, and missing required fields fail closed with named `host-registry:` errors
- hosts are discovered contributors: `hosts` left the import-tree exclusion, every host-private NixOS fragment and disko layout is underscore-private (`_nixos.nix`, `_disko-*.nix`, `_cockpit-auth.nix`, `_admin-runtime.nix`), and `facter.json` keeps its name because its path is a host-derivation input. `modules/flake/registry.nix` is reduced to the `flake.bootstrap.nodes` projection over `config.nixos.hosts` (with `hostName` and `flake` derived from the record key); the transitional loader and the concrete `nixos.configurations` table are deleted. The import filter is exactly `[ "services" ]`
- deploy and web metadata reference canonical host IDs and fail on unknown references ("reference, do not merge"): `modules/flake/deploy.nix` validates node keys, `edgeHost`, and `deployOrder` entries against declared IDs (`deploy: unknown host reference '<name>' is not a declared canonical host ID`), while `lib/deploy/hosts.nix` keeps owning every physical SSH/deploy fact; `modules/flake/web-policy.nix` validates web-policy host keys against declared IDs and every host-backed origin FQDN against the matching record's derived `tailscale.fqdn` (host-backed = the origin carries the tailnet suffix), while externally managed public names and `127.0.0.1` loopback origins stay literal
- the tailnet suffix has exactly one authority, `policy/globals.nix` `tailnet.suffix`, read by the host records and by `policy/web-services.nix`; `policy/web-services.nix` remains plain data so its module, script, and test consumers are unchanged
- exactly two internal transport contracts exist (`modules/fleet/internal-contracts.nix`): the shared PostgreSQL substrate and the private Niks3 write API. Each declares a provider host ID, a port, and the resolved private endpoint (`host`/`fqdn`/`url`); consumers read `config.repo.internal.*` instead of restating a provider literal, and three named checks fail closed — unknown provider host, provider host that does not enable the required capability, and declared-port drift against the port the provider actually listens on. Identity (Kanidm) and ntfy deliberately remain web-catalog contracts (`repo.web.catalog`) and MUST NOT gain an internal contract; `tests/check-internal-contracts.sh` pins the contract surface to exactly those two
- settled concerns moved into semantic domain paths while `modules/flake/` retains materialization: `modules/identity/` (the two `identity-client` contributors plus `identity-provider`), `modules/notifications/` (`notify`, `push-server`), `modules/cache/` (`state-backups`, `cache-publisher`, `niks3-cache`, with the private Niks3 leaves under `modules/cache/_backups/`), `modules/music/` (`music`, `dj`, with `_dj/`), `modules/admin/` (`cockpit`, `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`), `modules/edge/` (`edge` + `_edge/`), `modules/oci/` (`oci` + `_oci/`), and `modules/fleet/` (the internal contracts). `state-backups` later moved out of `modules/cache/` to `modules/backups/state-backups.nix` with its declaration surface in `modules/backups/state-backups/_consumer.nix`, so registration evaluates without the aspect. `modules/flake/` keeps `registry.nix`, `host-registry.nix`, `deploy.nix`, `packages.nix`, `dev.nix`, `scaffold.nix`, the support quartet (`provenance`, `oci-images`, `fleet-packages`, `web-policy`), the foundation aspects `base`/`shell`/`networking`/`tailscale` with `_aspects/`, `_builder-access/`, and the remaining placement aspects. Aspect names are unchanged and discovery still reaches every contributor (D-059 renamed `identity-client` to `kanidm-host-auth` and moved the OIDC contract to the intrinsic `modules/identity/_oidc.nix`)

Supersedes/updates:

- supersedes the typed `nixos.configurations.<host>` registry records and the `hosts` import-tree exclusion introduced by D-047 Stage 1; the concern-owned contributor model (D-050), the multi-contributor single-aspect merge (D-051), and the placement surface (D-053, D-054) remain in force
- supersedes D-055's path statement that the private Niks3 leaves live under `modules/flake/_backups/` — they now live under `modules/cache/_backups/`; the `state-backups`/`cache-publisher` split itself remains in force, and D-055's literal-endpoint clause is discharged by this decision's Niks3-write contract
- updates the current-state path and layout statements in `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, and `docs/context-history.md`; historical decision bodies are unchanged

References:

- `openspec/changes/dendritic-stage-8-host-identity-contracts/` (HIC-1-HIC-5)
- `modules/flake/host-registry.nix`, `modules/flake/registry.nix`, `modules/flake/deploy.nix`, `modules/flake/web-policy.nix`, `modules/fleet/internal-contracts.nix`, `policy/globals.nix`
- `tests/check-internal-contracts.sh`, `tests/check-dendritic-scaffold-contract.sh`

## D-057: Tracked-only provenance and the Git-tree flake reference form

Status: Accepted

Decision:

- `environment.etc."nixos-source".source = self.outPath` stays as written, and every local reference to this repository's flake uses the Git-tree form (`.#` / `.#<output>`): the `justfile` recipes, the workflow files, `scripts/resolve-host-config.sh`, the documented cutover command, and the `flake.bootstrap.nodes.<host>.flake` projection consumed by `nixos-anywhere`. The published copy is therefore the tracked configuration set (~5.5 MB) instead of the raw working directory (440 MB, including `.git`, `opentofu/**/.terraform`, `.hp-forge-esp-backup`, editor caches, and the plaintext `mTLS.key`, `secrets.auto.tfvars`, and `terraform.tfstate` files)
- tracking is the single filtering authority: no `lib.fileset`, `cleanSourceWith`, or `filterSource` call is added, and the temporary exclusion list written during this change's first pass is deleted. `lib.fileset.gitTracked` is unusable for a `path:`-resolved flake by design, `lib.fileset.toSource` is `cleanSourceWith` underneath, and filtering a store path would name the copy against the unfiltered hash and rebuild every host per commit
- `path:` is retained in exactly three places: contract tests that evaluate a copied tree with no Git repository (the harness's `make_copy` excludes `.git`/`.jj`, so `.#` cannot resolve) or that evaluate the working tree while injecting untracked fixtures; the `nvfetcher-refresh` validation, which must see freshly regenerated sources that may be untracked; and `scripts/export-web-services-policy.sh`, which resolves the tree rather than evaluating host configuration. Every other local reference uses `.#`
- `system.configurationRevision` is meaningful again, because `self.rev`/`self.dirtyRev` are populated for the Git-tree form; under `path:` it was `null`
- the Git index is a precondition for evaluation. Colocated jj keeps it in sync (a file is staged when jj first tracks it), but an external index command removed 19 tracked entries during Stage 8 and evaluation silently used a partial tree. `tests/check-flake-source-tracking.sh`, wired into `just checks all`, fails when a jj-tracked file is missing from the index and names the repair (`git add -A`); index-mutating Git commands (`git reset`, `git checkout`, `git stash`) are not used in this colocated repository
- project-owned agent policy — the reference-form rule, the index rule, and the delegation/apply discipline — lives in `AGENTS.md`, because `openspec update` regenerates the OpenSpec-managed integration files under `.pi/`, `.github/`, and `.opencode/` and would drop anything stored only there

Supersedes/updates:

- resolves `TD-19` (the provenance copy carrying working-directory debris) and removes the null-`configurationRevision` consequence recorded for the `path:` form
- updates the current-state statements about local evaluation and published provenance in `ARCHITECTURE.md`, `STRUCTURE.md`, `docs/architecture.md`, and `CONVENTIONS.md`; historical decision bodies are unchanged

References:

- `openspec/changes/restrict-provenance-source-copy/` (PSC-1-PSC-4)
- `modules/flake/provenance.nix`, `tests/check-flake-source-tracking.sh`, `AGENTS.md`

## D-058: The PostgreSQL substrate is a mechanism, instances, and consumer registrations

Status: Accepted

Decision:

- PostgreSQL support is split into three layers. The mechanism (`modules/services/postgres.nix`) renders provisioning from an instance declaration and a consumer registry and names no consumer and no instance; an instance is a placement aspect that imports the mechanism, with port and data directory declared by the host that runs the cluster; a consumer registers the database, role, credential, extensions, and setup SQL it needs from its own module (the mechanism is now `modules/database/postgres.nix` with the declaration-only contract `modules/database/postgres/_consumer.nix`, published as the `postgres` aspect from that same file)
- the shape follows the registrations already established in the fleet — `services.state-backups.services.<name>` and `services.notification-daemon.monitor.units.<unit>` — so a shared capability never holds a participant list
- registrations are keyed by consumer name, not by instance: the native NixOS `services.postgresql` runtime is single-cluster, so a host runs at most one cluster (a named error rather than an assumption), `instances.<name>` names that cluster for the internal contract, and a consumer stays instance-free
- a consumer's credential is part of its registration (`password = { file, key }`), which makes one file and one key authoritative for both the provider that provisions the role and the consumer that authenticates. There is no separate provider-side secret-file option, and the previously hand-synced pair for a cross-host consumer is gone
- extensions are contributed in nixpkgs' own shape — `extensions = ps: [ ps.pgvector ]`, a function of the instance's extension set — and the mechanism composes them (`ps: lib.unique (lib.concatMap (c: c.extensions ps) consumers)`), so a package always matches the server version and no central SQL-name-to-package map is needed. `pgvector.nix` carries no SQL name (it lives in `vector.control`, which exists only after the build), so a map would be hand-written policy that goes stale
- the SQL side is `setupSQL` (`types.lines`), run in the consumer's database as the superuser on every start and therefore required to be idempotent; a failure names the registration instead of aborting the cluster with an opaque error
- endpoint resolution prefers the local cluster: `services.postgres.localEndpoint` lets a co-located consumer use the host's own instance, and only a consumer whose database lives elsewhere reads `repo.internal.postgres.<instance>`. Switching a database between hosts is a registration move plus, for a cross-host move, a contract read — never a change to the service's connection code
- AudioMuse's database moved to `home-forge`, next to its compute, so same-host registration is the rule and cross-host registration (written on the provider host, which is the only host that can create the role and read the credential) is the documented exception
- cross-host registration is the one case where a provider host gains read access to a consumer's secret file; that widening is explicit in the registration and is a `.sops.yaml` decision, not an automatic consequence
- consumers that run outside this repository (for example a workstation) remain out of scope for this composition model: the consumer name is not a host ID and `allowedCIDRs` is the seam that will express them when a `nix-fleet` registration policy exists

Supersedes/updates:

- supersedes the `postgres-shared-access` requirements written around the LiteLLM consumer, which is retired
- the runbook namespace moved from `services.postgres-shared` to `services.postgres`, and `docs/runbooks/postgres-consumer-migration.md` covers moving a database between clusters
- revised by D-069: consumer roles, databases, and ownership are converged by the substrate's own provisioning unit rather than nixpkgs' `ensureDatabases`/`ensureUsers`, which could act on the previous generation's registrations

## D-059: The OIDC contract is intrinsic; capability, contract, and security binding are separate concerns

Status: Accepted

Decision:

- the OIDC contract (`services.identity.oidc.*`: provider URL, client path prefix, token URL, and the five endpoints of every enabled client, derived from `policy/identity.json` and the resolved `kanidm-admin` web-policy route) is an intrinsic module, `modules/identity/_oidc.nix`, imported by each participant that reads it — the provider leaf `modules/identity/kanidm-runtime.nix`, the capability `modules/identity/kanidm-host-auth.nix`, and the consuming leaves `modules/flake/paperless/core.nix` and `modules/flake/karakeep.nix`; `modules/admin/termix.nix` reads the same namespace through a tolerant lookup with its own named failure and therefore relies on another participant declaring the contract. It is neither a host-selected deployment aspect nor an all-host support module: it is needed only where an identity participant exists, and the underscore-prefixed fragment form (the `_consumer.nix` precedent) is the one that keeps it out of discovery while remaining importable
- this applies one boundary rule, recorded in `CONVENTIONS.md`: deployment capabilities are host-selected aspects; shared contracts and derived projections are intrinsic modules or fleet-level policy; helpers and package-family invariants are value-level support, never aspects; secret readership stays an explicit per-deployment binding even where the logical credential identity is shared
- the remaining capability aspect is `kanidm-host-auth` (Kanidm client package, `services.kanidm.client`, `services.kanidm.unix`, declared PAM login groups, SSH key integration), selected by `la-admin-1` and `oci-melb-1`. `identity-client` is retired with no compatibility alias: the aspect surface is internal to this repository and both consumers moved in the same change
- a projection MUST NOT be carried by a capability aspect. The provider leaf asserts `providerUrl == appUrl`, so the provider host had to select the client capability (the Kanidm Unix/PAM/SSH integration) merely to read a derived URL, and a consumer on a host without the aspect died with `The option 'services.identity.oidc' does not exist` — a failure `admin-module-structure` already forbids ("a missing required identity contract fails through a named assertion rather than a missing option namespace"). Both are gone: the provider consumes the contract intrinsically, the dead `services.identity.kanidm.oidc.*` mirror (which nothing in `modules/` or `tests/` read) is deleted, and a consumer whose client entry is absent now fails by name in its own leaf
- OIDC registration stays in `policy/identity.json` and is consumed from both sides; the postgres consumer-registration pattern (D-058) is not imitated, because provider and application are separate `nixosConfigurations` evaluations that cannot contribute to each other's option tree. The flake-parts alternative — a top-level identity registry fed by source contributors — would couple provisioning to source presence rather than to deployment, so explicit central policy remains the registration authority and the provider keeps its per-client credential-source map whose keys are validated against the policy's enabled clients
- the dead `mkOidcEndpoints` helper is removed rather than re-signed. It was Pocket-ID-shaped (`<issuer>/authorize`, `<issuer>/api/oidc/token`, `<issuer>/api/oidc/userinfo`) and had no call site in `lib/`, `modules/`, `tests/`, `scripts/`, or `opentofu/`; Kanidm's authorization and token endpoints are provider-level while discovery and userinfo are client-level, so a single-issuer-base signature cannot express the live shape and a wrong-shaped helper invites the next consumer to adopt it. The contract file is the single derivation site that consumers read
- the Kanidm release family is one value, `modules/identity/_kanidm-packages.nix` (`server` = the secret-provisioning wrapper, `client` = the CLI/klients package), consumed by the provider leaf and the capability; the `kanidmd domain upgrade-check` gate before a bump is unchanged
- observed boundary, pre-existing and intentional: a host may write into a contract namespace only when something in its composition imports the contract, otherwise evaluation fails loudly on the missing option. `la-admin-1` and `oci-melb-1` assign `services.identity.hostAuth.*`, which `kanidm-host-auth` declares, so dropping that aspect requires dropping the host's own assignment — the same select-then-assign coupling every capability has, and distinct from the projection coupling this decision removes
- out of scope: per-client encrypted identity credential files (recorded as `TD-25`, operator-owned), any Kanidm consumer registry, and the `tests/check-identity-contract-directionality.sh` split (`TD-11`)

Supersedes/updates:

- supersedes the `identity-client` bundle introduced by D-051 and every layout statement that named its two contributors as one aspect, annotated at D-048's staging note, D-050's multi-contributor bullet, D-053's co-selection bullet, D-054's identity bullets, and D-056's domain-relocation bullet; D-051's multi-contributor single-aspect mechanism remains in force with `cache-publisher` as its production example
- removes the `mkOidcEndpoints` requirement from `provider-owned-oidc-uris`; the contract's read-only-output requirement and the consumer-directionality requirements remain in force, and the latter is now satisfied by construction rather than by a host's placement decision
- updates the current-state statements in `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, and `docs/context-history.md`; historical decision bodies are otherwise unchanged

References:

- `openspec/changes/make-oidc-contract-intrinsic/`
- `modules/identity/_oidc.nix`, `modules/identity/_kanidm-packages.nix`, `modules/identity/kanidm-host-auth.nix`, `modules/identity/kanidm-runtime.nix`, `modules/identity/identity-provider.nix`
- `modules/flake/paperless/core.nix`, `modules/flake/karakeep.nix`, `modules/admin/termix.nix`
- `tests/check-dendritic-scaffold-contract.sh`, `tests/check-identity-contract-directionality.sh`

## D-060: flake.nix is generated; nix-fleet owns the shared baseline pins

The flake entrypoint was the last hand-maintained manifest in the repository: thirty lines of input pins with the discovery filter inline, edited by hand and by Renovate. Two consequences motivated the change. First, every input addition was a flake.nix edit rather than a module edit, so dependency ownership lived outside the dendritic tree that owns everything else. Second, this repository and nix-fleet each carried their own pin for nixpkgs, sops-nix and niks3, so the two repositories drifted independently (at the time of this decision: nixpkgs `0e251e24a4f2` from 2026-08-13 here against `20b1ddd1aa5a` from 2026-09-19 in nix-fleet).

- flake.nix is generated by `flake-file` (`github:denful/flake-file`) through its dendritic preset and regenerated with `nix run .#write-flake`. Inputs are declared in the tree: `modules/flake/inputs.nix` for the fleet-owned and shared baseline pins, and the concern contributor that owns a dependency for everything else. The generated file carries a do-not-edit header and is a build artifact of the module tree.
- `nix flake check` exposes `checks.<system>.check-flake-file`, which fails with a diff when the committed flake.nix drifts from the declarations. `--no-build` only evaluates it, so the gate is a build of that check (the verification step in CI and in `just checks all`), not the flake check alone.
- nix-fleet is the authority for the pins the two repositories share: nixpkgs, flake-parts, import-tree, sops-nix and niks3. They are declared here as follows aliases (`url = lib.mkForce ""` plus `follows = "nix-fleet/<input>"`, because an input may not carry both a URL and a follows, and the dendritic preset defaults the URLs of nixpkgs, flake-parts and import-tree). One nix-fleet revision then moves the shared baseline everywhere, and Renovate keeps two jobs instead of five: nix-fleet bumps the shared inputs on its own schedule, this repository bumps the nix-fleet revision plus its own inputs (disko, deploy-rs, nix-index-database, traktor-m3u-sync).
- The alias is structural, not a version copy: the consumer's lock materializes the followed node by resolving its ref, so a fresh resolve or a plain `nix flake update` can land on the current unstable head. `nix flake lock --update-input nix-fleet` aligns the shared nodes with nix-fleet's lock and is the documented baseline propagation.
- Local development uses `just dev nf-eval <host>`, `just dev nf-build <host>` and `just dev nf-check` (with `NIX_FLEET` pointing at any checkout, defaulting to the sibling `../nix/nix-fleet`). `--override-input` is per invocation: the committed lock is not touched, and the local checkout contributes both its code and its locked shared baseline.
- The import-tree boundary record is deleted. The generated outputs expression discovers `./modules` without a filter, so `modules/flake/_unconverted-nixos-dirs.nix` had stopped being wiring: an unconverted plain-NixOS module directory now fails loudly at discovery instead of being filtered out, and the scaffold contract asserts instead that the converted roots stay evacuated (`surviving_evacuated_roots`), so a transitional root cannot reappear unremarked.
- Adopting the baseline is not a no-op: it moved nixpkgs from 2026-08-13 to 2026-09-19, which removed `services.journald.extraConfig` (now `services.journald.settings.Journal`). The migration is in this change and is the only host-configuration delta the move required on all three hosts.

References:

- `flake.nix`, `modules/flake/flake-file.nix`, `modules/flake/inputs.nix`
- `modules/hosts/oci-melb-1/_nixos.nix` (journald settings migration)
- `tests/check-dendritic-scaffold-contract.sh`, `.just/checks.just`, `.just/dev.just`, `.github/workflows/ci.yml`
- `dendritic-stage-1-scaffold-hosts` (the hand-written manifest this replaces)

## D-061: nix-fleet owns the shared aspects; this repository keeps convention contributors

**Status:** Accepted
**Date:** 2026-09-22
**Context:** `dendritic-complete-flake-file-and-fleet-boundary` declared the nix-fleet input and flipped the shared pins so nix-fleet is the authority for `nixpkgs`, `flake-parts`, `import-tree`, `sops-nix` and `niks3`. nix-fleet also publishes six shared aspects in its own `flake.modules.nixos` namespace (`tailscale`, `beszel-agent`, `builder-access`, `niks3-cache`, `niks3-publisher`, `notification-daemon`), and four of them duplicate mechanisms this repository still carried.

**Decision:** consume a shared aspect through exactly one local convention contributor:

- The contributor publishes our aspect name, imports `inputs.nix-fleet.modules.nixos.<aspect>`, and supplies the fleet's conventions — the host-scoped secret path (`secrets/hosts/${config.networking.hostName}/system.yaml`), the values `policy/globals.nix` holds, and the bindings that keep host records unchanged. The shared module owns the mechanism: service wiring, option declarations, fail-closed assertions, secret registration, unit ordering.
- Aspect names are ours. An upstream file name does not constrain the name we publish, so host records, `CONVENTIONS.md`, and the scaffold contract keep the fleet's names (`observability-agent` consumes `beszel-agent`; `cache-publisher` consumes `niks3-publisher`).
- Equivalence is judged per host on structured observables — option values, `sops.secrets` entries, systemd unit wiring and ordering — never on derivation equality, because the published source set changes whenever a file is added or removed.
- An input repository's aspects do not enter our `flake.modules.nixos` namespace, so the bridge file is required even when the names match; a nix-fleet rename buys only cosmetic symmetry.
- The import-tree boundary record (`modules/flake/_unconverted-nixos-dirs.nix`) is deleted rather than kept as an empty record: the generated `outputs` discovers `modules/` unfiltered, and the scaffold contract now asserts the converted roots stay evacuated, so a transitional root cannot reappear unremarked.

**Consequences:**

- Four aspects moved in this change: `tailscale`, `builder-access`, `observability-agent` (→ `beszel-agent`), `niks3-cache`. Measured per host across 1225/982/1105 value leaves, the only deltas are the intended ones: the `beszel-agent` option namespace, `services.builder-access.hosts` becoming bound, upstream's `ControlPath /tmp/builder-access-%r@%h:%p` socket name in the nixbuild SSH block, and `secretFiles.apiToken` replacing our `hostSecretFile`.
- `cache-publisher` and `notification-daemon` stay open (TD-26). Our `cache-publisher` is not only a client: it suppresses upstream's post-build hook and pushes the filtered closure at activation, which covers closures built off-host (CI via nixbuild.net); migrating to nix-fleet's per-build hook is correct when every builder runs the publisher and CI-built closures need not stay published. Our `notify` carries the daemon body and monitoring composition, so its mechanism half must move upstream before the aspect can be consumed.
- Extraction candidates in the other direction are recorded as TD-27 (`networking`, `base/foundation`, `provenance`, `host-recovery`).

References:

- `flake.nix`, `modules/flake/inputs.nix`
- `modules/flake/tailscale.nix`, `modules/flake/builder-access.nix`, `modules/flake/observability-agent.nix`, `modules/cache/niks3-cache.nix`
- `tests/check-dendritic-scaffold-contract.sh`
- `CONVENTIONS.md` (`### Shared Aspect Consumption`), `AGENTS.md` (`### Shared Aspects from nix-fleet`)
## D-062: Private service endpoints are policy declarations; the internal-contract registry is retired

**Status:** Accepted

**Context:**

D-056 introduced `modules/contracts/internal.nix` (HIC-4): a typed registry declaring two cross-host transports (shared PostgreSQL, private Niks3 write API) with provider host ID, declared port, a capability path, and a listen path. It resolved `repo.internal.*` per host and validated, by evaluating the provider's configuration, that the provider enables the capability on the declared port.

Two developments shrank what that registry carried:

- **The PostgreSQL half became dead weight.** D-058 moved the fleet to per-host clusters with a consumer registry, and AudioMuse's database moved to the same host as its compute. The surviving consumer path was a fallback (`localPostgres != null` in `modules/music/music.nix`) that can no longer fire, because the only host that composes the music application also runs the cluster.
- **One live endpoint remained.** The Niks3 write API is the only contract with a consumer. Keeping ~300 lines of reflective machinery — `capabilityPath`, `listen.{path,kind}`, cross-host configuration traversal, a 260-line contract suite, a flake output — for one endpoint is disproportionate.

Meanwhile the web policy had already absorbed the relevant facts. `policy/web-services.nix` distinguishes published from private services (`exposureMode = "tailscale-only"`, `declarePublic = false`) and already carries the private endpoints (bifrost, phoenix, webhook-admin). The second registry duplicated a decision the first one could express.

**Decision:**

- A private service is declared **once** in `policy/web-services.nix`. The resolved catalog projects it as `repo.web.catalog.<id>.endpoint = { scheme, host, port, url }` with `publicUrl` and `publicHost` set to `null` — a service that is never published must not manufacture a public identity.
- A published service never exposes its origin host: the catalog carries its public identity (public URL/host, access, health) and the published upstream *shape* (`upstreamScheme`, `upstreamPort`) only. The edge remains the sole consumer of the full `repo.web.hosts` resolution, which carries origins.
- The declaration is the **single source for both sides** of a private transport: the provider derives its listen address from `endpoint.port` (e.g. `services.niks3-cache.httpAddr`) and every consumer dials `endpoint.url` (e.g. `services.niks3-publisher.serverUrl`). Declared-port drift is therefore unrepresentable rather than checked.
- The generic provider-capability introspection is retired with the registry. Its one surviving invariant — the host named as the private endpoint's origin is the host that renders the provider — is asserted as a concrete fleet check in `tests/check-web-service-catalog.sh`, not resurrected as a reusable abstraction.
- Cross-host relationships remain fleet-level policy. This refines D-059's rule (support machinery is never an aspect, and cross-host facts cannot be a per-host NixOS module option) rather than contradicting it: the policy file is the appropriate authority precisely because the relationship exists above any single host evaluation.

**Consequences:**

- `modules/contracts/` and `tests/check-internal-contracts.sh` are deleted; the `internal-contracts` aspect is removed from all three host records; `repo.internal.*` and `flake.internalContracts` no longer exist.
- `modules/music/music.nix` keeps no remote PostgreSQL fallback. A host that enables AudioMuse without a local cluster fails through a named assertion (`applications.music.audiomuse is enabled but no PostgreSQL endpoint is available…`) instead of silently dialing a remote endpoint.
- The `niks3-write` entry is listed under the edge host's service key, which for a service with no ingress route is a mild oddity. It is tolerated deliberately: the hosts axis means "the ingress host that owns this service topology", and redesigning the policy into `services/` + `ingress/` for one entry is a larger refactor than the oddity costs.
- Two honest deltas: the publisher's rendered target on a non-provider host becomes the provider's FQDN (`http://oci-melb-1.<tailnet>:5751`) instead of its short hostname — same host, resolvable under MagicDNS, and consistent with every other resolved endpoint — and the provider-capability invariant is now a fleet check rather than an architectural guarantee, so a host that stops rendering the cache server fails the check rather than the evaluation.
- The file name `policy/web-services.nix` undersells its content (it now describes public routes, private endpoints, health, and access). Renaming it is deferred: it is consumed as text by `scripts/export-web-services-policy.sh` and OpenTofu and compared byte-for-byte by tests, so the rename carries churn without changing semantics.

References:

- `policy/web-services.nix`, `lib/policy.nix` (`mkCatalogEntry`, `isPublicService`), `modules/web/web-policy.nix`
- `modules/cache/cache-publisher.nix`, `modules/cache/niks3-cache.nix`, `modules/music/music.nix`
- `tests/check-web-service-catalog.sh`
- `docs/decisions.md` D-056 (the registry this retires), D-058 (per-host clusters), D-059 (support machinery is not an aspect)

## D-063: The private upstream transport is policy-declared and provider-rendered; the identity provider owns its TLS

**Status:** Accepted

**Context:**

Moving the Caddy edge from `la-admin-1` to `oci-melb-1` was a routing change for nine services — plain-HTTP upstreams the edge now dials directly over the tailnet — and a structural failure for one. The Kanidm provider's socket is loopback-bound and TLS-only, and its configuration assumed the edge was co-located: it read the edge's ACME certificate, joined the `caddy` group only the edge role creates, and ordered itself after a reverse proxy its host no longer ran. The first two surfaced as a failed activation (`kanidm.service` exiting at spawn with an unresolvable supplementary group); the third would have surfaced as a silent identity outage once the borrowed certificate stopped renewing.

**Decision:**

1. `exposureMode` is the single axis describing how a route is exposed, and it is required on every route: `tailscale-upstream` (published; the edge dials the origin's tailnet-bound socket), `tailscale-serve` (published; the providing host renders the front the edge dials), `tailscale-only` (not published), with `direct` reserved for an edge-local loopback upstream. The served mechanism joins that vocabulary as a value rather than a second field, because the field already distinguished cross-host reachability — a parallel transport field would have written the same fact twice.
2. The provider host renders the front the edge dials, from a provider-side projection (`repo.web.originServices`) rather than the edge's route table, which does not carry the services a non-edge host provides. All transport-specific code lives in one contributor beside the ingress aspect, so the transport is replaceable in one file and no service module learns how the private network exposes it.
3. The front terminates the private network's own certificate and dials the service's loopback socket on the same port, so serve port = policy port = bind port and the port-drift property survives; nothing validates the inner pair, because its security boundary is localhost rather than PKI.
4. The identity provider owns its TLS material: a self-signed pair generated on first start under its state directory, with the certificate paths left host-overridable for a future fleet CA. Its public identity (`appUrl`, issuer, discovery) is unchanged.

Rejected: a host-facing `services.privateExposure.*` namespace (it would restate the port and reachability policy already declares, recreating the registry D-062 retired — the replaceable seam is a file, not an option surface); `tailscale cert` plus a tailnet bind (the operator then owns renewal, and the service acquires a second name for one identity); keeping ACME on the provider (the Cloudflare DNS-01 credential would move to a workload host); a fleet VPN abstraction with a backend discriminant.

**Consequences:**

- Edge placement stops being implied by who provides a route: the same policy table serves any edge, and a provider renders whatever its own routes need.
- A private-transport route is validated at evaluation — unknown transports, a non-FQDN origin, a host fronting itself, and per-route TLS overrides on a private transport all fail closed with the route named.
- Two bespoke fronts predate this mechanism (`modules/admin/cockpit/tailscale-serve.nix`, `modules/admin/termix.nix`); they are recorded as debt (TD-29) rather than migrated alongside a live cockpit.

References:

- `policy/web-services.nix`, `lib/policy.nix` (`providedServices`), `modules/web/{web-policy,ingress-origin-exposure}.nix`
- `modules/identity/{identity-provider,kanidm-runtime}.nix`
- `tests/check-dendritic-scaffold-contract.sh`
- `docs/decisions.md` D-062 (private endpoints are policy declarations), D-058 (per-host clusters)

## D-064: Web policy declares placement, not dial addresses; each consumer derives transport by its own policy

**Status:** Accepted

**Context:**
The ingress cleanup exposed a general defect: routes carried `origin.host` as a hand-composed tailnet FQDN (and, earlier, loopback literals), so placement topology lived in policy data *and* in every consumer that read it. Independently placeable services — the Niks3 write endpoint, Bifrost's gateway, any future workload move — required editing consumers or host files whenever a provider moved, and a colocated provider looked identical to a remote one.

**Decision:**

1. Routes declare `origin = { scheme; provider; port; }` — `provider` is a canonical host ID from the host records, never an address. Validation fails closed on unknown or missing providers, and a `direct` route additionally must have the policy host as its provider (edge-local means edge-local).
2. The two consumers of placement derive transport differently, over the same fact. The **ingress upstream** is exposure-driven: `direct` loops back; `tailscale-upstream` and `tailscale-serve` dial the provider's FQDN even when provider and edge coincide, because both sockets (origin and serve front) are tailnet-bound — verified against live listeners before adopting (the serve fronts bind the tailnet IP only). The **machine-to-machine `endpoint`** is locality-driven: a private service colocated with the host evaluating the catalog resolves to loopback, otherwise to the provider FQDN; a served endpoint is always reached by name. One resolver file (`lib/policy.nix`), two rules, one placement declaration.
3. Identity never derives: public URLs, OIDC endpoints, and TLS server names stay literal in the policy, so colocation can never rewrite what a client trusts.

Rejected: a locality rule for ingress upstreams — it would loop back a colocated `tailscale-upstream` route against its own declared semantics and break the bespoke cockpit front, a tailnet listener. Rejected: a generic service-discovery registry or a new option namespace — `policy/web-services.nix` already holds every placement, and cross-host registration cannot be expressed as per-host module options anyway (D-059). The postgres `localEndpoint` pattern stays separate: same shape, different contract (typed ports and credentials).

**Consequences:**

- Moving the edge or a workload is one placement edit; no consumer, host file, or route literal changes. The catalog's machine endpoint now reads `http://127.0.0.1:5751` on the colocated publisher and the provider FQDN everywhere else, with no publisher code involved.
- The catalog contract's placement test pins provider IDs against the host records instead of parsing FQDN suffixes.

References:

- `policy/web-services.nix`, `lib/policy.nix` (`upstreamHost`, `endpointHost`), `modules/web/web-policy.nix`
- `tests/check-web-service-catalog.sh`, `tests/check-dendritic-scaffold-contract.sh`
- `docs/decisions.md` D-062 (policy as the endpoint SSOT), D-063 (exposure axis), D-059 (cross-host facts are not module options)

## D-065: Machine identity and build capacity live in the fleet registry; the realization is consumer-constructed

**Status:** Superseded by D-066 for registry ownership — the facts moved upstream into nix-fleet's inventory; the scheduling-off decision and the beszel-agent consequence stand

**Context:**
nix-fleet replaced its `services.builder-access.hosts` trust module with a typed fleet registry (`fleet.hosts` / `fleet.builders` / `fleet.builderSets`) plus a NixOS realization constructed from that registry, and its hosts contract asks a consumer's own host registry to derive identity — system, tailscale hostname, host key — from it rather than restating it. This repository held the same facts twice (the host records, and an SSH-trust binding naming one external builder) and declared no host keys at all, so nothing could dial a fleet host as a builder.

**Decision:**

1. `fleet.hosts.<id>` is the machine-identity SSOT — target system, tailscale hostname, known-hosts names, and the host's SSH host public key — declared per host beside its canonical record. `nixos.hosts.<id>` derives `system` and `tailscale.hostname` from it and keeps this fleet's own concerns: the tailnet suffix authority, composition, and bootstrap metadata.
2. `fleet.builders` declares each host's build profile (systems, `maxJobs`, `speedFactor`, supported features) from observed capacity, and `fleet.builderSets.ci` names the capacity CI may draw on. Both live in `modules/flake/builder-access.nix` — the aspect's contributor — because participation and scheduling are fleet policy rather than host data.
3. Scheduling stays off: `services.fleet-builders.activeSet` is null on every host, so selecting the aspect yields trust (known-hosts entries and client tuning) without `nix.buildMachines`. The fleet builds in CI, which coordinates builders by architecture; local iteration builds on the workstation. A host that should offload to a peer sets `activeSet` in its own host-private composition.
4. The realization is **consumer-constructed**: importing nix-fleet's flake-level `flakeModules.fleet-builders` builds `flake.modules.nixos.fleet-builders` inside this evaluation with the fleet registry closed over, and our aspect imports that. Importing `inputs.nix-fleet.modules.nixos.fleet-builders` would bind nix-fleet's own inventory — measured, not assumed: the first attempt resolved the rendered trust entries to nix-fleet's fixture hosts.

**Consequences:**

- One hostname/system/host-key declaration per host; the registry renders trust for all three hosts, and the CI bundle (`packages.ci-builders`) renders the machines file, known-hosts and ssh client config from the same inventory.
- `nix flake check` now carries the shared `checks.registry-render`, which fails closed on an invalid registry: an unknown builder-set member, a builder that does not set exactly one of `host`/`uri`, or a builder referencing a host absent from `fleet.hosts`.
- The beszel-agent swap that arrived with the same pin bump retires the per-host agent token entirely: the shared module registers only the fleet-wide key, owns the unit's failure registration itself, and the local contributor is a two-field secret binding. The host-scoped secrets file remains the enrollment gate.

References:

- `modules/flake/builder-access.nix`, `modules/hosts/*/default.nix`, `modules/flake/observability-agent.nix`
- `tests/check-dendritic-scaffold-contract.sh`, `CONVENTIONS.md`, `AGENTS.md` (shared aspects)
- `docs/decisions.md` D-056 (canonical host records), D-061 (shared aspects and convention contributors)

## D-066: nix-fleet owns the canonical fleet inventory; this repository derives from it

**Status:** Superseded by D-068 for the consumption shape — nix-fleet v2 deleted the cross-class realization and publishes facts plus pure projections; the inventory-ownership decision stands

**Context:**
D-065 made this repository's host records the machine-identity SSOT and had nix-fleet render trust from that registry. nix-fleet then moved the facts themselves upstream: `modules/fleet/inventory.nix` now declares the canonical `fleet.hosts` (target system, Tailscale hostname, host names, host public key), `fleet.builders` and `fleet.builderSets` — including this fleet's three hosts — and publishes the whole surface as one flake-level module (`flakeModules.fleet`) with the realization at `config.fleet.realization`. Its contracts are explicit: a canonical fact is declared in nix-fleet and consumers derive, never restate; consumer additions are additive and may not shadow canonical IDs.

**Decision:**

1. This repository declares no machine identity, builder participation or builder set. The host contributors drop their `fleet.hosts.<id>` records (host keys included) and keep only the derivation — `system` and `tailscale.hostname` come from `config.fleet.hosts.<id>` — plus what is ours: composition, disks, bootstrap metadata, and the tailnet suffix authority.
2. The host registry enforces the join-key rule with a named error: a `nixos.hosts.<id>` record with no canonical `fleet.hosts.<id>` entry fails as `host-registry: host '<id>' has no canonical record in nix-fleet's fleet inventory` instead of a bare missing-attribute error.
3. `modules/flake/builder-access.nix` consumes the canonical inventory and publishes our aspect as the realization constructed in this evaluation. The scaffold contract ratchets the boundary by failing on any local `fleet.hosts` / `fleet.builders` / `fleet.builderSets` declaration.
4. Host keys bind upstream: nix-fleet's inventory carries each host's `publicKey`, read from that host's own `/etc/ssh/ssh_host_ed25519_key.pub` and verified live against it (never from a scan). Trust renders for every record carrying a key, and a builder backed by a keyless host fails closed upstream when scheduled, so trust never implies reachability.
5. **Resolved (was TD-31):** `flakeModules.fleet` was published as a pre-evaluated module value, which bound the provider's evaluation — measured, not assumed: `config.fleet.*` stayed empty here while the feature's CI bundles were byte-identical to nix-fleet's own drvs and `config.fleet.realization` rendered nix-fleet's inventory (`builder-fixture-external`, `builder-nixbuild`, `host-fixture-host`). nix-fleet now publishes the feature as a module function that imports its inventory, so the contributor is `imports = [ inputs.nix-fleet.flakeModules.fleet ]` plus `imports = [ config.fleet.realization ]`, and the consumer receives the schema, the inventory, the fail-closed validation, the CI bundles (`packages.ci`/`fixture`) and `checks.fleet-render`.

**Consequences:**

- The canonical facts have one authority. A host's system, Tailscale hostname, host key and build profile change in nix-fleet's inventory, and this repository picks them up on its next pin bump.
- Trust is currently thinner than the inventory: only `builder-nixbuild` renders a known-hosts entry until the three host keys are harvested upstream. The scaffold probe asserts exactly that set, and its end-to-end key check pins the external builder's canonical key.
- `packages.ci` / `packages.<set>` are absent from this repository's outputs until the CI adoption (TD-30) installs them from the fixed feature; the interim deliberately does not import the feature, so no fixture-bound package can leak into our namespace.
- The aspect name stays `builder-access`: aspect names are per-repository, so our contributor keeps publishing it and host records keep selecting it unchanged.

References:

- `modules/flake/builder-access.nix`, `modules/hosts/*/default.nix`, `modules/flake/host-registry.nix`
- nix-fleet `docs/contracts/hosts.md`, `docs/contracts/builders.md`
- `docs/decisions.md` D-060 (generated flake and follows aliases), D-065 (the previous, now superseded, registry ownership)

## D-067: The Bifrost gateway is product-named, host-networked, and pinned at v2.2.1

**Status:** Accepted
**Date:** 2026-09-22
**Context:** `ai-gateway` was the only role-named placement aspect in a fleet of product-named
ones, and its deployment still carried the BG-1 container decision behind a config and module
shape that had drifted from the fleet's conventions (published port bypassing the firewall, an
omitted `config_store` key papered over by a boot-time deletion, no dashboard auth). The upstream
flake at its own latest release tag (v2.2.1, 2026-09-18) still fails to build its UI package
(`npmDepsHash` mismatch against its own lockfile), pins nixpkgs `staging-next`, carries a Go 1.27
overlay workaround, and patches a UI file the Vite migration deleted — the container boundary from
BG-1 holds.

**Decision:**

- the aspect is renamed `bifrost` and moves to the `modules/ai/` domain (`modules/ai/bifrost.nix`
  owner plus the `modules/ai/bifrost/service.nix` sibling contributor). The option namespace
  (`services.bifrost-gateway` → `services.bifrost`), the secret file (`bifrost-gateway.yaml` →
  `bifrost.yaml`), and the policy data (`globals.aiGateway` → `globals.bifrost`) follow the aspect
  name; the unconsumed `globals.services.bifrost-gateway` defaults block is deleted
- the image pin moves to v2.2.1 tag + digest; the v2.0.0 breaking changes are audited and none
  apply (no custom plugins, no admin-API callers, no cost/observability integrations)
- file-driven mode becomes real: `policy/bifrost-config.json` states `config_store.enabled = false`
  and the render unit no longer deletes `config.db` on boot
- the dashboard and management API require governance admin auth from the host secret file;
  `disable_auth_on_inference` stays false
- the container is host-networked with no published port (the hindsight/docs-mcp shape);
  `oci-melb-1` admits its default podman bridge to port 7411 so the karakeep and paperless-gpt
  containers keep reaching `host.containers.internal:7411`
- the stale `crofai_api_key` secret key leaves the template and scope

**Consequences:** the operator re-encrypts `secrets/services/bifrost.yaml` once (two admin keys
in, one dead provider key out); the karakeep and paperless-gpt consumers change one option-path
each; docs-mcp on home-forge is untouched; oci-melb-1's bridge firewall drops the stale `4533`
openings (operator-confirmed unused; the navidrome catalog route points at home-forge); `5030` on
`podman0` has no identifiable consumer and stays until the operator confirms it dead.

## D-068: nix-fleet v2 publishes facts and projections; the fleet projects trust and leaves scheduling to CI

**Status:** Accepted

**Context:**

nix-fleet restructured its fleet contract after D-066. `fleet.builders` and `fleet.builderSets`
became a capability on the machine record (`fleet.hosts.<id>.capabilities.nixBuilder`), external
resources got their own namespace (`fleet.externalBuilders`), and named sets became
`fleet.buildProfiles` with per-member overrides, because scheduling parameters belong to the
relationship between workload and builder. The cross-class realization was deleted outright: the
feature publishes facts plus pure projections (`flake.lib.buildProfile` → `resolveHosts`,
`resolveBuildProfile`, `machinesFile`, `knownHosts`, `sshConfig`, `buildMachines`), and a consumer's
own flake-level module closes over its `config.fleet`. The v1 surfaces are gone or throwing shims
(`config.fleet.realization`, `services.fleet-builders.activeSet`,
`modules.nixos.{fleet-builders,builder-access}`), and the CI bundles became `packages.<profile>`.

Two smaller upstream changes ride the same pin: the `nh-gc` aspect is renamed `nix-gc` and gained a
selectable implementation, and the Beszel agent's credential is reclassified — its `KEY` is the
hub's public key, so the module takes it as an option and registers no sops secret.

**Decision:**

1. Pin nix-fleet to v2 and consume the documented shape: `modules/flake/builder-access.nix` imports
   `inputs.nix-fleet.flakeModules.fleet` and closes over this evaluation's `config.fleet`, projecting
   trust with `inputs.nix-fleet.lib.buildProfile` (`resolveHosts` → `knownHosts`/`sshConfig`).
   Nothing is restated — the trust selection is derived from the build capability, so a host joins
   the trust set by declaring the capability upstream.
2. Scheduling stays off: no profile is resolved, so no host gets `nix.buildMachines` and no dispatch
   account is selected. CI is the build path (TD-30), and the build capability already exists as
   inventory facts the CI bundles render.
3. Trust is thinner than the inventory by construction — the projection renders exactly the
   selection, so only hosts offering build capability are known hosts. A non-builder workstation is
   identity, not a dial target.
4. The Beszel agent holds no secret: `services.beszel-agent.key` binds from `policy/globals.nix`
   (`beszel.hubKey`), the sops registration and the enrollment gate are gone, and the fleet-wide
   `beszel/key` entry in `secrets/common.yaml` retires with them. The bound value was verified
   against the live fleet first: the deployed agent's rendered environment carries exactly that key.
5. Telegram delivery is off (`services.notify.telegram.enable = false`): ntfy is the fleet's push
   path, and the topic map stays bound so re-enabling it is one line.

**Consequences:**

- The evaluation is now consumer-shaped: `packages.ci` and `packages.arm-expensive` render this
  repository's hosts (`ssh-ng://nixbuild@home-forge …`) and `checks.fleet-render` validates our
  config. The v1 closure leak is gone.
- One upstream leak remains: `packages.fixture` still arrives from nix-fleet's own fixture profile
  and renders `fixture-host`/`builder.invalid`. The scaffold pins it as measured and it is reported
  upstream.
- Scheduling is not free: it needs the dispatch account (`modules.nixos.build-account`) on builder
  hosts and an authorized coordinator key before any profile can be selected. That is TD-30's work,
  not a fleet fact.
- The Beszel change removes a secret and a bootstrap gate from three host files; the encrypted
  `beszel: key:` entry is inert and is the operator's to drop on the next re-encryption.

**References:**

- `modules/flake/builder-access.nix`, `modules/flake/observability-agent.nix`,
  `modules/notifications/notify.nix`, `policy/globals.nix`
- nix-fleet `docs/contracts/builders.md`, `docs/contracts/hosts.md`, `lib/build-profile.nix`
- `docs/decisions.md` D-066 (superseded), D-060 (generated flake and follows aliases)

## D-069: The PostgreSQL substrate converges consumer roles, databases, and ownership itself

**Status:** Accepted

**Context:**

A generation that registers a credentialled consumer for the first time (langfuse on
`oci-melb-1`) failed to activate: `postgresql-provision.service` reported
`services.postgres.consumers.langfuse: role 'langfuse' does not exist`, and deploy-rs rolled back.
The role and database were created 19 s later, during the rollback's own unit restart.

The executed artifacts show why. Roles and databases were created by nixpkgs'
`postgresql-setup.service`, which systemd started from the definition it already had loaded: the
script that ran (`/nix/store/j04dd7…-unit-script-postgresql-setup-start`) is the *previous*
generation's and has no mention of langfuse, while the generation's own script
(`/nix/store/lnbc…`) contains that consumer's `CREATE USER`, `ALTER ROLE … LOGIN` and
`ALTER DATABASE … OWNER TO`. `postgresql-provision.service` was new in that generation, so systemd
read it from the new `/etc` and ran the new script — ordered after a setup unit that had just
recreated the previous role set, and it correctly reported that the role was missing.

**Decision:**

Consumer state is converged by the substrate's own unit, not by `postgresql-setup.service`:
`services.postgresql.ensureDatabases`/`ensureUsers` are not set, and
`systemd.services.postgresql-provision` creates each registered role, creates its database, sets
database ownership, enables login for `scram` consumers, applies the SOPS-held password, and runs
the registration's `setupSQL`. nixpkgs keeps the cluster: `initdb`, `pg_hba`, settings, and the
extension packages composed from the same registry.

The unit executes a fixed trampoline (`exec /etc/postgres/provision.sh`), so its own content never
varies with the consumer set and a stale in-memory definition cannot provision a stale set; the
script itself is rendered per generation under `/etc` (current by the time any unit starts) and
`restartTriggers` restarts the unit whenever it changes.

**Consequences:**

- Registering a consumer no longer depends on nixpkgs' setup unit being reloaded first, which is
  what the consumers already assume: langfuse's containers `require`/`after`
  `postgresql-provision.service`.
- Provisioning is idempotent and self-healing across rollbacks — create-if-missing plus named
  failures — instead of failing on state another unit was supposed to have created.
- The substrate owns creation semantics (plain `CREATE ROLE` / `CREATE DATABASE`, then
  `ALTER DATABASE … OWNER TO`), so role and database shape is ours to keep in step with the
  registry.
- The provisioning ordering contract (`requires`/`after` `postgresql-setup.service`, `partOf`
  `postgresql.target`, `postgres` user) is unchanged, and so is the scaffold's probe of it.

**References:**

- `modules/database/postgres.nix`, `modules/database/postgres/_consumer.nix`
- `tests/check-dendritic-scaffold-contract.sh` (provisioning-ordering block)
- Evidence: `/nix/store/j04dd7…-unit-script-postgresql-setup-start` (previous generation, no
  langfuse) vs `/nix/store/lnbc…-unit-script-postgresql-setup-start` (that generation, with it)
- `docs/decisions.md` D-058 (the consumer registry), D-059 (hindsight, the first consumer)

## D-070: The OCI media mount is repurposed as the fleet's heavy-app storage mount

**Status:** Accepted

**Context:**

The music application moved entirely to `home-forge` (D-033-era migration), leaving
`oci-melb-1`'s `/srv/media` filesystem (sda6, ~75G, only 22G used) holding nothing but a
rollback copy of the music library that no oci component referenced: no unit, config, or
restic include named it, the syncthing unit no longer exists in oci's generation, and
home-forge's device list no longer pairs oci. Meanwhile `oci-melb-1` gains heavy-app
workloads (the Latitude observability stack, ClickHouse data growth) whose stores belong
outside the 8.2G-free root and the `/srv/data` partition that already holds the 6.1G
postgres cluster.

**Decision:**

- Delete the rollback copy (verified: home-forge's active library 29G > copy 22G; wipe ran
  only after confirming no syncthing agent, container, unit, or open handle existed that
  could propagate the deletion).
- Relabel sda6 `srv-media` → `srv-storage` and mount it at `/srv/storage`, matching
  home-forge's existing convention (same label, same mountpoint) — no repartition, no data
  movement, no provider-side config.
- `modules/hosts/oci-melb-1/_disko-single-disk-split.nix` declares the new end state
  (partition key `storage`, label `srv-storage`, mountpoint `/srv/storage`) so a reimage
  reproduces it.
- Heavy-app bulk state (Latitude's `fs` storage driver, later ClickHouse data if it moves
  off root) lands under `/srv/storage/<service>`; `/srv/data` remains the
  mutable-service-state mount (`/srv/data/<service>`).
- The `/srv/media` references in historical decision records (D-019/D-020/D-022/D-024/…)
  stay as written; they describe the state at the time and are superseded here.

**Consequences:**

- `oci-melb-1` gains ~73G of declared heavy-app storage; `/srv/media` ceases to exist
  fleet-wide (home-forge never had it — its media already lives under
  `/srv/storage/media/music`).
- oci's restic scope shrinks by the deleted copy (it was never in a registration; the
  historical media-root backup clauses are retired).
- Rollback insurance for the music library is now solely home-forge's own backups — the
  second on-disk copy is gone by design.

**References:**

- `modules/hosts/oci-melb-1/_disko-single-disk-split.nix`, `modules/hosts/home-forge/_disko-two-disk.nix`
  (the `srv-storage` / `/srv/storage` convention it matches)
- `ARCHITECTURE.md` (storage cross-cutting note, media ingest flow paths),
  `docs/architecture.md` (baseline, media/data flow, backup scope)

## D-071: The observability gauntlet resolves to Latitude beside langfuse

**Status:** Accepted

**Context:**

Three rivals were weighed against the operator's actual criteria — cost and cache
visibility, provider/model behaviour, failure tracing, loop detection, and improving the
coding agent's own telemetry rather than prompts inside an app. OpenLIT was deployed but
never fed (no exporter was ever pointed at it, and its ClickHouse user existed only in its
container environment with no matching server-side fragment); Laminar was researched to a
deployable plan and parked; Latitude V2 turned out to be the agent-failure triage console
those criteria describe — signals, flaggers, percentile cohorts, custom JavaScript
detectors — with prompt management removed upstream.

**Decision:**

- Delete the `openlit` aspect untried: module, web route, image pin, host selection and
  scaffold pins. Its ClickHouse database is dropped host-side during the deploy.
- Add `modules/observability/latitude.nix` as a single-file contributor selected on
  `oci-melb-1` beside langfuse — the trial is those two, not three.
- Co-tenant every dependency that has a native equivalent: one PostgreSQL consumer
  (database `latitude`, role `latitude`, pgvector, BYPASSRLS plus CREATEDB in `setupSQL`),
  ClickHouse in a dedicated `latitude` database behind its own `users.d` fragment, and two
  native Redis instances (cache, plus an append-only no-eviction BullMQ queue). Temporal and
  the six application images are containers; object storage is the `fs` driver on
  `/srv/storage/latitude` instead of a bundled SeaweedFS.
- Gate the UI behind Cloudflare Access and leave the API origin Access-free, because the
  browser and the web container both call the API across origins and a challenge on that
  path breaks magic-link sign-in. Ingest gets no route at all: a tailnet-only machine
  endpoint the exporters dial.
- Seed the `costDashboard`, `agentScore` and `customBehaviors` feature-flag rows, since
  cost visibility is the first criterion and upstream has no supported self-host switch.
- Leave generation, embedding and reranking providers unset: core observability works
  without credentials, and since Latitude hard-codes 2048-dimensional embeddings, a 2048-dim
  source must exist before semantic search is configured at all.

**Consequences:**

- `oci-melb-1` declares 13 containers (was 8) plus two Redis instances and the `latitude`
  ClickHouse database — roughly 4–5 GiB of new memory demand against 19 GiB available.
- The consumer registration, ClickHouse fragment, rendered environment and the three
  Latitude oneshots activate only once `secrets/services/latitude.yaml` exists; until then
  the aspect evaluates with its containers declared and no secret-dependent wiring, which is
  the fleet's two-step sops bootstrap.
- The `oci-melb-1` `postgresConsumers` scaffold pin still reads
  `["langfuse","paperless"]` and gains `latitude` in the change that adds the encrypted
  secret.
- The cluster stays on `wal_level=replica` (upstream's bundled compose runs `logical`, but
  its bring-your-own checklist requires only pgvector and a schema-create admin); if a
  migration rejects it, the fix is a substrate config line plus a cluster restart.
- langfuse keeps its route, its OIDC client and its ClickHouse ownership: nothing here
  depends on the trial's outcome, and Laminar remains a parked phase-two candidate.

**References:**

- `modules/observability/latitude.nix`, `modules/database/postgres/_consumer.nix`
- `policy/web-services.nix` (`latitude`, `latitude-api`, `latitude-ingest`), `policy/oci-images.nix`
- `research/{latitude,laminar,openlit}-selfhost-eval.md`
- `secrets/.templates/services/latitude.yaml.j2`, `.sops.yaml`

## D-072: Cross-fleet service endpoints derive from nix-fleet's service inventory

**Status:** Accepted

**Context:**

nix-fleet now owns the coordinates of the services that cross repositories or hosts —
`lib/service-inventory.nix` declares each endpoint's host ID, scheme, port and base path,
and publishes it as `lib.serviceEndpoints.canonicalServices` for plain-data policy files
and `resolveEndpoint config.fleet` for flake-level code (`docs/contracts/services.md`).
Until this change homelab restated those coordinates: the provider host ID and port of the
`ntfy-admin`, `bifrost` and `niks3-write` routes were literals in `policy/web-services.nix`,
and four provider modules carried their listen port as a literal option default.

**Decision:**

- `policy/web-services.nix` takes `canonicalServices` as its argument and derives the three
  canonical routes' whole `origin` through a `canonicalOrigin` helper that fails closed with
  named `web-services:` errors. The file stays plain data — it holds no flake reference —
  and subdomain, exposure mode, access policy and health settings stay local.
- `omniroute.port`, `hindsight.apiPort` and `docs-mcp.port` close over the resolved record in
  their own contributor, so each default *is* the canonical value. `bifrost.port` is defined
  by its aspect owner (`modules/ai/bifrost.nix`) instead, because the options leaf sits one
  level deeper than the scaffold contract lets a flake argument reach; the option itself
  carries no default. `docs-mcp`'s `embedding.baseUrl` defaults to the resolved
  bifrost/embeddings URL, and the `home-forge` fragment no longer states it.
- Every consumer of the policy passes the records in: the web-policy aspect, the export
  script, and both web contract tests.

**Consequences:**

- No canonical port literal remains in the tree: `20128`, `6280`, `8888`, `7411`, `2586`
  and `5751` appear only in nix-fleet's inventory. A provider move is one upstream edit plus
  a relock — the route, the module default and the exported policy follow.
- The policy file is no longer a bare attribute set: the parameter is a set pattern, so a
  consumer that omits the argument fails at evaluation instead of reading an empty map.
- Route grouping is unchanged: every route still lives under the one topology-owning host
  key, while `origin.provider` now follows the record. Every derived value equals the literal
  it replaced, so the delta in the regenerated `generated/policy/web-services.json` comes
  only from the other work riding this change (the latitude routes, `search`'s `allow_users`
  policy, langfuse's OIDC flag).

**References:**

- `policy/web-services.nix`, `modules/web/web-policy.nix`, `lib/policy.nix`
- `modules/ai/omniroute.nix`, `modules/ai/bifrost/service.nix`,
  `modules/knowledge/{hindsight,docs-mcp}.nix`
- `modules/hosts/home-forge/_nixos.nix`, `scripts/export-web-services-policy.sh`
- nix-fleet `docs/contracts/services.md`, `lib/service-endpoints.nix`,
  `lib/service-inventory.nix`

## D-073: In-fleet notification publishes dial the ntfy endpoint, not the public hostname

**Status:** Accepted

**Context:**

`just deploy` runs `notify send` on the target host. la-admin-1's daemon posted to its
loopback listener and worked; oci-melb-1 and home-forge built their URL from the catalog's
`publicUrl` (`https://ntfy.shrublab.xyz`), so every publish crossed Cloudflare — which
answers the daemon's `Python-urllib` client with error 1010 (browser-signature ban) and a
403, and would also have to satisfy the Access policy. Server, ACLs, tokens and the network
path were all healthy (the same request with a curl User-Agent returns 200), so the fault
was entirely the transport choice.

**Decision:**

- `lib/policy.nix` emits the machine `endpoint` for published services too; previously only
  a private service carried one. Its host stays locality-derived: loopback when the
  evaluating host serves the service, the provider's tailnet name otherwise.
- `notify.ntfy.serverUrl` derives from `repo.web.catalog."ntfy-admin".endpoint.url`, and
  la-admin-1's explicit loopback override is deleted — it derives the same value now.
- The scaffold contract compares every host's `serverUrl` against the catalog endpoint and
  drops the now-dead `ntfyOverride` control flag.

**Consequences:**

- Machine publishes stay on the tailnet. `publicUrl` remains for phones and public clients,
  and nothing about the edge, the Access policies or the public hostname changes.
- A provider move stays one policy edit: the endpoint follows, consumers do not.
- `endpoint` is now non-null on every catalog entry, so a consumer must not read null as
  "private" — privacy is `declarePublic` + `exposureMode`, or the null `publicUrl`.

**References:**

- `lib/policy.nix` (`mkCatalogEntry`, `endpointHost`), `modules/notifications/notify.nix`
- `modules/hosts/la-admin-1/_nixos.nix`, `tests/check-dendritic-scaffold-contract.sh`
- `docs/decisions.md` D-072 (the canonical endpoint records this dial resolves through)

## D-074: The observability store is a placement aspect on home-forge, fed by an interim node exporter

**Status:** Accepted

**Context:**

The fleet had no metrics or logs store: Beszel reports host health to its own hub, and
traces reach Latitude and Langfuse, but nothing answers "what did this host do last
week". A collector contract is being built fleet-side (nix-fleet), so the store had to be
deployable before it, without pre-empting it.

Placement follows the disks, measured live: home-forge has 775 GB free on `/` and 838 GB on
`/srv/storage`, while oci-melb-1 has 54 GB free on `/srv/storage` after the container store
moved there (D-070) — and that host had just been through root-filesystem exhaustion. The
store also stays off the host already carrying PostgreSQL, ClickHouse, Redis, Temporal and
the LLM stack.

nixpkgs ships native modules for all four services (`services.victoriametrics`,
`services.victorialogs`, `services.victoriatraces`, `services.grafana`), so nothing here is
a container or a pinned digest, and no new secret is required.

**Decision:**

- `modules/observability/victoria.nix` publishes the `victoria` placement aspect: no enable
gate, selected by one host record (home-forge).
- Four native services: VictoriaMetrics in single-node mode, VictoriaLogs, VictoriaTraces,
  and Grafana with provisioned datasources (both Victoria datasource plugins are in
  nixpkgs; traces use the built-in Jaeger datasource against VictoriaTraces'
  Jaeger-compatible `/select/jaeger` API).
- Ports come from the web policy, never the module: `victoriametrics`, `victorialogs` and
  `victoriatraces` are private `tailscale-only` endpoints with no ingress route, and
  `grafana` is a published, Access-gated `tailscale-upstream` route (D-072).
- The store endpoints carry no auth yet — the tailnet is the perimeter the foundation
  aspect already trusts. Grafana's interactive gate is Cloudflare Access, so it serves
  read-only anonymous viewers and is given the documented pre-26.05 non-secret key, which
  NixOS 26.05 now requires explicitly.
- Producers are deliberately out of scope: the interim producer is one node exporter per
  host, enabled by the `observability-agent` aspect and scraped over the tailnet by the
  store's own `promscrape` job, alongside the store's self-metrics. The fleet collector
  contract supersedes that seam.
- Data stays in the modules' `StateDirectory` under `/var/lib` on the host's root
  filesystem — these units run as dynamic users under `ProtectSystem=full` — with retention
  as the volume control (12 months metrics, 30 days logs and traces). Relocating to a bulk
  mount is a bind mount in front of that directory, not a new storage-path flag.

**Consequences:**

- Metrics, logs and traces have one durable store and one dashboard front end with no new
  secret, no container image and no custom packaging; the scrape list is a host-owned
  interim seam until the collector contract derives it.
- The OTLP stream gains a third destination with explicit retention, which is the neutral
  arm for the tracing A/B (Latitude and Langfuse remain the app-native ones).
- Grafana holds no secret material: it becomes a sops-managed deployment the day it grows
  local users, API keys or OIDC.
- A later move of the store is a policy edit plus re-selection, because the ports were never
  restated in the module.

**References:**

- `modules/observability/victoria.nix`, `modules/flake/observability-agent.nix`
- `policy/web-services.nix` (the four route declarations),
  `modules/hosts/home-forge/{default,_nixos}.nix`
- `tests/check-dendritic-scaffold-contract.sh`, `docs/decisions.md` D-070 (storage
  placement), D-072 (port derivation)

## D-075: The observability producers run nix-fleet's telemetry contract, with our conventions on top

**Status:** Accepted

**Context:**

D-074 deployed the store with an interim producer: the `observability-agent` aspect enabled
one node exporter per host and the store scraped them by tailnet name from a host-owned
list. That seam had the store reaching into every host, it carried no logs and no traces,
and it was explicitly temporary — nix-fleet was building a host-local collector contract to
replace it.

That contract is published (nix-fleet `06f50853`, green in CI). `services.telemetry`
declares, per host, the OTLP receiver, Prometheus scrape sources, journald shipping, the
named destinations and the per-signal pipeline fanout, realized by an otel-collector
provider and a Vector journald provider. Its aspects are realizations of that mechanism —
`telemetry` plus `node-exporter` — and, like every shared mechanism (D-061), they are
consumed here through convention contributors of ours rather than selected from nix-fleet
directly, because nix-fleet's aspects are not merged into our flake's module namespace.

**Decision:**

- `modules/flake/telemetry.nix` publishes our `telemetry` aspect: it imports nix-fleet's
  module and supplies the fleet's conventions — the store is named as both the metrics
  destination (VictoriaMetrics remote-write) and the traces destination (VictoriaTraces
  OTLP), and journald ships to VictoriaLogs. Every URL derives from the store's catalog
  entry (`repo.web.catalog.<id>.endpoint.url`), so the colocated/remote difference (loopback
  on the store host, tailnet FQDN elsewhere) follows from the endpoint projection instead
  of a second rule (D-073); `services.otel-collector.exporterExtra` sets VictoriaTraces'
  signal-specific `traces_endpoint`, because VTraces rejects the exporter's default
  `/v1/traces` append.
- `modules/flake/node-exporter.nix` publishes the `node-exporter` aspect. The mechanism is
  entirely nix-fleet's — loopback listener, local scrape registration, its own failure
  notification — so the contributor supplies only the convention it cannot do without: the
  scrape target's identity. Without it the target carries just the loopback address, and
  three hosts' node metrics arrive as one series per metric, overwriting each other in the
  store; the label is `instance = <host>.<tailnet suffix>:<port>`, which keeps the naming
  the dashboards and alerts already address.
  - revised by D-081: the scrape identity is nix-fleet's own default
    (`instance = <hostName>:<port>`), verified distinct per host by a live store probe, so
    this contributor binds no convention of its own.
- All three hosts select both aspects. `oci-melb-1` additionally binds the OTLP receiver
  (`services.telemetry.otlp.host = "0.0.0.0"`) as the fleet's gateway for producers outside
  the fleet; the wildcard is deliberate and bounded by the host firewall, which publishes
  only 22/80/443 and trusts `lo`/`tailscale0`.
- The collector's internal Prometheus reader is switched off
  (`services.opentelemetry-collector.settings.service.telemetry.metrics.level = "none"`):
  its default `127.0.0.1:8888` is the port nix-fleet's own service inventory assigns to
  `hindsight/api` on home-forge, where the host-networked container holds it and the
  collector died at startup with `bind: address already in use`. Nothing consumes those
  self-metrics. (The same bind failure appeared once on oci-melb-1, whose holder was never
  identified; the level setting removes the listener everywhere.)
- The interim seam is deleted: `services.prometheus.exporters.node.enable` (so
  `observability-agent` is the Beszel agent mechanism alone again), the store's `node`
  scrape job with its `scrapeTargets` and `nodeExporterPort` options, and the
  scrape-topology list in home-forge's host fragment. The store keeps only its own
  `victoria` self-scrape job.

**Consequences:**

- Metrics stop being pulled host-to-host: each host pushes its own, so the store needs no
  reachability into another host and a producer's absence shows up as a gap rather than a
  failed scrape of someone else's exporter.
- Journald shipping is bounded, not lossless: the journald source defaults to the current
  boot and journald rotates at 300M/7d, so each reboot leaves never-shipped prior-boot
  entries behind, while the 512 MiB disk buffer protects records already read.
- Every producer host now runs a collector and Vector as well; both are nix-fleet
  mechanisms with their own failure notifications, so a wedged producer is reported by the
  same path as any other unit.
- The gateway on `oci-melb-1` is the credential-free OTLP endpoint an off-fleet producer
  pushes to, and the place the Latitude and Langfuse fan-out legs land once their project
  keys exist.
- A backend move is one contributor edit: no consumer restates a store URL or port.

**References:**

- `modules/flake/{telemetry,node-exporter}.nix`, `modules/observability/victoria.nix`,
  `modules/flake/observability-agent.nix`
- `modules/hosts/*/default.nix` (aspect selection), `modules/hosts/oci-melb-1/_nixos.nix`
  (the gateway bind)
- nix-fleet `modules/telemetry/**` and its `docs/contracts/telemetry.md`; `docs/decisions.md`
  D-061 (convention contributors), D-073 (catalog endpoints), D-074 (the store)

## D-076: Bifrost's routing rules are the fleet's model authority, and the file must be its source of truth

**Status:** Accepted

**Context:**

The fleet's model names (`shrublab-text`, `-fallback`, `-image`, `-embedding`) are sent by
hindsight, paperless-gpt and karakeep. Every one of them failed with a 403 from
`provider: opencode` — bifrost's built-in Zen entry — regardless of what
`policy/bifrost-config.json` declared, including after the alias map was corrected and the
provider's base URL and session header were verified with a direct call that returned 200.

Two properties of bifrost's config model explain it. Routing rules are not read from the
file on every start: they live in the config store (`config.db`, tables `routing_rules` and
`routing_targets`), and the store's rows were all `enabled = 0`, so a request matching no
rule fell through to model resolution and landed on the built-in provider. The file's
`governance` section only becomes authoritative when the top-level `source_of_truth` is set
to `config.json`; the default (`split`) keeps database rows. Separately, key-level `aliases`
take a bare provider-specific model id, not a `provider/model` string, so the qualified
values silently failed to resolve.

**Decision:**

- `policy/bifrost-config.json` sets `source_of_truth: "config.json"`, so the sections the
  file declares — `providers` and `governance.routing_rules` — are authoritative at startup.
- The routing rules are the single mapping authority and every rule is explicitly
  `enabled`: `shrublab-text` → `opencode-go/deepseek-v4-pro`, `shrublab-fallback` →
  `opencode-go/deepseek-v4-flash`, `shrublab-image` → `opencode-go/qwen3.8-flash`, with the
  same three rules' fallbacks staying inside `opencode-go`, and the previously store-only
  `embedding` rule (`shrublab-embedding` → `voyage/voyage-4`) written into the file so
  becoming authoritative does not drop the embedding path.
- The alias blocks are deleted. They were redundant with the rules and, in openrouter's
  case, actively harmful — its `shrublab-image` alias pointed at the expired key.
- `modules/ai/bifrost/service.nix` derives a unit property from the config content
  (`X-Bifrost-Config-Hash`), because `restartTriggers` on the source path did not restart
  the container when only the rendered config changed: a deploy re-rendered the file while
  the container kept serving the previous generation.

**Consequences:**

- Fleet model names resolve only through our provider; the built-in `opencode` provider row
  remains in the store but is no longer selected, and no rule or fallback reaches a provider
  we do not intend.
- A config edit now takes effect on the next activation without touching the store by hand;
  the file must keep every rule the fleet depends on, since the file's rules replace the
  store's.
- The same store-wins behaviour applies to `plugins`: the seeded `config_plugins` row is not
  re-read from the file on later starts (observed when the otel plugin's config changed), so
  changing a plugin's config requires dropping that row before restart.
- Verification is against the store and the wire, not the file: rule rows must read
  `enabled = 1` after startup, and the four fleet model names must answer 200.

**References:**

- `policy/bifrost-config.json`, `modules/ai/bifrost/service.nix`
- `docs/decisions.md` D-062 (the gateway), D-067 (file-driven mode)
- bifrost schema (`source_of_truth`, `routing_rule`, key-level `aliases`)

## D-077: A container is recreated when its environment changes, not when its unit happens to change

**Status:** Accepted

**Context:**

`virtualisation.oci-containers` generates the container's start script with a *stable*
env-file path — `/run/secrets/rendered/<name>` for a sops template, `/run/secrets/<name>`
for a secret consumed directly — and that file's content never appears in the unit
definition. A changed environment therefore left the unit byte-identical, systemd did not
restart it, and the running container kept the variables it had been created with. The
generated script is `podman run --replace` behind a `podman rm -f` pre-start, so a restart
is sufficient once it happens; nothing was making it happen.

This was not theoretical. A deploy that added `AUTH_CUSTOM_ID_TOKEN_SIGNED_RESPONSE_ALG`
for Langfuse's Kanidm OIDC reported success and activated the new generation while
`langfuse-web` kept serving the environment it had been created with eight hours earlier
(oci-melb-1, 2026-10-01), so the fix sat inert until the container was recreated by hand.
Bifrost escaped the same fate only because D-076 had already given it a config-content
hash. `restartTriggers = [ environmentFile ]` — present on `omniroute` and `hindsight` —
cannot help: the path is constant, only what it points at changes, so the trigger never
fires.

**Decision:**

- `modules/containers/container-env.nix` publishes the `container-env` aspect, selected by
every host that runs containers. For each container with env files it derives an
`X-Container-Env-Revision` unit property from the env-file paths, every sops template's
content, and the ciphertext of each sops file whose secrets that template interpolates, so
the unit differs exactly when the environment would.
- The secret half is reachable because sops-nix renders
`${config.sops.placeholder.<name>}` as `<SOPS:sha256(<secret name>):PLACEHOLDER>`: the
marker maps a template back to its secrets, and each secret to its `sopsFile`. Values are
decrypted at activation and are never reachable from evaluation, so the ciphertext is the
only eval-time trace of a rotated value.
- Coverage is the contributor's job, not the service module's: a new container needs no
wiring. The per-module `mkEnvRevision` helper that preceded this decision was deleted with
it. Bifrost keeps its own `X-Bifrost-Config-Hash` for the *file* its renderer writes,
which is a different input from the environment.

**Consequences:**

- A container whose environment file changes restarts on the next activation. On the first
deployment of this aspect every env-file container restarts once — the one-time cost of
the property appearing.
- Rotating a secret value recreates the container as well, because re-encryption changes
the sops file's ciphertext.
- The revision is derived from configuration, not from the rendered file, so an env file
produced outside sops (and therefore absent from `environmentFiles`) stays uncovered.

**References:**

- `modules/containers/container-env.nix`, `modules/ai/bifrost/service.nix`,
  `modules/observability/langfuse/service.nix`
- `docs/decisions.md` D-076 (the config-content hash this generalizes)

## D-078: Bifrost runs from nix-fleet's dynamic build, and this repository declares the plugins

**Status:** Accepted

**Context:**

Bifrost loads request filters as native Go plugins. Go's `plugin.Open` requires the host
binary and the plugin to come from the same module graph and toolchain — the loader
compares package hashes — which in turn requires a dynamically linked binary. Every
published Bifrost artifact is static: the Alpine and UBI images and the sampled Linux
release binaries were all `ET_EXEC` with no interpreter (verified 2026-10-03), and upstream
declined adding a dynamic image to OSS CI (maximhq/bifrost#2586). The gateway we ran,
`docker.io/maximhq/bifrost:v1.5.0-prerelease8`, was one of them.

The pressure that forced the question was a consumer defect with no consumer-side fix:
docs-mcp's embedding client hardcodes `encoding_format: "float"`, Voyage's embeddings API
rejects that field with a 400, and docs-mcp exposes no setting to omit it. A gateway-side
normalizer is the only place that repairs it once for every consumer, and the plugin
interface is the supported extension point for it.

**Decision:**

- The gateway runs natively from `inputs.nix-fleet.packages.<system>.bifrost` — the
dynamically linked build — with its plugin from the same nix-fleet revision, because only
one revision can guarantee the matching Go package hashes. nix-fleet owns the build
(`pkgs/bifrost/`, `pkgs/bifrost/plugins/`); this repository declares the plugin
registration and never mirrors the normalization logic.
- `modules/ai/bifrost/service.nix` owns the effective configuration: the repo-owned
`policy/bifrost-config.json` plus the plugin entry. It hashes the document's *inputs* — the
config file's digest and the plugin path — rather than the rendered file. Hashing the
rendered file would realise everything it references, including a plugin build for the
evaluating host's architecture, so `nix eval` of a host config would stop being
architecture-independent (found by the contract check, not by reasoning).
- The runtime is a native systemd unit under a dedicated `bifrost` account with
`ProtectSystem=strict` and only its app directory writable. The state directory's
ownership moved off the container era's shared uid 1000, which was the human admin.
- The unit carries two content-derived revisions: one over the configuration inputs and one
over the secrets file's ciphertext. Both paths are stable and systemd cannot see content,
which is exactly the failure D-077 describes for containers — a native unit has the same
blind spot, so it gets the same treatment in its own unit rather than through the
`container-env` aspect.
- `policy/bifrost-config.json` moved to the 2.2.5 shape. The admin account is declared as
`auth_config` with env indirection, because 2.2.5 no longer reads
`BIFROST_ADMIN_USERNAME`/`BIFROST_ADMIN_PASSWORD`. `custom_provider_config` is dropped from
`deepseek` and `opencode-go`: 2.2.5 treats both as standard providers and rejects the block
("cannot be created on standard providers"), while its built-in base URLs already match
ours. `voyage` stays a custom provider, which is what it is. `source_of_truth:
"config.json"` (D-076) is unchanged, as is the otel plugin's flat configuration and its
`disable_content_logging: true`.
- The OCI image pin is deleted with the container, so Renovate stops tracking it and no
unused reference remains.

**Consequences:**

- A configuration or credential change recreates the gateway process by changing its unit,
so the stale-environment class of failure no longer applies to this service.
- The first deployment of a given architecture pays for the Go build (the plugin needs the
same toolchain and vendor graph as the binary). The container's image digest pin no longer
exists, so the pinned revision moves with the nix-fleet input and is reviewed as a flake
update rather than a Renovate digest bump.
- The config store the running 1.5.x gateway created is replaced rather than migrated as an
operator step; the file owns providers and routing rules (D-076), so nothing
authoritative is lost, and the verification is the running process (`plugin status:
voyage-normalizer - active`) plus live alias calls — never the config file's contents,
which D-076 already showed can sit inert.
- Importing `modules/ai/bifrost/service.nix` now requires `repo.packages` on the host, and a
host that selects `bifrost` on an architecture where nix-fleet publishes no build fails at
build time rather than at request time.

**References:**

- `modules/ai/bifrost/default.nix`, `modules/ai/bifrost/service.nix`,
  `policy/bifrost-config.json`, `modules/flake/fleet-packages.nix`,
  `modules/flake/packages.nix`, `tests/check-bifrost-gateway-contract.sh`,
  `docs/runbooks/state-restore.md`
- `docs/decisions.md` D-076 (the file as routing authority), D-077 (content-derived unit
  revisions for stable paths)
- nix-fleet: `pkgs/bifrost/default.nix`, `pkgs/bifrost/plugins/voyage/main.go`,
  `tests/bifrost/voyage_check.py`; maximhq/bifrost#2586 (dynamic images declined)

## D-079: The Bifrost gateway mechanism moves to nix-fleet; this repository keeps its policy

**Status:** Accepted

**Context:**

D-078 made the gateway native: the runtime came from
`inputs.nix-fleet.packages.<system>.bifrost` with its Voyage plugin, and
`modules/ai/bifrost/service.nix` built everything around it — the service
account, the `config.json` render unit, the unit lifecycle, the failure
registration, the state directory. None of that was this repository's policy. It
is what any consumer of Bifrost has to do to run it at all, and the ABI that
makes the plugin loadable — binary and plugin from one revision, one toolchain —
is nix-fleet's invariant to keep rather than ours to restate.

nix-fleet now publishes `flake.modules.nixos.bifrost`, which carries exactly that
mechanism: the package, the `bifrost` account, the application directory, the
startup-configuration install with the config store disabled, the unit lifecycle,
and the `bifrost.failure` notification registration. Its contract
(`docs/contracts/bifrost.md`) draws the line this decision follows — the fleet
owns the mechanism; the consumer owns providers, credentials, exposure, backups
and telemetry policy, and keeps the secret-rotation restart wiring, because
rewriting a file at a stable path does not change a systemd unit.

**Decision:**

- `modules/ai/bifrost.nix` imports `inputs.nix-fleet.modules.nixos.bifrost`.
Import is deployment, so there is no `services.bifrost.enable`; the aspect owner
keeps only the canonical listen port, still resolved from nix-fleet's service
inventory.
- `modules/ai/bifrost/service.nix` keeps policy and gives up mechanism. Gone:
the `package` override, the `bifrost` user and group, the `bifrost-config` render
unit, the `bifrost` unit body, our own `renderedConfig` and `renderedConfigFile`
options, the `services.notify.events.bifrost` registration, and the tmpfiles
rules for the application directory. Kept: the settings document, the plugin
registrations, the SOPS-rendered environment file, the container-facing ingress
rule, the backup registration, the secret-rotation restart, and the URLs
consumers dial.
- Plugin registration moves out of `policy/bifrost-config.json` into
`services.bifrost.plugins.*`, that member's only owner — the fleet module refuses
a `plugins` member under `settings`. Both entries move: the built-in `otel`
exporter, whose configuration is telemetry policy, and the native
`voyage-normalizer`, whose path only the module can resolve from the fleet
package. The rendered list keeps the order the running gateway already had.
- `dataDir` becomes the application directory itself, `/srv/data/bifrost/app`,
which is what the fleet contract means by it. The module supplies this fleet's
path instead of the host, which now binds only its secret file. The fleet module
installs `config.json` from the rendered document before every start and names
that document in `restartTriggers`, so a settings or plugin edit recreates the
process without a render unit of ours ordering in front of it.
- Secret rotation stays here: the unit takes the encrypted secret file as a
second `restartTriggers` entry, the half the fleet deliberately leaves open. This
is D-077's blind spot in a native unit — `container-env` does not reach it,
because that contributor covers `virtualisation.oci-containers`.
- No ownership migration moves with it. The contract puts that on the consumer;
the live directory is already `bifrost`-owned, and
`docs/runbooks/state-restore.md` carries the ownership step for a restore, as it
does for every other native service.

**Consequences:**

- The gateway becomes one mechanism with one implementation, so a future consumer
inherits it instead of copying this repository's unit, and the ABI invariant
D-078 depends on becomes the fleet's to preserve.
- `tests/check-bifrost-gateway-contract.sh` stops pinning the unit body we used to
own and starts pinning the fleet assumptions this repository now relies on:
`dataDir` is the application directory, the startup configuration is installed
into it, and both the rendered document and the encrypted secret file are restart
triggers.
- Relocking nix-fleet from `5950fcbb` to `dc29c326` moved the shared baseline:
`nixpkgs` `c59305ba` → `a7868a72` and `sops-nix` `5efb5a6f` → `dcd241ba`. `degoog`
is a mutable ref and was held at `e4e110b9` again, so the bump stays scoped to
nix-fleet's own graph.

**References:**

- `modules/ai/bifrost.nix`, `modules/ai/bifrost/service.nix`,
  `policy/bifrost-config.json`, `modules/flake/fleet-packages.nix`,
  `modules/hosts/oci-melb-1/_nixos.nix`,
  `tests/check-bifrost-gateway-contract.sh`, `docs/runbooks/state-restore.md`
- `docs/decisions.md` D-078 (the native runtime and the plugin ABI), D-077
  (content-derived unit revisions for stable paths)
- nix-fleet: `modules/ai/bifrost.nix`, `docs/contracts/bifrost.md`

**Status:** Superseded by D-093 — this baseline pins LLVM 22 for the ClickHouse build, so the package substitutes from the shared baseline again

**Context:**

The Langfuse stack runs a native ClickHouse server
(`modules/observability/langfuse/service.nix`), and moving that stack to
home-forge put the package on the deployment path. It does not build there.

The derivation this baseline evaluates —
`/nix/store/x1c3z55sf98m90c7142yn3lcvvqgx46p-clickhouse-26.8.7.19-lts.drv`,
output `4fm10mf5jkywa2yhxyiv84afnaszc0sw-clickhouse-26.8.7.19-lts` — is the one
Hydra builds for `nixpkgs:staging-next:clickhouse.x86_64-linux`, and that build
**fails** (build 346560573, `buildstatus: 1`) at the final link:

```
ld.lld: error: undefined symbol:
>>> referenced by stripped.o:(.text._RNvXsq_…aho_corasick…3fmt…) in archive rust/workspace/lib_ch_rust_prql.a
clang++: error: linker command failed with exit code 1
```

The undefined symbol carries no name and the archive member is `stripped.o`:
nixpkgs runs ClickHouse's own `cmake/strip_rust_symbols.sh`, and its derivation
notes that `llvmPackages.bintools` is "required by cmake/strip_rust_symbols.sh to
match the LLVM toolchain, otherwise it corrupts .eh_frame in the Rust
staticlibs". Under LLVM 21.1.8 the stripped Rust staticlibs no longer resolve.
That is a packaging defect, not a cache gap: output and `.drv` are published
nowhere (cache.nixos.org, numtide's mirror, nix-community cachix and the fleet's
niks3 all answer 404), and because the derivation is identical our own build
would fail the same way after ~17k compile steps. `rustSupport = false` is not a
way out: it only drops `rustc`/`cargo` from the derivation's inputs, ClickHouse's
CMake does its own Rust detection, and that variant is uncached too.

The fleet does not have to repair that build. The revision this repository used
before the nix-fleet v2 relock — nixpkgs `44a91898…` — evaluates the *same
version* to `/nix/store/1rb0ambr…-clickhouse-26.8.7.19-lts`, which Hydra built
successfully and published: it answers 200 on cache.nixos.org and on the fleet
cache, and it is already realised on home-forge.

**Decision:**

ClickHouse comes from its own nixpkgs pin. `nixpkgs-clickhouse` (`44a91898…`) is
declared in `modules/flake/inputs.nix`, `modules/flake/fleet-packages.nix`
projects it as `repo.packages.clickhouse`, and both ClickHouse call sites read
that projection: the Langfuse module binds `services.clickhouse.package`, and the
Latitude database-init client takes its `clickhouse-client` from the same
projection. Both mattered — the host package set's client kept the broken
derivation in the system closure on its own, and the closure is what a deploy
builds. The pin is a frozen revision rather than a tracked channel, so the
workaround cannot drift, and Renovate is told to leave it alone. Every other
package keeps coming from the shared baseline through nix-fleet.

**Consequences:**

- The package set gains exactly one more nixpkgs node — the lock gained
`nixpkgs-clickhouse` and moved nothing else — and the two call sites above are
its only consumers.
- The server runs one nixpkgs generation behind the rest of its host. ClickHouse
is a self-contained C++ service with no NixOS coupling beyond
`services.clickhouse.package`, so the deviation stays inside that closure.
- `tests/check-dendritic-scaffold-contract.sh` pins all three wiring points by
grep — the frozen revision in `inputs.nix`, the projection in `fleet-packages.nix`,
the binding in the Langfuse module — and exposes `clickhouseVersion` in the
placement probe, because both candidates carry the identical version string and a
version assertion alone would not catch a dropped pin. Comparing the bound
package against the host's own was the sharper check and is not reachable:
`config.nixpkgs.pkgs` carries no package attributes and `config._module` is not
readable from a configuration, so the wiring greps are the available form.
- Debt: the input exists only while the shared baseline's ClickHouse fails to
link. Remove the input, the projection, the module binding and the test
observable together once `pkgs.clickhouse` substitutes from a cache again.
aarch64 is untested for the pinned revision: Langfuse is placed on x86_64 only
today, and an aarch64 placement would need that revision's ClickHouse cached or
built.

**References:**

- `modules/flake/inputs.nix`, `modules/flake/fleet-packages.nix`,
  `modules/observability/langfuse/service.nix`, `modules/observability/latitude.nix`,
  `tests/check-dendritic-scaffold-contract.sh`, `renovate.json`
- Hydra build <https://hydra.nixos.org/build/346560573> (job
  `nixpkgs:staging-next:clickhouse.x86_64-linux`, failed), and its raw log
  `https://hydra.nixos.org/log/x1c3z55sf98m90c7142yn3lcvvqgx46p-clickhouse-26.8.7.19-lts.drv`
- `docs/decisions.md` D-074 (the observability store on home-forge, which moved
  this stack); the failing revision entered the baseline with the nix-fleet relock
  to `5950fcbb`, carried by the `voyage-embedding-compatibility` change

## D-081: The node exporter's scrape identity is nix-fleet's, not a fleet convention

**Status:** Accepted

**Context:**

D-075 gave `modules/flake/node-exporter.nix` the one convention the aspect could not supply
on its own: the scrape target's `instance` label, spelled `<host>.<tailnet suffix>:<port>`.
Without a label the generated target carried only the loopback address, and three hosts'
node metrics would have arrived in the store as one series per metric, overwriting each
other.

nix-fleet has since made that label its own default — `dc29c326`, published before our
previous pin — `<hostName>:<port>` as a plain `mkDefault`, with the instruction to keep our
override until a live store-side probe confirmed the new spelling was distinct per host.
What was outstanding was the probe, not the default.

**Decision:**

- Our override is deleted; `modules/flake/node-exporter.nix` now imports nix-fleet's
  mechanism and publishes our aspect name over it, binding no convention.
- The identity is accepted on evidence rather than on the default's shape. Before the swap
  VictoriaMetrics held exactly three node series, one per host, and the three hosts render
  distinct values after it: `oci-melb-1:9100`, `la-admin-1:9100`, `home-forge:9100`.
  Distinctness rests on canonical host IDs being unique, which the host registry already
  fails closed on — the same reason the FQDN spelling was never load-bearing for identity.
- Only the label's *value* changes, and nothing here consumes it: this repository declares
  no VictoriaMetrics alerting or recording rules, queries node metrics nowhere, and reaches
  `instance` in Grafana only as a template variable.

**Consequences:**

- A saved Grafana dashboard variable or filter pinned to the old FQDN value does not
  repopulate by itself and has to be re-picked; that is the one place a stale value hides.
- Old FQDN series stay queryable until staleness, so `sum by (instance)` on a node metric
  briefly reports six series per host before settling to three. Transient, not corruption.
- Uniqueness now depends on an upstream default instead of on our binding. That is the
  intended division — the value is upstream's to name — and it means a change to that
  default upstream reaches the store without a change here.
- Debt: nothing here asserts the three hosts render distinct values. nix-fleet asserts its
  half — its fixture proves the default tracks both hostname and a non-default port, and
  that a consumer override wins — while the consumer-side distinctness is ours to state,
  because only this repository knows the host list. Eval-time distinctness is the property
  that prevents the collision; the store cannot be queried from the contract test.

**References:**

- `modules/flake/node-exporter.nix`, `modules/flake/telemetry.nix`
- nix-fleet `modules/observability/node-exporter.nix` (`dc29c326`) and
  `lib/telemetry-contract.nix`
- `docs/decisions.md` D-075 (the telemetry contract and the convention it introduced)

## D-082: The CI build plane is nix-fleet's builder contract, and `.#checks` is what CI builds

**Status:** Accepted; trusted-users fix pinned, builder activation pending

**Context:**

D-035 made nixbuild.net the canonical CI build plane at a time when the fleet had no
builder inventory of its own: CI authenticated to a third-party remote builder with an
attenuated token, remote-built host toplevels against `ssh-ng://eu.nixbuild.net`, and the
deploy workflows prebuilt profiles through the same route.

Since then nix-fleet became the canonical declaration of who the fleet's machines are and
what build capacity each contributes (D-066), and it now publishes the build plane that
inventory implies: a builder account, the canonical CI coordinator key
(`fleet.ci.sshPublicKey`), named build profiles with per-host job counts, the reusable
`build-push-cache` workflow, and the bundles that workflow installs. This repository had
adopted only the inbound half — `builder-access` renders SSH trust from the same inventory
(D-065, D-068) — so the hosts were reachable as builders while CI still built through
nixbuild.net, and our deploy path prebuilt through it as well.

A live dispatch exposed a missing permission in the adopted contract: run 37673821886
at `6bc11d04` passed all three SSH preflights, but the ARM `vmagent` guard rejected an
unsigned input. Repeating the identical tiny ARM derivation through OCI showed the cause:
`nixbuild` failed copying the input with “lacks a signature by a trusted key”, while root
succeeded. The Nix daemon's signature policy was unchanged; the dispatch account itself
needs trusted-user authority for ssh-ng's store operation.

**Decision:**

- The fleet's own machines are the build plane. `build-account` is selected on all three
  hosts through the convention contributor `modules/flake/build-account.nix`, which binds
  `fleet.ci.sshPublicKey` as the account's only authorized key. ssh-ng dispatch also
  requires the account name in `nix.settings.trusted-users`; the selected nix-fleet
  aspect owns that name-derived binding, now pinned at `33dea5c5` (the fix itself landed at `44bf4f71`) and evaluated on all
  three hosts. Do not duplicate it here. This is effectively root-level Nix authority
  despite no sudo, so access must remain constrained by the coordinator key and host
  SSH/Tailscale admission policy. Host activation remains pending.
- CI builds the nix-standard `.#checks` target rather than a bespoke aggregate. One caller
  job adopts nix-fleet's reusable `build-push-cache` workflow, pinned to the same commit as
  the flake input, with `systems` selecting both architectures, `builder_attr: ci`, and
  `targets: .#checks`.
- The deploy surface is standardised to that target instead of drifting from it.
  `modules/flake/deploy.nix` publishes each host's activatable profile as
  `checks.<system>.host-<host>` on the system that builds it, and the `packages.host-*`
  mirror publishes the same derivations unfiltered for cross-system prebuilds. The mirror
  previously omitted home-forge, which is why `just prebuild-local` could not resolve it.
- Host scheduling stays opt-in and off. Upstream installs the profile's rendered machines
  file for CI and leaves `nix.buildMachines` to a separate projection; nothing here
  populates it, so the fleet's machines accept CI's build jobs without dispatching builds
  to each other.
- Publication belongs to the build job and activation to the deploy job. `deploy-host.yml`
  stops prebuilding through nixbuild.net and instead verifies the exact profile it is about
  to activate is substitutable — `nix build --option max-jobs 0 --option builders ""` — so a
  cache miss fails loudly in CI rather than becoming a silent host-side compile. The build
  coordinator key is a build credential and never becomes a deployment key; the deployment
  path keeps its own tailnet identity and host-key verification.

**Consequences:**

- The three hosts are builders now, so the CI coordinator key is an inbound authorization on
  every host: rotating it is one upstream value plus the GitHub secret, not a per-host edit.
  The dispatch account is a trusted Nix user because ssh-ng requires that authority;
  treat compromise of its key or admission path as root-equivalent on each builder. This
  does not change cache signatures, `require-sigs`, cache keys, or publication authorization.
- The workflow's inputs are the contract's, and they carry meaning: `runner_system` defaults
  to aarch64, `systems` to both, `builder_attr` to `ci`, and `targets` is a single flake
  selection. One coordinator job therefore covers both architectures through the fleet's own
  builders, and a foreign-architecture target cannot fall back to the coordinator's store.
- A green workflow is not acceptance. The evidence that separates "CI built it" from "CI
  found it cached" is an uncached build on each architecture followed by signature-checked
  substitution, so main-push builds stay off until a manual dispatch has produced that.
- The wiring gate moves to the build job. `nix flake check --no-build` is gone from CI:
  evaluating the flake realises degoog's bun2nix import-from-derivation, whose
  `runCommandLocal` step sets `allowSubstitutes = false`, so an evaluation-only gate cannot
  pass on a cold store. Building `.#checks` is the same gate with a builder available.
- `.github/actions/setup-nixbuild` is deleted with the path it served;
  `nixbuild/nix-quick-install-action` stays only as a Nix installer.
- Leftover, recorded rather than hidden: `trusted-substituters` still names
  `ssh-ng://eu.nixbuild.net`, because nix-fleet's `nix-baseline` carries it. Nothing here
  consumes it — `substituters` never included it — and it is upstream's default, not restated
  locally, so removing it is an upstream question.
- Deploy topology flags are unchanged: `remoteBuild` and `strictSubstituteOnly` in
  `lib/deploy/hosts.nix` still describe per-host deploy behaviour for operator runs, while
  the CI path passes `--remote-build` and so only activates.

**References:**

- `modules/flake/build-account.nix`, `modules/flake/deploy.nix`, `modules/flake/packages.nix`
- `.github/workflows/{ci,deploy,deploy-host}.yml`, `tests/check-build-account-contract.sh`
- `openspec/changes/adopt-fleet-ci-builders/`
- `docs/decisions.md` D-035 (superseded), D-065, D-066, D-068
- `docs/plan.md` TD-30 (the debt this closes)


## D-083: AI telemetry reaches the LLM backends by an explicitly selected route, and that route is routing-only

**Status:** Accepted; gateway-side routing and Bifrost enrollment are live, producer enrollment remains selective, and authenticated admission is pending. Revised by D-084 for trace views and D-086 for three-signal routing and log provenance.

**Context:** The collector gateway on `home-forge` derived its trace fan-out from destination presence: every trace arriving on the general OTLP ingress was exported to VictoriaTraces *and* to Langfuse and Latitude. The LLM-observability backends therefore received the whole fleet's telemetry — infrastructure, node, Bifrost and diagnostic-probe spans — and Latitude reported sessions containing no LLM call, which is the visible form of that mixing. There was also no way for a producer to select an AI-only stream, because the general ingress was the only ingress. nix-fleet published a named-route contract (`services.telemetry.routes.<route>`, main `fb5ac7e3`) that admits signals independently and gives each signal its own destination declaration.

**Decision:** Both the general route and the independently addressed `routes.ai` listener carry traces, metrics and logs, with per-signal destinations declared explicitly: VictoriaTraces, VictoriaMetrics and VictoriaLogs for the general route; the AI route additionally names Langfuse and Latitude for traces. AI producers select that listener instead of the general one. The isolation is **routing only**: a route listener carries no authentication, enrolment or credential, so no consumer document, comment or claim may describe the AI lane as authenticated or access-controlled. Authenticated admission stays deferred to a separate upstream change. Enrolment of a producer resolves the ingress coordinate from nix-fleet's canonical service inventory rather than a literal host and port.

**Alternatives considered:**

- **Filtering by span attribute on the general ingress** — rejected: an attribute is caller-supplied and would be used as a routing selector, and it filters spans rather than producers, which would break complete sessions.
- **A second collector service** — unnecessary: one collector runs multiple named receivers and pipelines, and the route-scoped instances already give each destination its own queue, WAL and retry scope.
- **Enrolling Bifrost immediately with a literal gateway address** — rejected: it would restate a physical coordinate that the service inventory owns (D-063, D-064); enrolment follows the published `ai-otlp` record.

**Consequences:**

- General and AI telemetry are separate streams with separate delivery state; a backend a route does not name simply receives nothing from that route. VictoriaLogs receives OTLP application logs on both routes, while journald continues through Vector.
- Destination-scoped exporter policy — each backend's credential, required headers, and Latitude's `compression = "none"` — applies unchanged to route exporters, so a route names destinations and never restates a backend contract.
- Consuming the pin also required the lane migration: the bare `telemetry` aspect is now vocabulary plus this repository's fleet policy, each host composes the lanes for the signals it ships, and collector-scoped policy (`services.otel-collector.exporterExtra`, the collector's own metrics level) moved into the OTLP lane because that option only exists where a collector realization is composed. This supersedes D-075's aspect shape (`telemetry` plus `node-exporter` as the realizations) and D-074's gateway placement on `oci-melb-1` — the gateway moved with the store to `home-forge`.
- Two adjacent upstream moves landed in the same revision and are absorbed rather than worked around. The `services.nix-gc` fleet namespace is retired and the notify registrations name the units the aspect owns (`nh-clean`, `fast-nix-gc`, `fast-nix-optimise`) instead of the aspect, so our schedule override is dropped — upstream's defaults are daily `nh clean` with `--keep 3 --keep-since 7d --keep-one --no-gc`, hourly `fast-nix-gc` with a one-day `keepRecent`, and weekly `fast-nix-optimise`. They also prune stale roots, so restating a weaker schedule would have silently disabled that; `--keep 3` keeps the previous generation, so a deploy-rs rollback target survives a collection. The contract additionally requires journald shipping to name a unit allowlist or license the whole journal, and `includeAll = true` preserves existing behaviour: an empty allowlist previously shipped the entire journal, so the assertion made an existing choice explicit rather than changing it.
- The route listener binds the tailnet address and is reached by tailnet grants alone; a peer able to reach it can publish to both backends. That is no weaker than the general ingress it replaces, which reached the same backends, and closing it is the deferred admission change.

**References:**

- `modules/flake/telemetry.nix`, `modules/hosts/home-forge/_nixos.nix`
- `openspec/changes/telemetry-ai-route-isolation/`
- nix-fleet `docs/contracts/telemetry.md`, `docs/contracts/observability.md`, `modules/telemetry/lanes.nix`, `lib/telemetry-contract.nix`, `lib/telemetry-otel-collector-common.nix` at `fb5ac7e3`
- `docs/decisions.md` D-074 (the fan-out legs this narrows), D-075 (the telemetry contract), D-081 (the node exporter's scrape identity), D-086 (log redaction and route provenance)


## D-084: One AI route reads differently per destination, and the trace store's copy is lean

**Status:** Accepted; landed, awaiting the gateway deploy

**Context:** The routing-only AI lane (D-083) delivered every span intact to all three destinations. That put the operational trace store in possession of every prompt, completion and tool payload the lane carried — the fleet's long-retention trace store holds no use for that content — while the deployed Latitude (0.3.118) reads span attributes only and renders a session's messages from the deprecated `gen_ai.prompt`/`gen_ai.completion` pair, so its view of a session showed the spans and not the prompts. A route is one input audience, so a destination could not be given a different reading of the same span: every pipeline consuming the route receiver sees every span arriving on its listener. nix-fleet published the output-view recipe for exactly this (`examples/telemetry-output-views.nix` with the reusable `flake.lib.telemetryOutputViews.compositionFailures` guard, main `25d65d0e`).

**Decision:** The AI route carries one output view per destination, all consuming the same route receiver. Langfuse keeps the generated rich pipeline, because it parses a session; D-088 maps its vendor keys from canonical carriers. VictoriaTraces receives a lean view: the content carriers the analysis backends parse — the canonical message fields, tool arguments and results, the legacy `gen_ai.prompt`/`completion` pair, the generic `input.value`/`output.value` conventions and their numbered families — are deleted from the span, and content-bearing span events (the GenAI families and the SDK exception event) are dropped, while status, error attributes and timing survive. Latitude receives a version-scoped bridge that lifts the canonical carriers off the inference event onto the span for its deprecated parser, gated so it never mixes carrier families inside one span. The generated route pipeline is force-replaced rather than extended, because a member left in it while a view also exports it would be assigned two output paths. The composition, its branch processors and the expected views are declared in the fleet telemetry contributor and activated by the presence of the `ai` route; the expectation is published as read-only internal data and checked against the effective settings by nix-fleet's guard, with a mutant proving the guard is not vacuous.

**Alternatives considered:**

- **Give the route's store leg its own destination name** (what nix-fleet's example does, with `store` beside `general`) — rejected: it duplicates the canonical endpoint and the destination-scoped exporter policy for a backend that is already reachable as one destination, and the route-scoped instance is already separate in queue, WAL and retry scope. Upstream confirmed the guard's uniqueness check needs scoping rather than the consumer needing an alias.
- **Apply the guard to a route-only subset** — rejected: it would skip the general-declaration comparison the guard already performs correctly, and it reads the guard's data as something other than the effective configuration.
- **Keep the store leg rich** — rejected: it retains user payloads in the long-retention store for no analytical purpose, and expands the payload-retention surface beyond the backends that parse it.
- **Strip by allow list instead of deny list** — rejected: an allow list would silently drop instrumentation this fleet has not seen yet, which is a worse failure than retaining a carrier until it is listed.

**Consequences:**

- A prompt or completion is no longer recoverable from VictoriaTraces once the collector has forwarded it; debugging with payloads means querying Langfuse or Latitude, on their retention.
- The deny list is honest about its own coverage: a producer whose carriers are not listed reaches the store intact until it is added, so Hindsight's carriers are a binding task in the AI-route change rather than an assumed one.
- The bridge assumes one inference event per span; a span carrying two would overwrite the same carrier. It is version-scoped, so a Latitude upgrade that reads canonical attributes makes the view removable rather than permanent.
- Two of nix-fleet's guard checks are over-broad for a host that runs a general route and a route at once, or that admits more than traces: destination uniqueness keys on backend name globally, and coverage counts instances the trace views cannot own. Both are reported upstream and reported by our contract test as deviations rather than worked around by aliasing; the test still fails on any other guard finding. The guard gained an exact exporter-membership assertion at `33dea5c5` — each view pipeline must export exactly its route-scoped members — which no override can satisfy, and that half is adopted; the two checks above are unchanged there, because scoping them is nix-fleet's side of the fix (their confirmation is recorded above).
- No span is dropped from any destination, so the views are payload shaping and not an audience boundary. Nothing in this decision changes the admission position recorded in D-083.

**References:**

- `modules/flake/telemetry.nix`, `tests/check-telemetry-view-composition.sh`, `.just/checks.just`
- `openspec/changes/telemetry-ai-route-isolation/` (tasks 3.4, 3.5, 3.6, 6.4)
- nix-fleet `examples/telemetry-output-views.nix`, `modules/telemetry/output-view-checks.nix` at `33dea5c5` (the recipe first landed at `25d65d0e`; `33dea5c5` adds the exporter-membership assertion)
- `docs/decisions.md` D-083 (the route this shapes), D-074 (the store's retention)

## D-085: Host observability arrives by adoption, and an adopted contract is pinned by effective value

**Status:** Accepted; landed and verified live on all three hosts

**Context:** The fleet's host telemetry was complete in shape and incomplete in substance. Every host ran the node exporter and both telemetry lanes, but the exporter collected no unit state, so a crashed or flapping unit appeared only in the journal; nothing scraped the Tailscale daemon's own metrics, so tailnet health was invisible from the fleet's metrics plane; no telemetry carried an identity that joins to the canonical host record, so a series named its scrape target rather than the host that deploy metadata and web policy reference; and journal shipping left `trace_id`/`span_id` values as they arrived, so a record could not be correlated with its trace. All four are nix-fleet contract surfaces. Upstream published them in `telemetry-host-observability`, and its first published revision (`aa162629`) was withdrawn: the systemd collector contribution was defined with `mkDefault`, so a consumer's own `enabledCollectors` list *replaced* it instead of extending it — upstream's own frozen-host repro yielded only the consumer's collector and no `AF_UNIX` — and their gates passed on that revision because the composition case was absent from them. The fix (an additive `mkAfter [ "systemd" ]` contribution) is forward-only and published at `a48a1dcf`.

**Decision:** The fleet adopts the contract as published and states none of it locally: no `enabledCollectors`, no scrape registration, no identity option, no journal override. Every effect arrives through an aspect the fleet already selects (`node-exporter`, `tailscale`, `telemetry-metrics`, `telemetry-logs`), so the adoption is a pin move and an assertion about effective values. The assertion is the substance of the decision, and it is written as values rather than flags: the configured collector set and its disabled counterpart, the rendered exporter unit (the systemd invocation, the `AF_UNIX` allowance the public system DBus API needs, and the ordinary static account that runs it), the registered Tailscale scrape source and the job it produces, that job's canonical host label, the resolved `hostName`, the deliberately null `environment`, the unset journal host label and the journal correlation default. The pin set carries one mutation: on a throwaway copy, a host that declares its own `enabledCollectors` list must still receive the contributed collector and keep the systemd invocation. That mutation is the part that fails on the withdrawn revision's defect class, and it is the reason the contract test does not simply reuse upstream's verdict — the position that missed the defect is the position a consumer would be trusting. Verification of the running feature is outcome-based for the same reason: collector success plus unit-state series for the systemd leg, and a daemon-specific series for the Tailscale leg, because with the client fallback disabled a failed lookup can still answer a successful status with a page body instead of metrics. No consumer privilege is granted: the collector uses the public system DBus API on its existing account, and the Tailscale endpoint is served by the daemon-owned local API proxy before the browser session gate, so the scraper needs no group and no widening.

**Alternatives considered:**

- **Bind the systemd collector locally to be safe** — rejected: a local copy of a contribution upstream owns becomes a second authority that silently wins, the failure mode D-066 and D-068 removed from the fleet.
- **Pin the contract's declaration instead of its effective values** — rejected: the withdrawn revision declared the collector and still lost it, so a declaration check certifies exactly the defect it should catch; and a collector list can be correct while the rendered unit has lost the flag or the address-family allowance.
- **Check the systemd flag rather than the collector's outcome** — rejected: the flag proves intent, not collection; unit-state series prove the feature.
- **Check that the Tailscale endpoint answers** — rejected: a successful status can carry a page instead of metrics, which would certify a broken scrape as healthy.
- **Fill the environment label to complete the upstream contract** — rejected: the fleet has no environment dimension, and a filled value would be a second naming authority beside the canonical host IDs.
- **Override the journal correlation default** — rejected: the default is narrow, preserves messages and metadata, and has a documented opt-out; restating it locally would be a contract default with no fleet-specific reason.

**Consequences:**

- Unit state and tailnet health become queryable in the fleet's metrics store; a unit that fails and restarts is visible as a series rather than only as a journal line.
- Series and journal records join to the canonical host IDs, so retention, dashboards and alerting can key on the same identifier the fleet inventory uses. New label values create new series; there is no historical rewrite and no queue or WAL identity change, so producers keep their endpoints and buffered state across the deploy.
- The pin set now owns this adoption's regression surface. A future upstream change to these values reports as a failed check on the next pin bump, to be re-derived against the published contract rather than silenced.
- The fleet depends on an upstream contribution staying additive. The consumer-side mutation holds that dependency; a regression to enumerating replacement fails the gate rather than quietly removing a collector at deploy time.
- Nothing here is gated or admitted: the two producers are additive telemetry sources, and the routing separation that governs AI telemetry remains D-083/D-084.

**Verified live (2026-10-09):** The three hosts took the pin in the order `home-forge` (126 → 127), `la-admin-1` (64 → 65), `oci-melb-1` (326 → 327), each with magic rollback confirmed and the telemetry units restarted; no failed units anywhere. The generation comparison showed the pin moved nothing else — only the notify file's renamed render, the provenance copy, and those units (plus `oci-melb-1`'s `caddy.service.d/overrides.conf`, whose one difference is its reload-trigger store path). Both legs report from the running feature: `node_scrape_collector_success{collector="systemd"} = 1` with 1340 / 920 / 1095 unit-state series for `home-forge` / `la-admin-1` / `oci-melb-1`, and `up{job="tailscale"} = 1` with 27 / 26 / 26 daemon series. Every scraped series carries its canonical host ID as `host`, and none carries an environment label. The journal probe behaved as the contract documents: an uppercase message carrier and its lowercase twin normalized to one lowercase trace id, a valid span was promoted only beside a valid trace, an invalid carrier promoted nothing, a message carrying its own `host_name` and `_SYSTEMD_UNIT` overrode neither identity nor a unit field, and an uncorrelated record shipped unchanged with no trace id — messages preserved throughout. The store is not instantaneous, so a verification has to poll: a single query about a minute after a deploy reported `oci-melb-1` missing from both legs entirely.

**References:**

- `tests/check-dendritic-scaffold-contract.sh` (section 7n-4, the effective-value pins and the collector-composition mutation)
- `flake.lock` (nix-fleet `a48a1dcfaa0116e85d148e2c7b3f61636f7b0ec4`), `.github/workflows/ci.yml` (caller reference)
- `openspec/changes/telemetry-host-observability/`
- nix-fleet `telemetry-host-observability` at `a48a1dcf` (withdrawn intermediate `aa162629`)
- `docs/decisions.md` D-081 (the exporter's scrape identity is nix-fleet's), D-083 and D-084 (the AI routing this leaves untouched)

## D-086: OTLP logs use allowlisted fields and route provenance comes from the receiver

**Status:** Accepted; Collector 0.155.0 transformation and VictoriaLogs 1.53.0 storage verified with a local, non-deployed probe. The expanded composition guard still awaits the corrected multi-signal helper; no deployment.

**Context:** Extending the gateway's AI lane beyond traces means OTLP application logs and metrics also cross the same receiver boundary. The logs may contain arbitrary producer attributes, including content-bearing data and a caller-supplied `telemetry.route`; VictoriaLogs flattens resource and record attributes into searchable fields, so a record-level route value could collide with the intended route provenance. Journald remains a separate Vector path and is not part of the OTLP route.

**Decision:** The general and AI OTLP routes both send logs to VictoriaLogs, but only the AI listener sets resource `telemetry.route="ai"`. Before export, log-record attributes are cleared except a derived `trace_flags` field, and instrumentation-scope attributes are cleared; only resource `host.name`, `service.name`, `deployment.environment.name` and the receiver-selected route marker are retained. Collector transformations leave the OTLP body, event and observed timestamps, severity, correlation IDs and native flags untouched. VictoriaLogs stores event timestamp as `_time`, using observed timestamp only when event time is absent; it does not persist both timestamps independently. Since VictoriaLogs does not otherwise serialize native `log.flags`, the Collector projects it into the sole allowlisted record field `trace_flags`. The AI branch deletes a producer-supplied record `telemetry.route` before setting the resource marker; general branches remove producer-supplied route values from resource, span and datapoint attributes, so the label cannot claim a receiver the record did not use. The marker means only that the data entered via the named AI route; it is not producer identity, AI classification, admission, or authentication.

**Alternatives considered:**

- **Keep all OTLP log attributes and rely on VictoriaLogs indexing policy** — rejected: payloads would cross the retention boundary before indexing, and field collisions could misstate route provenance.
- **Store the marker on each log record/datapoint/span** — rejected: resource scope represents the receiver path consistently across records and maps to backend resource-derived fields; producer-level values are removed before it is set.
- **Drop the body or correlation fields with attributes** — rejected: these are first-class OTLP log fields, not attributes; the required body and trace-correlation fields are preserved explicitly.

**Consequences:**

- A local, non-deployed Collector 0.155.0 probe against VictoriaLogs 1.53.0 verified the rendered fields: the general row was unmarked; the AI row had `telemetry.route=ai`, canonical host/service identity, body, severity, trace/span IDs and `trace_flags=1`; arbitrary resource, record and scope attributes were absent, including producer-supplied route collisions. An observed-time-only probe populated `_time`; when both OTLP timestamps were present, event time won. VictoriaLogs exposes one `_time`, not both timestamp values independently.
- Logs and metrics now have explicit general and AI-route output pipelines alongside the existing per-destination trace views. This does not add authentication or admission control to the AI listener.

**References:**

- `modules/flake/telemetry.nix`, `modules/hosts/home-forge/_nixos.nix`, `tests/check-telemetry-view-composition.sh`
- `openspec/changes/telemetry-ai-route-isolation/`
- nix-fleet `modules/telemetry/output-view-checks.nix` (the reported multi-signal helper changes are not yet present in the shared checkout)
- Collector 0.155.0 transform processor; VictoriaLogs 1.53.0 `app/vlinsert/opentelemetry/pb.go`

## D-087: A co-located consumer dials the host-local endpoint, and the gateway is placed where its consumers run

**Status:** Accepted; evaluated and pinned by contract tests, not deployed. home-forge cannot activate until the operator re-encrypts the service-scope secret file for its age recipient.

**Context:** nix-fleet now publishes `lib.localEndpoint` and a `services.bifrost.localEndpoint` derived from the gateway's own listener (`649554fc0`). Placement in the web policy names the *provider* host, so the catalog's machine-to-machine endpoint resolves to the provider's tailnet name on every other host — which means a consumer running beside a gateway would cross the tailnet for a socket on its own machine, and the home host's inference path would depend on the public-cloud host being up. The fleet's two gateway dial sites are Latitude (which renders its dial into an environment file) and Hindsight (whose LLM base URL was the catalog route). PostgreSQL has its own host-local read (`services.postgres.localEndpoint`).

**Decision:** The `bifrost` aspect is selected on `home-forge` as well as `oci-melb-1`. The two are identically configured replicas — one configuration document, one package, one plugin definition, the canonical port from the service inventory on both — with independent process, state and service account; no gateway dials another and neither falls back to the other. A host that runs the gateway dials its own listener: consumers prefer `services.bifrost.localEndpoint.url` and fall back to the canonical route otherwise, probing `options` rather than `config` because that option exists only where the aspect is imported. The version prefix is the consumer's to append, since the local record is a bare origin. Both consumers can reach loopback (Latitude's containers share the host network namespace, Hindsight's container is host-networked). The ingress route keeps its canonical `bifrost/embeddings` origin: that is the edge dialing the provider's tailnet socket, a different decision from local consumption. PostgreSQL keeps its own port-only endpoint instead of adopting the shared helper.

**Alternatives considered:**

- **Keep one central gateway and let home-forge dial it over the tailnet** — rejected: the hop sits on the inference path of every home consumer and couples their availability to the cloud host, for a lightweight local proxy that shares no state with its peer.
- **Separate provider keys per gateway host** — deferred: per-host keys would improve attribution and revocation, but both instances draw on the same provider accounts and quota, so isolation would be nominal until a provider supports per-key attribution; the split is an operator key-management task, not a module change.
- **Adopt nix-fleet's `localEndpoint` for PostgreSQL** — rejected: the helper exists for HTTP(S) services and refuses any other scheme, so its `url` would misstate a database endpoint, and the socket-based consumers (`auth = "peer"`) are not a URL at all. The port-only record stays, with the reason recorded beside it.
- **Read `localEndpoint` unconditionally in the consumers** — rejected: the aspect is independently placeable, and an unconditional read would turn a placement change into an option-missing evaluation error instead of a remote dial.
- **Extend the catalog's loopback rule to cover the second instance** — rejected: that rule keys on the policy's declared provider, which names `oci-melb-1`; it cannot know a second replica exists, and teaching it about replicas would put deployment topology back into the route policy.

**Consequences:**

- Evaluated on the three hosts: home-forge renders port 7411 with `localEndpoint = http://127.0.0.1:7411`, Latitude `LAT_CUSTOM_AI_BASE_URL=http://127.0.0.1:7411/v1`, Hindsight `HINDSIGHT_API_LLM_BASE_URL=http://127.0.0.1:7411/v1`; oci-melb-1 is unchanged (7411, spans on the AI lane); la-admin-1 has no `services.bifrost` namespace.
- The gateway contract test now runs on both hosts and asserts the local endpoint against the port the unit actually binds, plus the two co-located dials, so a placement or port drift fails by name. The authority stays upstream: the endpoint and the listener are built from one value, so they cannot diverge.
- Blast radius: the provider credentials now rest on two hosts, and one service-scope file is shared, so a compromise of either host reaches the same keys and a rotation is a single file for both instances. Widening that readership is an explicit `sops updatekeys` step, recorded in the scope fixture and the secret-scope check.
- The fallback branch is not exercised by current placement — both consumers are selected only where the gateway now runs. It is there for a placement change, and evaluation covers it only once such a placement exists.
- The listener surface doubles with the placement: the gateway takes no client credential (consumers pass a placeholder), so each instance is an unauthenticated OpenAI-compatible endpoint reachable from the tailnet on its host. That posture is unchanged per host, but it now exists on two, and admission control on either listener remains an open upstream question rather than something this change introduces or resolves.
- The `bifrost` secret file is service-scoped and shared, so home-forge's activation depends on the operator adding its recipient to that file first; a deploy before that step fails at decryption rather than silently running without credentials.

**References:**

- `modules/hosts/home-forge/default.nix`, `modules/hosts/home-forge/_nixos.nix`
- `modules/observability/latitude.nix`, `modules/knowledge/hindsight.nix`, `modules/database/postgres/_consumer.nix`
- `.sops.yaml`, `tests/fixtures/secret-scope.nix`, `tests/check-bifrost-gateway-contract.sh`, `tests/check-dendritic-scaffold-contract.sh`
- nix-fleet `649554fc0`: `lib/local-endpoint.nix`, `docs/contracts/bifrost.md`, `docs/contracts/services.md`

## D-088: The Langfuse leg receives vendor keys mapped from canonical carriers, and the duplicates it does not read are pruned

**Status:** Accepted; implemented in `modules/flake/telemetry.nix` and verified by a local Collector 0.155.0 run through the rendered route pipelines. Revises the Langfuse half of D-084. Not deployed.

**Context:** The producer (pi-otel) emits canonical `gen_ai.*` and `pi.*` attributes together with Langfuse- and Latitude-specific keys carrying the same content. The mapping document (pi-otel `docs/attribute-mapping.md`) fixes which vendor keys a collector transform can rebuild from canonical fields, and which it cannot: JSON wrapping and span-kind knowledge need a Lua processor, and the Collector's OTTL functions neither escape nor encode JSON.

**Decision:** The AI route's rich leg maps the rebuildable Langfuse keys from canonical carriers, without overwriting any key the exporter already wrote. It copies `langfuse.trace.name`, the Langfuse observation output of an LLM span and the observation input and output of a tool span, and the eight `pi.*` metadata fields as `langfuse.trace.metadata.*`, cut to 256 characters. It appends the four `prefix:value` trace tags, each guarded by its attribute and a 200-character limit. It removes the canonical duplicates Langfuse reads through its vendor keys, only where those keys are present. The Latitude leg takes `latitude.capture.name` from the root span name and drops the `langfuse.*` keys, and the VictoriaTraces leg drops the raw `pi.user_prompt` along with the other content carriers. Rows that need JSON encoding or span-kind knowledge stay exporter-emitted, as the mapping document requires.

**Alternatives considered:**

- **Build the JSON-encoded keys in a Lua processor** — rejected for now: it moves the producer's business logic into the collector, which the mapping document excludes, and the rows it would cover are a small share of the duplication.
- **Remove the exporter's vendor keys at the source** — rejected: the rows that need JSON encoding would then vanish from Langfuse and Latitude, so the source keeps them until a collector can rebuild each one.

**Consequences:**

- The Langfuse leg loses the canonical duplicates it reads through its own keys; a Langfuse-side read of `gen_ai.*` content is no longer exercised. The pruning is safe only if Langfuse reads the vendor keys in its events-only mode, and that is taken from the mapping document, not yet proven on the deployed backend.
- Canonical-key copies never overwrite an exporter value, so a producer that already writes a vendor key is unaffected.
- The probe covered the copy, pruning and tag paths; it did not exercise the 200-character tag guard or the 256-character cut on a non-ASCII value, and it does not prove the composition on the deployed Collector.

## D-089: Delta metrics are made cumulative on the local OTLP metrics pipeline, after identity enrichment

**Status:** Accepted; adopted by bumping nix-fleet to `e5d74415`, which carries the upstream implementation (`lib/telemetry-otel-collector-common.nix`, `modules/telemetry/otel-collector.nix`, `docs/contracts/telemetry.md`). Evaluated on home-forge; not deployed.

**Context:** Pi's OTLP metrics are delta by default. The `prometheusremotewrite` exporter translates only cumulative sums and histograms, so every Pi series was dropped at translation and never reached the store. The failure was silent at the unit's info level.

**Decision:** The local OTLP metrics pipeline runs `deltatocumulative` with an explicit `max_stale = "5m"`, placed after `resource/telemetry-identity` so the stream identity it tracks is stable. Traces, the ingress and named-route metrics pipelines, and the scrape pipeline do not carry it. The processor is a no-op for cumulative streams. Pi's temporality preference is not changed on any host.

**Alternatives considered:**

- **Set `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative` in the producer** — rejected: it changes every consumer and breaks the per-run counter model of short-lived Pi child processes.
- **An OTTL or Lua transform** — rejected: temporality is the only defect, so a transform adds a second mechanism for no gain.

**Consequences:**

- The change covers Pi without any gateway edit: Pi exports to its host's loopback producer endpoint (`services.telemetry.otlp.httpUrl`), so its delta metrics are converted on the producer's own host, before the remote write that used to drop them. Only a producer that publishes deltas directly to the gateway ingress or to a named route is still dropped at the exporter; no fleet producer does that today, and the upstream contract records the case as open pending a decision with the gateway owner.
- The processor reaches a host when that host is switched, not when the pin moves. A host whose running collector predates the change keeps dropping Pi series until it is activated.
- A delta stream silent for longer than five minutes restarts from zero. That is intended for per-run Pi counters.

## D-091: User applications authenticate at the application rather than the edge

**Status:** Accepted; implemented for Actual Budget, Memos and tududi on `oci-melb-1`, not deployed.

**Evidence:** Confirmed packaging and exposure choices; Memos' file-loader contract is source-backed. Actual/tududi signing compatibility is inferred from their client libraries and remains subject to live login verification.

**Source:** `openspec/changes/add-actual-memos-tududi/design.md` and `docs/research/actual-memos-tududi-upstream-facts.md`.

**Verification:** Uncorroborated on a running host; evaluated wiring and placement checks pass, but the full scaffold gate is blocked by the absent tududi encrypted secret.

**Decision:** Use native nixpkgs services for Actual Budget and Memos and a digest-pinned container for tududi. Publish all three through loopback-backed `direct` routes, with Kanidm application login and no Cloudflare Access gate. Keep Actual's password method alongside its preview OpenID integration. Render Memos' provider as a root-owned sops template, load it as a systemd credential, and bind the unit's private credential directory at its fixed `/etc/secrets` path. Direct symlink delivery failed because the shared rendered-secret directory was `0750 root:root`; widening that directory is rejected. The explicit `/run/credentials/memos.service` bind was verified with a non-secret fixture on OCI under the service sandbox; `%d` was rejected in the bind setting. Keep tududi's bootstrap email with its application secrets, not as host configuration; an omitted email leaves bootstrap disabled.

**Alternatives considered:** Cloudflare Access in front of these applications was rejected because sync, mobile and API clients cannot be assumed to carry its browser session. A manual Memos provider was initially planned because its documentation emphasized instance settings; source verification established the pinned version's file loader, so manual configuration is retained only as a live-deployment fallback.

**Consequences:** Public routes rely on the application's own authentication and must pass real login and client checks before acceptance. Memos file access under its systemd sandbox remains unverified. A fallback provider belongs to its database and is lost on a bare reimage without database restoration. Primary SQLite databases use export-first backups; Actual's raw user-file consistency remains unresolved. The operator must prepare the tududi secret file and three host-scoped OAuth2 client secrets before rollout. See `docs/runbooks/actual-memos-tududi.md`.

## D-090: Routine CI is validation-only, and package pins move through nix-fleet's package-updates contract

**Status:** Accepted; adopted while the nix-fleet pin already equalled upstream `main` (`e5d74415`). Nothing deployed.

**Context:** nix-fleet's current CI contract keeps routine push and pull-request validation evaluation-only and puts building checks against the fleet's configured builders in a separate, manually dispatched path. Its package-update contract replaced nvfetcher with one native interface: a published flake module over `nix-update`, with each repository registering the package outputs it owns. This repository still carried the older shape of both — the fleet build as a job inside `ci.yml`, and nvfetcher scaffolding (`nvfetcher.toml`, `pkgs/_sources/`, a weekly refresh workflow, a `just deps` recipe) that owned no source at all.

**Decision:** The fleet build moves to `.github/workflows/fleet-build.yml`, dispatched by hand and only on `main`, calling `ci.yml` as a reusable workflow so validation still gates a privileged publication. `ci.yml` keeps validation and can no longer build fleet outputs on any event; it still builds its own two sandboxed tools (the formatter check and the `flake.nix` freshness comparator), as nix-fleet's validate job builds its formatter check. `modules/flake/package-updates.nix` imports nix-fleet's package-updates module and registers `windows-dj-setup`, the only package this repository owns; that package gains a `passthru.updateScript` refreshing its two coupled pins (WinFsp and Mesa) through `pkgs/windows-dj-setup/update.py`, and a `passthru.checkUpdate` reporting the newest stable WinFsp version, which is also the package's `version` carrier. nvfetcher is removed outright — config, generated directory, refresh workflow, `just deps` recipe and its import, and the treefmt exclusions — and the scheduled refresh becomes the contract's workflow, evaluating the registered package's derivation rather than a whole-flake check.

**Alternatives considered:**

- **Keep the build job in `ci.yml` behind a dispatch condition** (nix-fleet's own arrangement) — rejected: it makes "routine CI does not build" a property of one condition rather than of the file's shape; this path has already been mis-scoped once, which is why a branch-dispatch guard exists at all.
- **Adopt the contract's whole-flake evaluation gate verbatim** — rejected: evaluation alone cannot pass on a cold store here, because evaluating this flake realises degoog's unsubstitutable bun2nix import-from-derivation (D-082).
- **Drop the `flake.nix` freshness comparator from validation** — rejected: it is a real PR-time gate and costs seconds.
- **Leave the nvfetcher scaffolding dormant** — rejected: it would leave two canonical updaters for one dependency class while owning no source, and keep a `just` module, a scheduled workflow and two treefmt exclusion lines alive to serve nothing.
- **Register no package** — rejected: the batch refuses an empty selection, and the pins would keep drifting by hand.
- **Use nix-update's standard discovery for `windows-dj-setup`** — rejected: the derivation has no single `src` and two upstream repositories, so the package owns its release discovery.

**Consequences:**

- A pull request can no longer reach the fleet build at all, and a branch dispatch is refused by the workflow's own main-only condition as well.
- Two stale canonical specs are corrected in the same change: `dependency-source-management` (nvfetcher → the package-updates contract) and `nixbuild-build-plane` (nixbuild.net, and a substitution-only framing → the fleet's own builders and substituters). The latter's file name no longer describes its content; renaming a main spec is left to a separate change rather than taken silently here.
- Nothing is deployed and no host or secret changes. The DJ VM's setup media content is unchanged; only how its pins are refreshed.

## D-092: Homarr is the user-facing dashboard beside operator Homepage

**Status:** Accepted; implementation in progress on `oci-melb-1`, not deployed.

**Evidence:** User-facing placement and per-user OIDC requirements are confirmed. The pinned v2.5.2 release, secret formats, OIDC callback path, and environment behavior are source-backed. Live authentication and restore remain unverified.

**Source:** `openspec/changes/add-homarr-dashboard/design.md`; Homarr v2.5.2 [environment example](https://raw.githubusercontent.com/homarr-labs/homarr/v2.5.2/.env.example), [environment variables](https://homarr.dev/docs/advanced/environment-variables), and [single sign-on](https://homarr.dev/docs/advanced/single-sign-on) documentation.

**Verification:** The placement contract evaluates the pinned image, OIDC environment, callback URIs, withheld route, and SQLite export. No service secret has been provisioned and no live login or restore has been performed.

**Decision:** Deploy released Homarr v2.5.2 as a digest-pinned OCI container managed by the NixOS `homarr` aspect on `oci-melb-1`. Keep it separate from operator Homepage: Homarr owns user accounts, groups, boards, and per-user home boards through its UI, while the fleet owns the service runtime, canonical route, OIDC client, encrypted secrets, and backup. Use Kanidm OIDC without Cloudflare Access, keep Homarr's local group management enabled, and explicitly disable dangerous OIDC credential linking. Keep the public route withheld while a disabled-by-default credentials option permits private first-admin setup through the provider's Tailscale Serve URL. Register both the public callback and private HTTPS callback with Kanidm. During bootstrap, `BASE_URL` follows the private origin; in steady state it follows the public origin, while `NEXTAUTH_URL` remains unset so the callback is derived from request headers. Persist distinct `AUTH_SECRET` and `SECRET_ENCRYPTION_KEY` values in the service-scoped encrypted file. Export SQLite through its backup API and exclude the live database directory from raw capture.

**Alternatives considered:** Replacing Homepage was rejected because the two dashboards serve different audiences. Generating Homarr's boards from web policy was rejected because it would duplicate route ownership and remove the requested per-user, UI-managed workflow. Cloudflare Access was rejected because Homarr already owns browser authentication and an edge login would complicate its OIDC flow. Maintaining a local Nix build was rejected in favor of the official immutable image: nixpkgs has no Homarr package, and the repository does not need to own the full web-app build to declare its runtime reproducibly.

**Consequences:** The public route cannot be released until the private Kanidm login and per-user authorization checks pass. The operator must prepare the two persistent secret files and preserve the exact Homarr keys with its database state. UI-managed links can drift from canonical web policy and need manual updates. Restore the pre-upgrade database before rolling back an image after Homarr migrations. See `docs/runbooks/homarr.md`.

## D-093: ClickHouse returns to the host package set

**Status:** Accepted.

**Context:** The dedicated `nixpkgs-clickhouse` pin existed because this baseline's ClickHouse failed at the final link — ClickHouse's own `cmake/strip_rust_symbols.sh` corrupting the Rust staticlibs under LLVM 21.1.8 (D-080). That condition has gone: the packaging now builds with `llvmPackages_22` rather than the baseline's default toolchain, and the package it derives substitutes again.

**Evidence:** At the current baseline, `pkgs/by-name/cl/clickhouse/generic.nix` sets `llvmPackages = llvmPackages_22`. The baseline evaluates `clickhouse-26.8.7.19-lts` to `/nix/store/g6ffa90mzkqym0pf7ycynjwjhmrhrw92-clickhouse-26.8.7.19-lts.drv`, output `/nix/store/lg4lv7dkq2rfk2f3gp6s36bd7132cg4s-clickhouse-26.8.7.19-lts`, which cache.nixos.org serves and the fleet cache carries — no host builds it locally.

**Decision:** ClickHouse comes from the host package set. The `nixpkgs-clickhouse` input is dropped, `repo.packages.clickhouse` with it, and both call sites read `pkgs.clickhouse`: the Langfuse module binds `services.clickhouse.package`, and the Latitude database-init client takes its `clickhouse-client` from the same package. `renovate.json` loses the rule that kept the retired input frozen.

**Alternatives considered:** Keeping the pin was rejected — it held a second nixpkgs node plus an indirection between two call sites for a condition that no longer holds, and it would need re-verifying at every baseline. Keeping `repo.packages.clickhouse` as an alias of `pkgs.clickhouse` was rejected for the same reason: an indirection with one possible value.

**Consequences:** `tests/check-dendritic-scaffold-contract.sh` asserts the pin and the projection are gone, that neither call site names the projection, and that the ClickHouse server home-forge deploys is the host package set's own derivation. If a future baseline reintroduces the link failure, the workaround is D-080's shape — a pinned revision, a projection, and both call sites reading it.

## D-094: The rescue password secret lives at sops-nix's `neededForUsers` default

**Status:** Accepted.

**Context:** `host_recovery_rescue_password_hash` is the fleet's only `neededForUsers` secret, and it carried an explicit `path = "/run/secrets/host-recovery.rescue_password_hash"`. Verification on la-admin-1 after the systemd activation switch, and on home-forge under the legacy activation path, found that symlink absent while the file itself sat at `/run/secrets-for-users/host_recovery_rescue_password_hash`. The digest of that file still matched the hash applied to the rescue account on both hosts, so the password was applied by ordering luck rather than by the configured path.

**Evidence:** sops-nix's `secrets-for-users` manifest sets `symlinkPath = /run/secrets-for-users` and `secretsMountPoint = /run/secrets-for-users.d`; `symlinkSecretsAndTemplates` creates each secret's configured path as a symlink into that directory, while the *regular* manifest's run swaps `/run/secrets` for its own generation directory (`atomicSymlink(secretDir, "/run/secrets")` in `pkgs/sops-install-secrets/main.go`). A `neededForUsers` symlink placed under `/run/secrets` therefore dies with the directory it was created in. On la-admin-1 (systemd activation) the swap runs after the activation step that installs this file, so nothing else could read it afterwards; on home-forge (legacy activation, where both installs are activation snippets) it is absent as well.

**Decision:** Drop the `path` override and let the secret sit at sops-nix's default, `/run/secrets-for-users/<name>` — outside the directory the regular installer swaps. `hashedPasswordFile` keeps reading `sops.secrets.<name>.path`, which now names the durable location.

**Alternatives considered:** Setting the default path explicitly was rejected as redundant. Ordering an extra activation dependency to protect the symlink was rejected because it would preserve a dependency on install order for a path sops-nix already publishes correctly.

**Consequences:** The rescue password no longer depends on the users step running between the two installs. `tests/check-shell-account-contract.sh` asserts every rescue secret's path sits under `/run/secrets-for-users` and equals the account's `hashedPasswordFile`, with a control that must reject the old path.

## D-095: The 19 October PostgreSQL switch failure stays unreproduced, and the provisioning shape is unchanged until reproduced

**Status:** Accepted. Investigation closed as unreproduced. The provisioning unit keeps its two-unit shape; the binary-identity wait is removed.

**Context:** On 2026-10-19 the `oci-melb-1` deploy of the generation built from `fe13242` failed activation. `postgresql-provision.service` reported `server runs '…v4vm1…-postgresql-and-plugins-17.11/bin/postgres', expected '…7g8f51…-postgresql-and-plugins-17.11/bin/postgres' after 60s`, `switch-to-configuration` returned status 4, and deploy-rs rolled back to generation 330. The database was intact: a provisioning run after the server restarted succeeded. The open questions were what made the switch restart the server late and why the failing provisioning guard ran before the server had restarted.

**Evidence:**

- Closure diff, generation 330 → the failing generation (verified from the store): the `postgresql.service` binary changed (rebuilt plugin set, `v4vm1` → `7g8f51`); the provisioning script changed (0 → 14 `geopulse` references, a new consumer); `postgresql.service`'s `X-Restart-Triggers` changed (its content is the provisioning script path); the new sops secret `postgres_geopulse_password` carries `restartUnits = postgresql-provision.service`; and `unit-postgresql-provision.service` is byte-identical between the two generations.
- The switch's stop list named `postgresql.service` and `postgresql-setup.service`; its restart list named `postgresql-provision.service`. The Postgres stop ran at 02:13:25.716, after both 60-second guard runs had failed and deploy-rs had begun rolling back.
- VM reproductions (nixosTest, `switch-to-configuration test`, `dbus-monitor` on `JobNew`/`JobRemoved`) did not reproduce the late stop: a stock `services.postgresql` unit change; the fleet postgres module with a unit-only change; the same with a rotated consumer secret; and a mirror of the generation 330 → failing generation changes (new binary, new consumer with an extension, new secret, script change). Every job completed `done`, the server restarted in the stop phase, and provisioning ran once in the restart phase and succeeded.
- A live switch on `oci-melb-1` to a rebuilt generation carrying the same Postgres changes (`STC_DEBUG=1 STC_DISPLAY_ALL_UNITS=1`, job trace captured) exited 0 with no failed units. Postgres was not in the stop list because the running unit already matched, and provisioning finished `success`.

**Decision:**

1. The failure is recorded as unreproduced. No mechanism is claimed. Statements not supported by the evidence are: that a skipped or late stop explains the failure, that `After=` is at fault, and that a job-queue block explains the 60-second wait.
2. The provisioning unit keeps its shape: a separate oneshot, ordered by `requires`/`after` on `postgresql.service` and `postgresql-setup.service`, and re-run through `partOf` when postgresql restarts. Its script trigger stays on `postgresql.service`, and its consumer secret keeps `restartUnits`. Ordering is left to systemd's documented behaviour, including the case where a restart is queued in the same switch.
3. The binary-identity wait (the 60-second loop in `modules/database/postgres.nix`) is removed. It converted a switch-ordering question into a timed failure and hid where the ordering broke. Without it, the script applies its SQL to whichever server is live when it starts. A consumer whose extension the live server lacks fails loudly at `CREATE EXTENSION`, which is the observable signal.
4. Observability for the next occurrence is a nix-fleet concern. This repository only selects the producers once they exist.
5. `ExecStartPost` on `postgresql.service` remains a possible later shape. It is not adopted: it would remove the separate unit, which this decision keeps for reproduction, and it would change the failure semantics of the database server.

**Alternatives considered:**

- Keeping the wait was rejected: it turns a visible ordering failure into a timed one and hides the ordering behaviour.
- Moving to `ExecStartPost` now was deferred: it removes the unit whose ordering is being examined, and no reproduction yet shows it fixes the observed failure.

**Consequences:** `oci-melb-1` runs a generation built from the same Postgres changes, so its next Postgres unit change is the natural reproduction point. The VM reproduction files are in `/tmp/stc-repro` (outside the repository) and are reconstructible from this entry.

## D-096: The PostgreSQL substrate installs only the extensions its consumers keep, so a consumer's own migration can create and drop its own

**Status:** Accepted. Implemented in `modules/apps/inbox-zero.nix` and verified on `oci-melb-1`.

**Context:** The Inbox Zero deployment served a partial schema for six days. `inbox-zero-watch-renewal` failed with `curl: (22) … 500` and `inbox-zero-scheduled-actions` returned 500 on every run, because the database had no `EmailAccount` or `ScheduledAction` table. Prisma's `_prisma_migrations` showed one unresolved row: `20240116235134_shared_premium` failed with `must be owner of extension uuid-ossp` (SQLSTATE 42501), which blocks every later migration. The consumer's `setupSQL` had created `uuid-ossp` as the cluster superuser, and the migration's final statement is `DROP EXTENSION "uuid-ossp"` — only the role that created an extension may drop it, so the migration could never complete.

**Evidence:**

- `_prisma_migrations`: 13 rows, `20240116235134_shared_premium` with `finished_at` null and `rolled_back_at` null, log text naming the SQLSTATE and the ownership error.
- The image's `/app/apps/web/prisma/migrations/20240116235134_shared_premium/migration.sql` creates `uuid-ossp` at line 39 and drops it at line 73.
- `pg_extension` before the fix: `uuid-ossp` and `btree_gist` owned by `postgres`; the database `inbox_zero` owned by the application role.
- `uuid-ossp.control` in the pinned `postgresql-17.11` carries `trusted = true`, so the database owner may create it without superuser.
- Recovery on `oci-melb-1`: drop the superuser-owned extension, `prisma migrate resolve --rolled-back`, restart. The log then read "All migrations have been successfully applied", applied migrations went 12 → 213, `EmailAccount`/`ScheduledAction`/`Premium` exist, `uuid-ossp` is absent, and both maintenance units returned `Result=success`.
- The database held 0 rows in `User`, `Account` and `Rule`, and the failed migration had rolled back cleanly (no `Premium` table), so the retry ran against an empty schema.

**Decision:** A consumer declares in `setupSQL` only the extensions it keeps for the life of the database. An extension that the application's own migrations create and drop is left out, so the application role owns what it drops. Inbox Zero therefore installs `btree_gist` only.

**Alternatives considered:**

- Transferring ownership with `ALTER EXTENSION … OWNER TO` was rejected: PostgreSQL has no such clause for extensions.
- `REASSIGN OWNED BY postgres TO inbox_zero` was rejected: it reassigns every object the superuser owns in that database, far beyond the one extension.
- Installing `uuid-ossp` and patching the migration was rejected: the migration lives in the pinned image, and forking it would drift from upstream's schema history.
- Resolving the migration as applied was rejected: it skips the …shared_premium… DDL the later migrations build on.

**Consequences:** A consumer whose migrations touch an extension it does not own fails the same way, so the rule is recorded here rather than in one module. The substrate stays generic: it installs what it is told and does not infer ownership. Recovery needs `prisma migrate resolve --rolled-back` inside the container before the retry, because upstream's `start.sh` logs a `migrate deploy` failure and starts the application anyway; that procedure is in `docs/runbooks/inbox-zero.md`.

## D-097: Secret activation is a fleet aspect bound over nix-fleet's policy, not a per-host option

**Status:** Accepted. Prepared in the repository; each host takes it on its next deploy.

**Context:** NixOS 26.11 removes the activation-script restart path (`/run/nixos/activation-restart-list`) that `sops-nix` used by default. nix-fleet adopted systemd secret activation as fleet policy and documented the consumer's contract in `docs/patterns/systemd-lifecycle.md`: a service binding a regular SOPS secret orders after and wants `sops-install-secrets.service`, and no module branches on the activation mode. la-admin-1 had been running the systemd path alone through an explicit `sops.useSystemdActivation = true`, which is exactly the per-host divergence that contract forbids.

**Evidence:**

- All three hosts evaluate `sops.useSystemdActivation = true` and enable `sops-install-secrets.service` after selecting the aspect.
- The installer ordering now renders on `geopulse-backend`, `podman-homarr`, `memos` and `bifrost` (both hosts that place it).
- An audit of rendered units referencing `/run/secrets` counts 19 on oci-melb-1, 12 on home-forge and 6 on la-admin-1; 33 of the 37 have no explicit edge, and all are units this repository does not own (`paperless-*`, `niks3-*`, `notify`, `beets-*`, `clickhouse`, `degoog`, `kanidm`, `vaultwarden`, `restic-backups-state`, the OTLP collector).
- la-admin-1 ran the systemd path in production for several deploys before this change, which is what made a fleet-wide flip safe to consider.

**Decision:** `modules/flake/sops-systemd-activation.nix` publishes the aspect name and imports nix-fleet's module, and every host record selects it. No host sets `sops.useSystemdActivation` itself.

**Alternatives considered:**

- Setting the option per host was rejected: it is the divergence the upstream contract names, and it makes a host's secret semantics invisible to the fleet.
- Folding it into `base` was rejected: `sops-nix` is a host import, so a fleet-baseline module would have to assume it is present; an aspect makes the dependency explicit at selection.
- Adding the explicit installer edge to all 33 upstream units was deferred: the installer is `WantedBy sysinit.target` and ordinary units inherit `After=sysinit.target` from `DefaultDependencies`, so the edge restates a guarantee for them. Making the contract literal everywhere stays available if an early-starting unit ever needs it.

**Consequences:** Secret semantics are the same on every host, and the nix-fleet lock already carries the policy commit. Two things remain unproven until the hosts deploy: that a consumer-secret rotation still re-runs PostgreSQL provisioning (its `restartUnits` used the legacy `try-restart` path), and that the ordering edges render as expected in the live unit graph. nix-fleet's own `notify`, `restic-backups-state` and `niks3-auto-upload` units carry no explicit edge either; that belongs upstream rather than being patched here.

## D-098: A route is published by the policy's own `publicReady`, with no host-side release switch

**Status:** Accepted. `services.geopulse.publicReady` and `services.ingress.releasedRoutes` deleted; verified on the oci-melb-1 edge.

**Context:** GeoPulse's route was withheld by two independent switches. `policy/web-services.nix` declared `publicReady = false`, and the aspect offered `services.geopulse.publicReady`, which registered the route in `services.ingress.releasedRoutes`; the ingress filter served a route when `svc.publicReady or true` **or** its name was in that list. Releasing GeoPulse therefore meant overriding the policy from a host record, while the policy still said the route was not ready. Homarr, declared later, released through the policy flag alone.

**Evidence:**

- `releasedRoutes` had exactly one producer (GeoPulse) and one consumer (the ingress filter), so it was a general mechanism with a single user.
- The evaluated edge served no `geopulse` route while the gate was closed and 31 other routes normally, which is indistinguishable from the policy's own answer.
- After removal the GeoPulse contract still proves the released shape: rendering the route from the resolved policy record with `publicReady` flipped produces the 17 denial matchers, the loopback upstream and the direct canonical host.
- The filter's `or true` default published any route that forgot the field, which is the wrong way to lean on a security-relevant bit.

**Decision:** Publication is one fact, `publicReady` on the route in `policy/web-services.nix`. The edge serves a route exactly when it is true. A second switch, and the ingress list that carried it, are gone.

**Alternatives considered:**

- Keeping the two-key release (policy identity plus host release) was rejected: both edits land in the same reviewed change, so the second key adds no gate, only a second place to look.
- Adding an option for the release list to the *policy data* so a test could flip it was rejected: it would put a knob back for the sake of a test.
- Releasing through a mutated tree copy in the test was rejected for this repository, where `.#` reads the Git index and a copy evaluates a different tree.

**Consequences:** The edge route projection moved to `modules/web/_ingress-routes.nix` so the ingress module and the tests that render a withheld route share one function; the GeoPulse test now releases the route the way production does. The rule generalises: an option that exists to be flipped after an imperative step is acceptable only when the fact it mirrors cannot be read from the repository — Homarr's first-administrator window is that case, because the fact lives in Homarr's database; GeoPulse's did not, because policy already held it.

## D-099: Cache pins are reserved per calling repository, and the cache's own metrics are collected on its host

**Status:** Accepted. Rendered and verified: three OIDC rules with `pins`, and a `niks3` scrape job on oci-melb-1.

**Context:** Push access to the niks3 cache API is federated to GitHub Actions with OIDC, and one provider rule bound all three calling repositories (`nix-fleet`, `nix-homelab`, `nix-dotfiles`) to a single `write` scope. A niks3 pin is *not* covered by a scope: niks3's own documentation for the option states that any token holding `write` may create or repoint any pin that no rule reserves. So a token minted for one repository could move another repository's `main` pin — the name a consumer reads as "the fleet's current main".

**Evidence:** The pinned niks3 (`27d6bdb`, module `nix/nixosModules/niks3.nix`) exposes `pins` on a provider and on each entry of `rules`, described as "pin names (glob patterns) reserved for boundClaims/boundSubject: a pin that matches can then only be created or moved by a token this provider matches, or by an admin. Other pins still need write only". `server/oidc/config.go` rejects a rule whose `pins` are set without `write`/`admin`, and a provider that sets both `rules` and top-level claims. The rendered config file for oci-melb-1 carries the three rules and no top-level claims.

**Decision:** One rule per calling repository. Each rule keeps the shared claims — owner ID, `refs/heads/main`, and the one workflow that mints a pushing token (nix-fleet's `build-push-cache.yml`) — names its own repository, grants `write`, and reserves that repository's pin namespace as `<repository>-main-*`. A pin therefore reads as `<repository>-main-<system>` (`nix-fleet-main-aarch64-linux`), and only that repository's CI identity or an admin token can create or move it.

**Alternatives considered:**

- Keeping one provider-level rule and reserving all three namespaces together was rejected: it still lets any calling repository's token move any other repository's `main` pin, which is the risk being closed.
- `boundSubject` patterns instead of claims were already rejected earlier: GitHub mints `sub` in two forms, and the immutable form (used by repositories created on or after 2026-07-15) does not match the older `repo:owner/*` shape.

**Consequences:** The pin names are a convention the build plane has to create; nothing creates pins yet, so the reservation is inert until nix-fleet's `build-push-cache` workflow publishes them. The reservation is deny-by-default for those names in the meantime.

The same change registers the cache's own metrics. `GET /metrics` is served by the same listener as the cache API and is unauthenticated like `/health` (niks3's monitoring documentation), so the host that runs the cache scrapes itself over loopback through nix-fleet's telemetry contract. No new exposure is added — the port is the one the private service policy already declares, and the scrape target is loopback.

The board is niks3's own, not one authored here: the flake input already publishes it as `dashboards.niks3`, so the store reads it from `inputs.niks3.dashboards.niks3` and rewrites it on the way in exactly as it treats the other upstream boards. Two rewrites are needed. The board is written for an `instance` label while every series this fleet scrapes carries the canonical host ID as `host`, so the variable, its `label_values` query, every selector and every aggregation move to that name. And its `Last GC` panel subtracts a comparison from the clock (`time() - (gauge > 0)`), which on a server that has not collected yet renders the epoch age — roughly 55 years — while the panel's own description promises "none yet"; a 1.15.0 server reports the gauge as `0` rather than omitting it (observed: `niks3_gc_last_run_timestamp_seconds 0`, with 137,311 objects and 465 GB cached), so the mask divides instead and the panel reads no data until a run completes.

Authoring a board was the first attempt and was dropped: the input's board covers the same ground with more panels (requests by route and status, latency mean and p90, storage and garbage collection, skipped uploads) and moves with the pin that ships the server it describes.

## D-100: Home Assistant runs as the upstream container, not the nixpkgs Core module

**Status:** Accepted. Module, route, pin and contract test landed; not deployed.

**Context:** Home Assistant had to be placed on `home-forge`. Two installation methods are available in Nix: nixpkgs' native `services.home-assistant`, which renders `configuration.yaml` from Nix and pulls every integration dependency into the package, and the project's own container image.

**Evidence:** Home Assistant's ADR-0012 lists the supported installation methods, and Core-on-a-distro is not among them; the nixpkgs module carries that caveat in a comment and the upstream project closes issues that are not reproducible on a supported setup. The nixpkgs maintainers state they will keep supporting it, and at the pinned nixpkgs the module ships Home Assistant 2026.10.1 with complete built-in integration coverage, custom components (including `auth_oidc`) and Lovelace modules — so the native route is genuinely functional, not a fallback.

What decides it is where Home Assistant's state actually lives. Modern Home Assistant keeps integrations, users, tokens and dashboards in `.storage`, and history in a SQLite recorder database; the native module makes `configuration.yaml` declarative but leaves that state imperative, so an operator configures the instance through the UI either way. The native module's real cost is instead that each Home Assistant release rebuilds its Python closure, and its version moves with nixpkgs rather than with the project's release cadence.

**Decision:** Place the container, pinned by tag and digest in `policy/oci-images.nix` and bumped by Renovate. The container shares the host network namespace (`--network=host`) rather than publishing a port, because discovery integrations (HomeKit, Chromecast, Hue, Matter, ESPHome) need the LAN's own namespace; this is the shape upstream's container documentation and the nixpkgs wiki both show. The configuration directory `/srv/data/home-assistant` is created mode `0700` and otherwise untouched by Nix: Home Assistant writes its own minimal `configuration.yaml` on first start, and the operator owns everything below it.

The option namespace is `services.hass`, not `services.home-assistant`. nixpkgs owns that path for its native module, and one option name meaning two different installations depending on which module a host imported is a trap; the aspect is still named `home-assistant`, so host records read naturally.

The recorder keeps SQLite to start. Home Assistant's own guidance is that an external database matters for large installations; the fleet's `forge` cluster is available as a later migration (`recorder.db_url`), and joining the consumer registry is one module edit when history volume justifies it.

**Alternatives considered:**

- The nixpkgs Core module was rejected on the balance above: it makes a minority of the configuration declarative, while every release costs a large rebuild and each integration addition is a rebuild rather than a UI action. It remains the better choice for an instance whose integrations are all YAML-declared and stable.
- Publishing only `8123` over a bridge network was rejected: discovery integrations mostly stop working without host networking, and per-device manual host/port entry is a worse trade than the container's already-wide network grant.
- Kanidm OIDC was deferred rather than declined. It needs the `hass-oidc-auth` custom component inside `/config`, which Nix does not manage for a container, so putting it in the authentication path before the instance is proven buys risk, not parity.

**Consequences:** The route is declared with `publicReady = false` and reached on the tailnet at the provider's port until onboarding is accepted, then released by flipping that one policy field — the same single edit Homarr uses, with no host-side switch. Publishing additionally needs `use_x_forwarded_for` and a pinned `trusted_proxies` entry in `configuration.yaml`, which the runbook records because it is operator-owned state. The container is registered with `services.notify.events` so a crash loop reaches the notifier, and its recorder database is exported through SQLite's online backup API while the database and its WAL sidecars are excluded from the raw copy of the directory.

## D-101: A route's publication is a posture field (`publish`), not a readiness flag

**Status:** Accepted. Supersedes the *name* in D-098; the decision it records — one field, no host-side release switch — stands.

**Context:** D-098 left publication as `publicReady` on the route in `policy/web-services.nix`. The mechanism was right, the name was not: `publicReady` describes where a human has got to in an acceptance process ("is it ready yet?"), so the policy file carried a lifecycle state rather than an intent. A declarative configuration should state the desired posture; the process that leads to it belongs in a runbook.

**Evidence:** It is not an upstream idiom. In the pinned nixpkgs, options named for lifecycle state are essentially absent (a single `ready` and a single `bootstrap` across `nixos/modules`), while the attribute names in use are intent-shaped (`enable`, and per-capability `*Enabled`). The two switches D-098 deleted were also state-named (`services.geopulse.publicReady`, `services.ingress.releasedRoutes`), so this was the last one left.

**Decision:** The field is `publish` on the route record, defaulting to true: declaring a route at all *is* the publication declaration, so withholding is the exception that has to be written down. `publish = false` reads the same way as `enable = false` — an instruction about the desired state, with no claim about whether anyone has finished a process. The runbooks keep the acceptance steps; the policy file keeps the posture.

**Alternatives considered:**

- Collapsing publication into the fields that already exist — declaring a withheld route `tailscale-only` + `declarePublic = false` — was rejected on a concrete cost: `publicUrl`/`publicHost` are null for a service that is not public, and those values are exactly what a withheld deployment still needs. The registered OIDC redirect URI derives from `publicUrl`, as do the ntfy base URL, the operator homepage links and cockpit's host. A withheld route must keep its public identity while the edge serves nothing, so the two axes have to stay separate.
- `forcePrivate` was rejected as a name: "force" reads as definition priority (`mkForce`) in Nix, so the field would look like an override mechanism rather than the posture itself.
- Defaulting `publish` to `false`, so a route must opt in to being served, was rejected: every one of the fleet's published routes would need the line, and the failure mode of the safe default is a route that silently answers nothing because someone forgot it.

**Consequences:** Withholding and releasing are one field either way, so the working shape is unchanged; what changes is that the file now says what the system should be, and `just checks` pins that posture rather than a stage. The rename touched the ingress filter, the three withheld routes (`geopulse`, `homarr`, `home-assistant`), their contract tests, and the runbooks.

## D-102: ClickHouse's HTTP port is fleet policy, and a host-networked collision fails at evaluation

**Status:** Accepted.

**Context:** Two facts collided on `home-forge`. Home Assistant runs with `--network=host` so discovery integrations can see the LAN, which makes it bind `0.0.0.0:8123` in the host's own port space. ClickHouse's HTTP interface defaults to `8123`, and on that same host Langfuse and Latitude both dial it there. The first Home Assistant deploy produced a container that was *up* and a port that answered `200` — because ClickHouse was answering — while Home Assistant had failed to bind, logged `Failed to create HTTP server at port 8123: address in use`, and dropped into recovery mode with no frontend. The switch then failed for a reason nothing in the repo could see: the ports were chosen in three files that never compared notes.

**Decision:** ClickHouse's HTTP port is declared once, in `policy/globals.nix` (`observability.clickhouseHttpPort = 8124`), and both the server's `serverConfig.http_port` and both consumers' URLs read it. Home Assistant keeps `8123`, the port its documentation, companion app and integration guides assume. When a host also enables a ClickHouse server, the Home Assistant module asserts that the two ports differ, so the collision fails at evaluation rather than at activation.

**Alternatives considered:**

- Moving Home Assistant's port was rejected: its listener is configured in operator-owned `configuration.yaml` (`http.server_port`), which Nix deliberately does not manage, and a non-standard port breaks the assumptions every guide and the companion app make.
- Bridged networking with published ports was rejected for the same reason host networking exists here — multicast discovery needs the LAN namespace — and the published port would still have collided on the loopback address ClickHouse holds.
- Single-sourcing the port in one of the two observability modules was rejected: the value is a property of the host that runs the server, both consumers are separate files, and the fleet's existing home for a shared non-secret constant is `policy/globals.nix`.

**Consequences:** Nothing else on the host moves, and the Langfuse/Latitude ClickHouse path keeps working across the rename — the guard proves the two ports differ. The assertion covers the pair that actually collided, not the class of host-networked port collisions: a new host-networked service must make the same check, and the module that introduces it owns that assertion.

A port declared in `policy/globals.nix` is only half the change, which the first deploy after this decision proved. `nixpkgs` renders `services.clickhouse.serverConfig` into `/etc/clickhouse-server/config.d/100-nixos-module-config.yaml` and the unit reaches it through the stable path `--config=/etc/clickhouse-server/config.xml`; the unit text is therefore identical between the old and new generation, `switch-to-configuration` compares unit files and nothing else, and the clickhouse module defines no `restartTriggers`. The server kept serving `8123` from the generation it had loaded days earlier while both consumers had moved to `8124`, and Latitude's fail-closed dependency gate — waiting on `10.255.0.1:8124` — was the first thing to notice, failing the activation. The trigger on the rendered file is now declared beside the port it follows. The same indirection hides a credential rotation: ClickHouse expands `include_from` once at startup, so the substitution template carries `restartUnits` for the server. Any service configured through `/etc/` rather than a store path baked into its unit needs its own trigger, and a rendered file that a process reads once needs a restart list.

## D-103: Homarr takes its groups from the Kanidm `groups` claim, requested as `groups_name`

**Status:** Accepted.

**Context:** Homarr ran with `AUTH_OIDC_GROUPS_LOCAL_MANAGEMENT=true`, which makes group membership local to Homarr. An administrator therefore had to be promoted by hand after their first OIDC login, and a person added to the fleet's admin group in Kanidm gained nothing there. The fleet's identity provider already knows the answer, and Kanidm can put it in the token.

**Decision:** Homarr requests the `groups_name` scope, reads the claim through `AUTH_OIDC_GROUPS_ATTRIBUTE=groups`, and follows it with `AUTH_OIDC_GROUPS_LOCAL_MANAGEMENT=false`. The scope is granted to the Homarr client's `service-admins` and `users` scope maps in `policy/identity.json`.

**Why the scope maps and not the supplemental ones:** Kanidm's `process_requested_scopes_for_identity` (server/lib/src/idm/oauth2.rs) rejects an authorize request unless every requested scope is present in the *scope maps* for the user's groups; supplemental scope maps are merged into the granted set afterwards and never authorise a request. A `groups_name` granted only as supplemental would therefore make Homarr's request fail rather than arrive empty.

**Why `groups_name`:** Kanidm always emits the claim under the key `groups`; the value shape depends on which variant was requested — `groups` gives UUID and SPN pairs, `groups_spn` gives `name@domain`, `groups_name` gives bare names. Homarr matches group names, and `service-admins` is the name both sides already use.

**Consequences:** Adding a person to `service-admins` in Kanidm grants admin in Homarr at their next login, and nothing needs re-issuing when the group changes. Homarr still joins only groups that already exist in its own database, so the `service-admins` group and its Administrator preset are created once, by hand — the one imperative step that remains. Sync is authoritative in both directions: an OIDC user is removed from Homarr groups the claim does not name (except `Everyone`), so any group an OIDC user must keep has to exist in Kanidm. The credentials administrator is not an OIDC user and is untouched by sync, which keeps it available as break-glass while `credentialsBootstrap` is still on.

## D-104: Homarr has no bootstrap switch; its posture is the route's `publish`

**Status:** Accepted.

**Context:** `services.homarr.credentialsBootstrap` existed to sequence a private bring-up: while `true`, `BASE_URL` pointed at the Tailscale Serve origin and `AUTH_PROVIDERS` allowed local credentials so the first administrator could be created; while `false`, both flipped to the public origin and OIDC only. It encoded a fact the repository cannot read — whether a first administrator exists, which lives in Homarr's SQLite database — so it had to be flipped by hand after an imperative step, and forgetting the flip left either a password login on a public route or an instance no administrator could reach. It was also the surviving case of the option class D-098 removed for GeoPulse and Homarr's own route.

**Decision:** The option is gone. `BASE_URL` and `AUTH_PROVIDERS` are derived from the route's `publish` posture in `policy/web-services.nix`: a withheld route is a private instance and keeps the private origin with `credentials,oidc`; a published route is public and OIDC-only. The posture reaches the aspect through the catalog: `lib/policy.nix` now carries `publish` on each catalog entry, defaulted the same way the edge filter defaults it, so a consumer never reads the provider-host record to learn whether its own route is served.

**Alternatives considered:**

- Keeping a boolean and renaming it was rejected: the name was never the problem. The value still mirrored an unreadable database fact, and a rename would preserve the failure mode D-098 rejected for GeoPulse.
- Always OIDC-only was rejected. Homarr's first user becomes administrator only through credentials onboarding; with an OIDC-only provider the onboarding skips the user step to an external-group step, and an already-onboarded instance grants administration solely through group membership. Neither produces an administrator without an administrator.
- Keeping credentials enabled on the public route was rejected: a public dashboard with a password login beside OIDC is a second, weaker door, and the posture makes the two impossible to separate.

**Consequences:** Publishing a route now also disables local credentials, and withholding it re-enables them along with the private origin — so `publish = false` is both the private bring-up state and the recovery path when identity fails. Group administration is unaffected by the flip, because group sync only touches OIDC users and the local administrator remains in the database. Two footguns remain and are documented in the runbook: Homarr joins only groups that already exist in its own database, so a `service-admins` group must be created once by hand; and Kanidm rejects scopes that are not in the client's granted scope maps, so `la-admin-1` must be deployed before the host whose client requests a new scope.

## D-105: GeoPulse 2.0 replaces JWT sessions, keeps PKCE as a patch, and declares its administrator

**Status:** Accepted.

**Context:** GeoPulse 2.0.0 was released on 2026-10-17, before this deployment carried real location history. Upgrading later would mean migrating a live database instead of an empty one. The release changes three things that reach this repository: it stays on PostgreSQL 17 (an 18 migration is separate and optional, with its own script), it replaces JWT authentication with database-backed sessions — `SessionAuthenticationMechanism` and `MobileSessionExchangeResource`, with no `geopulse.jwt.*` or `GEOPULSE_JWT_*` anywhere in the shipped configuration — and its frontend declares `engines.node >= 24.15` on Vite 8, where our build pinned Node 22 for Vite 4.

The upstream release still has no PKCE: at tag `v2.0.0` there is no `codeVerifier`, `code_challenge` or `code_verifier` in the backend. Kanidm enforces PKCE, so `patches/pkce.patch` remains load-bearing and had to be rebased onto rewritten OIDC code.

**Decision:** Pin `2.0.0` (`11955ec8`) and carry four coupled changes.

- **The patch is rebased, not dropped.** Ten hunks in `OidcAuthenticationService` survived the rewrite; the three that did not were the import block (2.0 dropped `java.net.URI` and moved lines, so `StandardCharsets`, `MessageDigest`, `NoSuchAlgorithmException` and `Base64` were re-added), the removal of the `finally` cleanup block (2.0 still deletes session state there, and the atomic `consumeByStateToken` still owns single-use semantics), and one test assertion (`OidcCallbackAuthResult` is now a record of user/redirect/provider/subject/session/idToken, so the test asserts `user()` and `idToken()`).
- **The migration becomes repeatable.** The patch first shipped its column as `V36.53.0`, and 2.0 introduced a *different* migration at that exact version (`V36.53.0__Add_user_notification_preferences_and_gps_health_incidents.sql`), so Flyway refused to start: `Found more than one migration with version 36.53.0` and the backend crash-looped into `start-limit-hit`. It is now `R__Add_oidc_session_code_verifier.sql` with `ADD COLUMN IF NOT EXISTS`: repeatable migrations run after the versioned stream and re-run only when the file changes, so a patch-owned schema change never occupies a number upstream may take. The stale `36.53.0` history row (ours, and the newest applied, so deleting it left no out-of-order gap) was removed from the live database before the retry.
- **The frontend toolchain follows the engine.** `nodejs_24` replaces `nodejs_22`.
- **The dead JWT wiring is removed.** The three `GEOPULSE_JWT_*` variables, the two PEM `sops.secrets` entries, and the start wrapper's requirement that those files be non-empty all go: 2.0 never opens them, and a preflight demanding them would fail a host that has no reason to create them.

It also adds `services.geopulse.adminEmail`, bound to `GEOPULSE_ADMIN_EMAIL`, because 2.0's `AdminBootstrapService` promotes that address on start and on every login. Administration then becomes a declared fact instead of "whichever account registered first" — the risk that made the earlier bootstrap sequence delicate.

**Alternatives considered:** Staying on 1.39.1 was rejected — the reason to upgrade is precisely to avoid a migration with real history in it. Dropping the PKCE patch was rejected: the identity provider requires PKCE and upstream has no verifier column, so login would fail outright. Renumbering the patch migration above 2.0's was rejected once the collision surfaced: any fixed number is a number upstream can reach, whereas a repeatable migration cannot collide. Deleting the stale history row and re-applying was preferred to Flyway `repair`, which would have had to realign a checksum for a file that no longer exists on disk. Keeping the JWT files and their preflight was rejected: they would be a required secret that no process reads, and the first host built without them would refuse to start for nothing.

**Consequences:** Sessions do not carry over from 1.x, so every user signs in once. A deployment that installed the 1.x-era `V36.53.0` must delete that history row once, by hand, before 2.0 will start; a fresh database never hits it, because the repeatable migration simply creates the column. A `secrets/services/geopulse.yaml` written for 1.x still holds `jwt/private_key` and `jwt/public_key`; they are ignored and can be dropped at the next rotation. `GEOPULSE_ADMIN_EMAIL` is optional — unset, 2.0 falls back to promoting the only user, and refuses to guess once there are several.

## D-106: The zone apex answers with a permanent redirect to the dashboard

**Status:** Accepted, pending deploy and the apex DNS apply.

**Context:** `shrublab.xyz` had no service behind it, so a visitor to the bare domain met nothing. Three shapes were offered: a redirect to `home.shrublab.xyz`, Homarr served at the apex, or a repo-owned static landing page.

**Decision:** The apex is a route with `subdomain = null` and `redirectTo`, rendered by Caddy as `redir <target>{uri} permanent`. It has no upstream, no health probe and no Access application, and it is withheld from the cross-host catalog because nothing dials it.

- **Resolver:** an origin-less route is valid only when it declares `redirectTo`, and only at the apex (`web-policy` rejects a redirect with a subdomain). `hostPorts`, the catalog and the provider projection skip redirects, and `mkUpstream`/`healthUrl` are not computed for them.
- **Edge:** a redirect owns its whole site, and `_ingress-routes.nix` carries `redirectTo` through. The certificate gains the apex as an explicit SAN, because `*.shrublab.xyz` does not cover the apex.
- **DNS:** the record is named `@` and carries `settings.flatten_cname = true`, since a zone apex cannot be a bare CNAME. The flag is set only on the apex record; every other record keeps `false`.

**Rejected:** Serving Homarr at the apex. Its cookies could be scoped to `shrublab.xyz`, which every other host receives, and the apex would become a workload whose name is the one people share. A static landing page was deferred: it is content to maintain, and the redirect can be replaced by one later without changing the DNS record.

**Consequences:** `home.shrublab.xyz` is the single dashboard address. Changing the landing target is one edit to `policy/web-services.nix`, and the rendered site and the DNS export follow from it.

**Follow-up found by the live check:** publishing the apex exposed that the dashboard's public route had never worked. `https://home.shrublab.xyz/` answered `400 Client sent an HTTP request to an HTTPS server` — Go's own error string, from the provider's Tailscale Serve front. A `tailscale-serve` route published its socket behind that front, which terminates TLS on the declared port and proxies to the app's loopback listener, but the edge derived its dial scheme from the application's `origin.scheme` (`http`). The dial was therefore a plain-HTTP request to a TLS listener. `lib/policy.nix` now has one `dialScheme` that answers `https` for `tailscale-serve` regardless of what the app speaks, applied to both the edge upstream and the catalog endpoint; dialing the front at the app's scheme is never correct, and the same defect silently affected every tailnet-served route. Verified live: `https://shrublab.xyz/boards` 301s to `https://home.shrublab.xyz/boards`, which answers 200.

## D-107: Homarr's app inventory is a projection of the web policy, synced through Homarr's API

**Status:** Accepted. Awaiting the operator's API key before it runs.

**Context:** Homarr is the user-facing dashboard, but its apps and boards live in its own SQLite database: no configuration file, and the apps a person can add to a board were hand-made. That is the one place where "what links exist" lived outside `policy/web-services.nix`. Keeping those links true is the tedious part — the name, URL and icon go stale whenever a route is renamed or a service moves — while arranging a board is a matter of taste, done once and occasionally.

**Decision:** Sync the **apps**; leave boards to the UI. `modules/apps/homarr/apps.nix` compiles the desired apps from `repo.web.catalog` and `modules/apps/homarr/reconcile.py` converges them through the API from a oneshot unit.

- **Selection is policy, not a list.** A route becomes an app when its `category` is `app` or `admin` and it is published. `infra` routes are machine endpoints — metrics stores, ingest listeners, the cache's write API — that no one opens, so they earn none; a withheld route is not served by the edge, so an app for it would be dead until release. `latitude-api` was retagged `infra` on this basis: it is the API origin the Latitude web app's browser calls, not a page.
- **Apps are matched by URL** and only ever created or patched. Nothing is deleted: an app the sync did not create is someone's own bookmark, and an app whose route retired may still sit on a board that was arranged by hand.
- **Boards are not generated.** Homarr's `PUT /api/boards/{id}/content` would let a script rewrite editor state, but that payload models sections, layouts and widget options this repository would have to track, and the result is a layout nobody asked it to decide. A board is built in the UI from the synced apps.
- **The API key is the one operator step**, because Homarr has no headless login: an administrator mints it in the UI and it is stored in the service secret file under `api_key`. A missing or empty key makes the unit exit successfully with a journal line, since an unminted key is a prepared state rather than a fault; API errors are failures, so the unit reaches `failed` and the notification path reports it.

**Rejected:** generating boards as well (the arrangement is taste, and reconciliation would need to model Homarr's editor payload to change it safely); pruning apps that no longer correspond to a route (deleting silently empties a tile someone placed, and an unused app costs nothing); resolving icons through Homarr's icon search at sync time (a network call and a non-deterministic input for a cosmetic value — the dashboard-icons slug is compiled, with a per-route override).

**Consequences:** the app list a person picks from is an observable of the web policy, verifiable against `repo.web.catalog`, and a renamed subdomain yields a corrected app instead of a stale bookmark. Board arrangement remains manual, which is where hand work belongs.

## D-108: GeoPulse stops carrying the PKCE patch; the Kanidm client opts out declaratively

**Status:** Accepted. Applies on the next deploy chain, `la-admin-1` before `oci-melb-1`.

**Context:** D-105 kept a 547-line local patch so GeoPulse's OIDC login would send a PKCE challenge, because Kanidm requires PKCE and upstream 2.0 has none. The patch carried three Java changes, an entity column, a repeatable migration and a test harness, and it cost real money twice: rebasing it across the 2.0 rewrite, and the Flyway version collision that took the backend down when the patch's `V36.53.0` met upstream's new file of the same number.

**Decision:** the patch is removed and GeoPulse is built from unmodified upstream sources. The client declares `allowInsecureClientDisablePkce` in `policy/identity.json`, which this repository already maps through `services.kanidm.provision.systems.oauth2` — nixpkgs' declarative provisioning applies it at activation. No operator command, no imperative step.

The repeatable migration `R__Add_oidc_session_code_verifier.sql` stays in the package (`pkgs/geopulse/migrations/`), unchanged. Flyway records an applied repeatable migration by description and checksum, so dropping the file would leave it unresolved locally and fail validation on the next start; the statement is `ADD COLUMN IF NOT EXISTS`, so it re-runs as a no-op and the unused column remains.

**Why the downgrade is acceptable:** PKCE protects against authorization-code interception, which matters most for public clients that cannot hold a secret. GeoPulse is a confidential client with a client secret, reached over TLS on the tailnet or behind Access, and it is the only client in the fleet relying on this flag. Kanidm marks the client insecure when it is set, which is the visibility wanted: the posture is a declaration in `policy/identity.json`, not a hidden CLI change.

**Alternatives considered:** keeping the patch was rejected as a recurring cost on every GeoPulse bump, with a failure mode (schema-version collision) that lands in production rather than in a build. Deleting the repeatable migration as well was rejected: it would make Flyway refuse to start on a database that has applied it.

**Consequences:** a GeoPulse bump is now `version`, `rev`, `hash` and the two dependency hashes, with nothing to re-apply. The client's PKCE exemption is visible in `policy/identity.json` and in Kanidm's own output. If GeoPulse ever ships PKCE upstream, the flag comes off the same way it went on, and the sparse-checkout-free patch never returns.

## D-109: degoog's package is built here, because its dependency expression was generated during evaluation

**Status:** Accepted. Applies on the next `home-forge` deploy.

**Context:** degoog's flake publishes the NixOS module this repository selects, and its package generates its dependency expression while it is being evaluated: `third-party/nix/package.nix` passes `bun2nix.fetchBunDeps` a `runCommandLocal` that runs the `bun2nix` CLI over `bun.lock`. `fetchBunDeps` `callPackage`s that path, so the derivation is built mid-evaluation and its `bun.nix` read back. `runCommandLocal` sets `allowSubstitutes = false`, so no cache can serve it and every cold store builds it itself.

Measured on `5cd67cec`, this repository's pinned revision: `oci-melb-1` and `la-admin-1` evaluate with `--option allow-import-from-derivation false`; `home-forge` fails on `fetch-degoog-deps.drv^out`. The option is reached only through `services.degoog.package` — overriding it alone made the whole toplevel evaluate — so the module was never the problem. The consequence was already recorded in D-082: `nix flake check --no-build` had to be dropped from CI because evaluation realises an unsubstitutable build. It is also the blocker for adopting nix-fleet's CI contract, whose validate gate evaluates.

**Decision:** the package is ours and the module stays upstream's. `services.degoog.package = config.repo.packages.degoog` drops the upstream default, which nothing then forces.

- `pkgs/degoog/bun.nix` is committed data, generated from the pinned input's `bun.lock` by this repository's own `bun2nix` input (2.1.2): 176 `fetchurl` entries keyed by package and version, with the lockfile's own sha512 integrity. Pinning the generator here rather than borrowing `inputs.degoog.inputs.bun2nix` keeps a degoog bump from changing the artifact's shape.
- The source is `inputs.degoog`, so module and package cannot skew, and `nix flake update degoog` moves both. The package is therefore absent from package-update discovery and present in its registry only as the owner of the derived file.
- The registered updater resolves the source at run time (`nix eval .#packages.<system>.degoog.source`) rather than baking a path in: the producer refreshes flake inputs before it runs updaters, so a baked path would regenerate the expression from the previous lock.
- The derivation sits behind a `symlinkJoin` wrapper declaring `pname` and `version`, the shape GeoPulse uses. `nix-update` reads the definition position of `version` and refuses a package whose `version` is defined inside a builder library — with the bare `writeBunApplication` result it failed with `.../nix/mk-derivation.nix is not in <flake source>`.
- `checks.<system>.check-degoog-bun-deps` regenerates and diffs, formatting both sides through `nixfmt` first: `nix fmt` covers every `.nix` file in the tree and ignores `treefmt.toml`'s excludes, so a byte comparison would otherwise make a repository-wide format a false failure.
- `renovate.json` drops the `nix` manager, following nix-fleet's `enabledManagers: ["github-actions"]` and keeping only the OCI-reference manager that is this repository's own. The pin moves through the package-update producer, not through a second writer.

**Rejected:** waiting for upstream to commit `bun.nix` (their Nix packaging is one contributor's side artifact — six commits, no Nix CI job, no issue raised; the fix is a two-line change plus a generated file, and it is being raised separately, but this repository's evaluation cannot wait on it); keeping the IFD and CI's scoped `path:` evaluation (it costs the only evaluation-only gate and blocks the fleet CI adoption); a fixed-output derivation over `bun install --frozen-lockfile` (one hash per system, where the generated expression is architecture-independent data — one artifact, no per-system hash to bump); a `postinstall` regenerating the file (degoog's Docker build installs with `--production`, so a devDependency-provided hook breaks it, and generation and verification should not be able to disagree about the tool); committing `bun.nix` without a gate (a lock bump that skips regeneration builds the previous package set silently, because the old hashes still resolve).

**Consequences:** all three hosts evaluate with import-from-derivation disabled, so `nix flake check --no-build --all-systems` passes. The evaluation-only gate returns through the nix-fleet CI adoption rather than as local CI, which is why no workflow here changes in this decision; the comments in `ci.yml` and `package-updates-refresh.yml` that explain the missing gate become obsolete with that adoption. This repository now owns a mirror of upstream's packaging — runtime inputs, build phase, start script — and must track changes like theirs of 2026-10-06, which added `curl`, `curl-impersonate` and the `binPaths` module option. The exit is deletion: when upstream commits `bun.nix` and points `fetchBunDeps` at it, `pkgs/degoog/`, the `repo.packages` entry and the module override all go.

## D-110: CI is nix-fleet's, and formatting is declared in Nix

**Status:** Accepted. Workflow-side changes take effect on merge; the pipeline, promotion and acceptance paths stay inert until the GitHub App, the `automation` environment and the repository variables exist.

**Context:** this repository carried two CI entry points of its own — `ci.yml` running `treefmt --fail-on-change` plus `just checks all`, and a `fleet-build.yml` pinned to a fleet revision that predates the coordinator — and a copy of nix-fleet's `package-updates-refresh.yml`. D-109 removed the last obstacle to the fleet's validator: evaluation no longer builds, so `nix flake check --no-build --all-systems` passes and the `validate-flake` action's IFD-disabled evaluation is a gate this flake can meet. Two flake-level items still decided whether the validator was usable at all, and both were checked before anything was adopted: `checks.x86_64-linux.treefmt` did not exist (formatting ran in a development shell, and `validate.yml`'s format job builds that check), and `checks.x86_64-linux.host-home-forge` now evaluates with import-from-derivation disabled.

**Decision:** adopt the fleet's CI contract at `@v3` and keep only what the fleet cannot know.

- **Formatting moves into Nix.** `modules/flake/treefmt.nix` imports `inputs.treefmt-nix.flakeModule` and declares the formatter set, so the same declaration produces the `nix fmt` wrapper, the devShell's `treefmt`, and `checks.<system>.treefmt`. `treefmt.toml` is deleted; its exclusions move to `settings.global.excludes`, with `.jj/**` and `.pi/**` added because those trees are large and never hand-edited. The formatters are declared as raw `settings.formatter` entries with absolute commands rather than through `programs.*`: the modules carry their own option sets, and these are the exact invocations the tree was already formatted with. Measured, this matters — treefmt-nix's `prettier` options reformatted 466 files across `openspec/` and `research/`, so the equivalent of the old configuration is what keeps the gate honest instead of turning it into a mass rewrite.
- **A retention root.** `modules/flake/cache-root.nix` publishes `packages.<system>.cache-root`, a linkFarm over every published package, and puts it in the build selection as `checks.<system>.packages`. The pin is refused for a path the cache does not hold, so a promoted revision must have built it; the aggregate is artefacts only, because a check's output moves whenever its inputs do.
- **The validator replaces the local gate.** `ci.yml` keeps its name and its trigger set (a `ci` workflow_run is what the pipeline listens for) and splits into `fleet`, calling `validate.yml@v3` with `generated_files: check`, and `repo`, running the contract tests no fleet workflow knows about.
- **One producer.** `package-updates-refresh.yml` becomes a thin weekly caller of the fleet's producer. Two producers on `automation/*` was the failure this replaces. The cadence stays weekly rather than the fleet's daily because each proposal triggers a full build.
- **Five thin callers.** `pipeline.yml` (`workflow_run` on `ci`, granted the union its jobs need and `secrets: inherit`), `promote.yml` (`status`, passing the retention selection), `accept.yml` (`pull_request_target` on the acceptance label), `candidate-sweep.yml` (scheduled) and `verify-cache.yml` (on `main`). None reimplements orchestration; each supplies the event, the grant and the repository's own variables.
- **`fleet-build.yml` moves from `builder_attr` to `profile`** at `@v3`, which also drops the comment requiring the workflow pin to track the flake input: the workflow resolves its own coordinator from `job.workflow_sha`, so the pin and the flake input are separate decisions.
- **Two inputs are pinned to a release, and Renovate keeps them there.** `degoog` (`github:degoog-org/degoog/1.1.0`) and `bun2nix` (`github:nix-community/bun2nix/2.1.2`) tracked branches, so `renovate.json` — whose nix manager D-109 switched off — could not see them. Both locked revisions already equalled the newest tag, so the pin is content-identical: only `original.ref` changes in `flake.lock`. Two `custom.regex` managers now read the version out of the input URL (`github-tags` for degoog, which publishes no GitHub releases; `github-releases` for bun2nix, which does), grouped into one proposal. **A degoog bump that changes `bun.lock` must regenerate `pkgs/degoog/bun.nix` in the same change** — Renovate cannot run the generator (hosted Renovate has no `postUpgradeTasks`), so `check-degoog-bun-deps` fails the proposal until `nix run .#update-packages -- degoog` runs. That failure is the gate working: a stale artifact is otherwise a build that consumes the wrong dependency set.

**Rejected:** copying `validate.yml` or the pipeline into this repository (the reason the fleet owns it is that a consumer's copy diverges silently; the runbook's warning that nix-fleet's own `ci.yml` uses internal `$` references is exactly why its callers stay thin); keeping `builder_attr` (the input no longer exists — there is no alias, the call fails at parse time); hand-rolling `checks.<system>.treefmt` as a `runCommandLocal` over a source copy (it repeats the tool list in a second place and skips the pinned tooling base the fleet's format job is named for); `settingsFile`-style reuse of `treefmt.toml` (treefmt-nix renders its configuration from the module and offers no such option, and parsing the TOML into `settings` collides with the program modules' own values); keeping `treefmt.toml` beside the module (two sources for one formatter set — the drift the adoption is meant to end).

**Consequences:** the evaluation gate this repository lost in D-082 is back, run by the fleet's validator on every pull request, and the local battery no longer claims a limitation that has ceased to exist. `nix fmt` now formats the whole repository through the generated wrapper rather than only `.nix` files. `openspec/specs/repository-structure/spec.md` and `openspec/specs/operations/spec.md` still say `treefmt.toml` is required; that spec delta is outstanding and belongs to an OpenSpec change, not to this one. `AGENTS.md` and `.just/checks.just` are corrected here. The fleet-side items stay operator-owned: a GitHub App installed on this repository, an `automation` environment holding its private key with a default-branch policy, the variables (`AUTOMATION_APP_ID`, `AUTOMATION_APP_SLUG`, `PROMOTION_POLICY=label`, `CACHE_PIN_NAME=auto`, `CANDIDATE_TARGETS`, `CANDIDATE_SYSTEMS`, `CANDIDATE_RUNNER_SYSTEM`, `AUTOMATION_UPDATE_AUTHORS`), the `accept-update`/`dependencies`/`automated` labels, `FLEET_BUILDER_SSH_KEY`, and the `update-candidate` ruleset — which is enabled only after one candidate has validated and promoted by hand, and never requires `update-accepted`.

## D-111: The ClickHouse server is its own aspect; its consumers have no registry

**Status:** Accepted. Supersedes the ownership clause of D-071 ("langfuse keeps its ClickHouse ownership").

**Context:** Langfuse introduced the native ClickHouse server, so its module owned it: `services.clickhouse` (enablement, package, `serverConfig`), the unit's restart policy, the `/run/secrets/rendered` permission fix and the config restart trigger. D-071 then placed Latitude beside Langfuse as a *trial* and deliberately left that ownership alone, so nothing about the datastore would move if the trial failed.

The trial's first real deploy made the cost visible. Latitude contributes its own `clickhouse-server/users.d/300-latitude.xml` and extends `systemd.services.clickhouse.restartTriggers` from its own module, so the substrate was already co-owned de facto while one consumer nominally owned it. Two consequences followed: disabling `langfuse` while keeping `latitude` left the second consumer with a users fragment and no server, and no named error; and the one-line ClickHouse restart trigger fix had to be made in a *consumer's* file, which is where it was hardest to find.

**Decision:** `modules/database/clickhouse.nix` publishes the `clickhouse` aspect and owns only the server — enablement, package, `serverConfig` with `http_port` read from `policy/globals.nix` (D-102), the rendered-config restart trigger, the `/run/secrets/rendered` permission fix, and the `Restart`/`RestartSec` policy. The host selects it beside the consumers it runs. Each consumer keeps exactly what it had: its `users.d` fragment, its own substitution file, its own `restartTriggers` entry, and its URL built from the policy port. Both consumers assert `config.services.clickhouse.enable` with a named message.

There is **no consumer registry**, which is the one place this deliberately differs from the PostgreSQL mechanism (D-058). ClickHouse merges every file in `users.d/` at startup, so a co-tenant needs nothing from the server; PostgreSQL's registry exists because the server must create each consumer's database, role, `pg_hba` entry, extensions, setup SQL and dump, and it cannot do that work without knowing the consumer exists. A ClickHouse registry would restate what the filesystem already expresses.

**Alternatives considered:**

- Keeping ownership with Langfuse until the trial resolves was rejected: the inversion already produced a real defect (a co-tenant that cannot evaluate its own precondition), and the trial's outcome does not change who should own a shared server.
- A `services.clickhouse.consumers.<name>` registry mirroring `services.postgres.consumers` was rejected as above: it would duplicate a merge ClickHouse performs itself.
- Leaving the permission fix and restart trigger in the consumer and adding only an assertion was rejected as a half-measure: the assertion fixes the silent failure, but the substrate would still be edited in a consumer's file.

**Consequences:** `services.clickhouse` is now enabled by aspect selection, so a host that runs a consumer without the substrate fails evaluation by name instead of starting with a fragment for a server nobody enabled. The `ExecStartPre` chmod now carries a `-` prefix, because the substrate cannot know whether any consumer has rendered a template yet. The scaffold contract's package-provenance pin moved from the Langfuse module to `modules/database/clickhouse.nix`. Langfuse's users fragment moved from nixpkgs' `extraUsersConfig` (rendered as `users.d/200-nixos-module-extra-config.xml`) to an explicit `users.d/250-langfuse.xml`, so both consumers are now shaped alike — a filename change only; the XML is identical.

## D-114: Equal source trees must yield reusable host outputs

**Status:** Accepted; live PR/main reuse pending.

**Evidence:** Confirmed by the fleet-controller reuse requirement and the host module's explicit dependency on `self.rev`/`self.dirtyRev`.

**Supersedes:** Only D-057's revision-stamping consequence. Its Git-tree source boundary and index-integrity guard remain unchanged.

**Context:** A merge commit can have exactly the built PR's source tree but a different commit ID. Stamping that ID into `system.configurationRevision` changes the host derivation and prevents equal-tree build reuse without changing configuration behavior.

**Decision:** Stop stamping the flake revision into host outputs. Keep `/etc/nixos-source` pointing at the tracked `self.outPath`, so hosts retain the evaluated configuration without importing VCS metadata or plaintext working-directory files. Use nixbot's build metadata for commit attribution.

**Rejected:** Keeping commit-dependent outputs and assuming a matching tree guarantees reuse, or dropping the tracked source copy to hide the dependency. The source copy is useful provenance and is already content-addressed.

**Consequences:** `system.configurationRevision` is no longer supplied by this repository. Validate equal-tree derivations independently of the later observed PR/main reuse test; neither result substitutes for the other.
