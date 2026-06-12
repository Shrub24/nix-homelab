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

- baseline shared policy lives in `modules/core/base.nix`
- profile composition lives in `modules/profiles/base-server.nix`
- service boundary for private access starts in `modules/services/tailscale.nix`

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
- keep low-level implementation in `modules/services/*.nix` and avoid broad repository reorganization

Rationale:

- introduces an explicit logical application boundary without disrupting existing host behavior
- preserves service-level reuse while making host composition easier to reason about

## D-018: Termix runs as a Tailscale-only admin application on do-admin-1

Status: Accepted

Decision:

- implement Termix with a dedicated low-level module `modules/services/termix.nix` using Podman OCI containers (`termix` + `guacd`)
- persist Termix state under `/srv/data/termix`
- expose Termix only through declared edge route policy (Cloudflare Access-gated at public edge, private-origin transport preference)
- Termix is hosted on `do-admin-1` (DigitalOcean x86_64); `oci-melb-1` does not run Termix

Rationale:

- adds controlled remote admin capability while preserving private-origin boundaries and explicit edge policy
- keeps runtime/container specifics isolated from host composition and canonical docs

## D-030: Homepage authenticated widgets use host-scoped caller-owned machine-auth env wiring

Status: Accepted

Decision:

- Homepage authenticated widgets consume credentials via a dedicated host-scoped SOPS template environment file (`homepage-auth.env`)
- credential ownership stays with Homepage caller wiring (`modules/services/admin/homepage/**`) instead of route policy metadata
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
4. Store the username/password in `hosts/do-admin-1/secrets.yaml` under:
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

- default bootstrap workflow derives host age recipient by fetching live SSH ed25519 host key (`host-generic` pattern)
- keep advanced injected-key workflow available for cases where live retrieval is not possible
- enforce host-scoped `.sops.yaml` rules per host (`hosts/<host>/secrets.yaml`)

Rationale:

- reduces manual key handling during day-0 bring-up while preserving scoped blast radius
- keeps a deterministic fallback for restricted network/bootstrap scenarios

## D-027: deploy-rs is the primary deployment workflow for both active hosts

Status: Accepted

Decision:

- add `deploy-rs` as a flake input and publish `deploy.nodes` for `oci-melb-1` and `do-admin-1`
- define host deploy metadata in `lib/deploy/hosts.nix` and reusable wiring in `lib/deploy/default.nix`
- set each node to `sshUser = "dev"`, host hostname, and `profiles.system.path` from the matching `nixosConfigurations.<host>`
- wire `deploy-rs` deployment checks into `flake checks` for both `aarch64-linux` and `x86_64-linux`
- make `just deploy`, `just activate`, and `just check` the primary operator workflow

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
  - leaf service modules (`modules/services/**/*.nix`) own their own enablement, secret contracts, and runtime wiring
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
- `modules/profiles/base-server.nix` applies those defaults for active hosts as part of common host profile composition
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

## Open Questions (Intentional)

These are known but intentionally unresolved until implementation and operational learning justify final decisions.

- when to introduce service-scoped secret files for movable workloads
- when and how to introduce `rclone`/VFS into media flow
- hook/event framework for future processing pipeline
- backup policy timing once host authority increases
- fleet tool choice and operating model once host count grows
