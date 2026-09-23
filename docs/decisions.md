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

Status: Accepted

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

**Status:** Accepted

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
