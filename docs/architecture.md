# Architecture

## Purpose

This repository is the infrastructure source of truth for a modular NixOS homelab fleet. It is being repurposed from a single developer VPS configuration into a multi-host, service-oriented infrastructure repository.

Primary objective:

- define and operate reproducible NixOS hosts across providers and regions
- start with a small, reliable base and scale architecture over time
- keep security boundaries explicit (network, secrets, host identity)

## Scope

In scope now:

- Oracle Cloud host `oci-melb-1` as the first fleet node
- DigitalOcean host `do-admin-1` as the second fleet node
- private-first service topology with a designated public edge bastion (Cloudflare + Caddy)
- native NixOS services: `navidrome` and `syncthing`
- modular host and service design for future multi-host growth

Out of scope for now:

- Kubernetes stack (`k3s`, `keda`) and cluster scheduling decisions
- high-availability edge topology and advanced edge traffic policy
- cloud worker architecture details

## Environment Model

Control plane:

- local admin machine drives builds and deployments
- first bootstrap performed with `nixos-anywhere`

First target host:

- hostname: `oci-melb-1`
- provider: Oracle Cloud Free Tier
- architecture: `aarch64-linux` (Ampere)
- network policy: private-origin services and cross-host access over Tailscale

Fleet direction:

- future mixed architecture support (`aarch64` and `x86_64`)
- additional provider and region expansion expected
- infrastructure layout should be provider-aware but provider-agnostic where practical

## Design Principles

1. Native first, orchestrated later

- prefer native NixOS modules and systemd services first
- add orchestration only when concrete workload pressure appears

2. Modular, feature-oriented composition

- host identity, facts, and narrow host-only overrides belong in host modules
- reusable behavior and secret ownership belong in service modules
- multi-service stacks and shared cross-service concerns belong in application modules
- provider specifics should be isolated from workload modules

3. Security blast radius minimization

- secrets split by feature scope (applications, standalone services, host exceptions)
- host-scoped encryption recipients maintained by `.sops.yaml`
- normal secret scope derived from feature enablement
- explicit exception scopes only for cross-host readers (e.g. OIDC handshakes)

4. Operational simplicity in early stages

- first host bootstrap should optimize for reliability and recoverability
- avoid unnecessary complexity before fleet scale requires it

5. Single package baseline by default

- active host and module code uses primary `nixpkgs` pinned to `nixos-unstable`
- stable fallback inputs are introduced only as explicit, documented exceptions

## Logical Repository Shape (Target)

The exact file tree can evolve, but the intended shape is:

- `hosts/oci-melb-1/default.nix` and `hosts/do-admin-1/default.nix` as thin host assembly entrypoints
- `hosts/<host>/default.nix` for host identity, facts, feature enables, and narrow overrides
- `hosts/<host>/hardware-configuration.nix` for auto-detected hardware facts
- `hosts/<host>/<component>.nix` for host-specific component overlays
- `modules/applications/<name>/default.nix` for feature composition roots (multi-service stacks)
- `modules/services/<domain>/<name>.nix` for reusable service modules with enable flags and secret contracts
- `modules/services/<name>.nix` for standalone leaf service modules
- `modules/core/base.nix` for shared baseline NixOS policy
- `modules/core/users.nix` for shared user declarations
- `modules/profiles/base-server.nix` for common host profile composition, including shared Nix substitute/trust defaults
- `modules/providers/oci/default.nix` for OCI-specific host-safe defaults
- `modules/providers/digitalocean/default.nix` for DigitalOcean host-safe defaults
- `modules/storage/disko-root.nix` for declarative root disk layout
- `modules/storage/disko-single-disk.nix` for single-disk host layout
- `policy/globals.nix` for canonical non-secret fleet defaults
- `policy/service-defaults.nix` for feature enablement and path defaults
- `policy/web-services.nix` for SSOT endpoint and routing policy
- `generated/policy/web-services.json` for the committed exported web-policy artifact consumed by OpenTofu
- `lib/secrets.nix` for reusable secret-contract helpers
- `scripts/*.sh` for operator-facing repo utilities and export/render helpers
- `tests/fixtures/secret-scope.nix` for secret-scope contract expectations used by validation checks
- `tests/*.sh` for repo-owned validation checks that verify committed artifacts and policy contracts
- `lib/deploy/` for deploy-rs host wiring
- `secrets/applications/<name>.yaml` for application-scoped encrypted values
- `secrets/services/<name>.yaml` for standalone service-scoped encrypted values
- `secrets/hosts/<host>/system.yaml` for host-only bootstrap/system secrets
- `secrets/hosts/<host>/oidc.yaml` for cross-host OIDC handshake secrets
- `secrets/common.yaml` for tightly-scoped fleet-shared secrets
- `.sops.yaml` as central recipient policy with explicit path-scoped rules

## Secrets Architecture

Secrets follow a feature-aligned, topology-derived blast-radius model.

### Scope model

Application scope:

- file: `secrets/applications/<name>.yaml` (e.g. `secrets/applications/music.yaml`, `secrets/applications/admin.yaml`)
- contains values consumed by a specific application stack
- normal reader set derived from hosts where the application is enabled

Standalone service scope:

- file: `secrets/services/<name>.yaml` (e.g. `secrets/services/karakeep-pod.yaml`, `secrets/services/bifrost-gateway.yaml`)
- contains values consumed by a single leaf service not part of a composed application stack

Host exception scope:

- `secrets/hosts/<host>/system.yaml` — host-only bootstrap/system secrets (e.g. Tailscale auth key, SSH identities)
  - this scope now also carries host-only recovery password hash material for console break-glass users when that recovery baseline is enabled
- `secrets/hosts/<host>/oidc.yaml` — cross-host OIDC handshake secrets where both the app host and identity provider host need to decrypt

Fleet-shared scope:

- `secrets/common.yaml` — values intentionally shared across hosts (e.g. Beszel agent key)
- unencrypted reference: `secrets/common.template.yaml`

### Ownership model

- **Leaf service modules** own their own `secretFiles.*` / `secretKeys.*` contract options, `sops.secrets` registrations, `sops.templates` assembly, and runtime service wiring
- **Application modules** own shared composition defaults and pass through `secretFiles.*` values to sub-services; they do not own sub-service secret internals
- **Host modules** own only host identity, feature enables, and explicit secret-file-path bindings (e.g. `applications.music.secretFiles.host = ./secrets/applications/music.yaml`)
- **Policy layer** (`.sops.yaml`) defines decryption recipients per file pattern using explicit path-scoped rules; normal scope derives from feature enablement; explicit exception readers declared for OIDC handshake material

### Validation Contracts

- `lib/secrets.nix` provides reusable helpers: `mkSecretFileOption`, `mkSecretKeyOption`, `mkRequiredSecretAssertion`, `mkSimpleSecret`, `mkSecretsFromMap`
- `.sops.yaml` remains the source of truth for recipient policy; validation lives separately so tests do not read as authoritative configuration
- `tests/fixtures/secret-scope.nix` defines the expected recipient contract used by secret-scope validation
- `tests/check-secret-scope.sh` verifies `.sops.yaml` matches the intended topology and blast-radius rules
- `tests/check-web-services-policy.sh` verifies the committed exported web-services JSON matches `policy/web-services.nix`

### Operational implications

- adding a host should not implicitly expose all existing secrets
- moving a service between hosts is an explicit security and operations decision
- per-host enrollment tokens are preferred over shared reusable tokens
- secret file moves and `.sops.yaml` updates must be coordinated to preserve blast-radius boundaries

## Host Identity and Bootstrap Posture

Preferred baseline:

- `nixos-anywhere` bootstrap with conservative secret bootstrapping
- two-step secrets bootstrap is the default because it reduces pre-install key handling risk
- host key bootstrap defaults to retrieving the live SSH ed25519 host key and deriving an age recipient

Accepted advanced alternative:

- pre-generated host identity material can be used when first-boot decryption is required
- this is valid but is intentionally treated as a sharper option with higher bootstrap complexity
- injected host public key bootstrap is available as an advanced override path

## Storage and Service Data Model

Current decision:

- one dedicated Nix store filesystem mounted at `/nix` on `oci-melb-1`
- one persistent service-state mount on the host (`/srv/data`)
- one dedicated media filesystem mounted at `/srv/media`
- service state organized under subdirectories on `/srv/data`

Recovered `oci-melb-1` single-disk baseline:

- the OCI boot volume now carries the EFI system partition plus labeled ext4 filesystems for `/`, `/srv/data`, `/nix`, and `/srv/media`
- `modules/storage/disko-single-disk.nix` is the canonical storage boundary for that recovered host shape
- host-specific sizing stays in `hosts/oci-melb-1/default.nix`, while the partition/mount contract remains declarative in the storage module

Initial media/data flow:

- Syncthing manages both `/srv/media/library` and `/srv/media/quarantine` directly
- `modules/applications/music.nix` is the canonical owner for creating shared media roots (`/srv/media`, `/srv/media/inbox`, `/srv/media/library`, `/srv/media/quarantine`, `.versions`)
- lower-level service modules may add ACLs, marker files, or service-specific subdirectories, but do not redefine those shared root directory ownership contracts
- SoulSync is the primary ingest and promotion control-plane service
- Tagr is available as an operator-invoked manual metadata/cover fallback editor against canonical media paths
- `/srv/media` remains the authoritative shared media root
- `/srv/data` remains the service-state mount (`/srv/data/syncthing/config`, `/srv/data/navidrome`, `/srv/data/soulsync`, `/srv/data/tagr`, `/srv/data/karakeep`, `/srv/data/bifrost`)
- canonical ingest/promotion paths:
  - download inbox: `/srv/media/inbox/slskd`
  - canonical library: `/srv/media/library`
  - unresolved/review lane: `/srv/media/quarantine/untagged`
  - approved rescue/staging lane: `/srv/media/quarantine/approved`
- quarantine ownership is `music-ingest`; ACL grants explicit `media` read-only (`r-x`/`r-X`) access and `syncthing` write access for review and sync workflows
- Syncthing folder markers are codified with tmpfiles at `/srv/media/library/.stfolder` and `/srv/media/quarantine/.stfolder` owned by `syncthing:syncthing`
- beets remains installed as fallback rescue tooling and no longer owns default automated ingest
- SoulSync is configured for conservative day-1 behavior (Discogs-first metadata fallback preference and no broad pre-existing-library mutation jobs)
- Navidrome scope is explicit (`library + quarantine`) and inbox is excluded from the listening surface
- `modules/applications/music.nix` also defines `music-library` so `dev` and Syncthing share controlled library access
- `slskd` keeps downloads and incomplete state under `/srv/media` (`/srv/media/inbox/slskd` and `/srv/media/slskd-incomplete`)
- Beets state and import logs remain under `/srv/data/beets` (`/srv/data/beets/state`, `/srv/data/beets/logs`)
- no duplicate media staging dataset is introduced

Future evolution:

- when moving toward `rclone`/VFS and processing workflows, an ingest pipeline can be introduced
- hook-driven processing is expected later, not required for initial baseline

## Backup Architecture

Current baseline:

- mutable service state is backed up with NixOS-native `services.restic.backups`
- backup scope is state-first: `/srv/data` subtrees and generated recovery artifacts are in scope, and `/srv/media` coverage is controlled by host backup policy
- each host writes to its own dedicated Cloudflare R2 bucket using host-scoped credentials and a host-unique restic password
- non-secret transport defaults (`endpoint`, `region`, path-style behavior) stay canonical in `policy/globals.nix`

Consistency model:

- `export` services generate an app-native recovery artifact before the shared restic job runs, while raw state is also captured initially
- `quiesce` services may later stop or stabilize around the backup window if required
- `live` services are captured without explicit coordination in the current baseline

Current export-first services:

- Kanidm via upstream automatic backup artifacts plus raw state coverage
- Vaultwarden via SQLite `.backup` export plus raw state coverage
- Tagr via SQLite `.backup` export plus raw state coverage

Current live-state services:

- Syncthing, Navidrome, Beets state, SoulSync state, Termix, Beszel hub, Karakeep, and Bifrost app state
- optional Cockpit loopback TLS material when enabled

Operator workflow:

- initialize a host repository: `just backup-init <host>`
- run an on-demand backup: `just backup-run <host>`
- re-run the canonical managed backup flow for initialization, integrity checks, and pruning: `just backup-check <host>` and `just backup-prune <host>`
- inspect status/logs: `just backup-status <host>` and `just backup-logs <host>`

Restore posture:

- backup success alone is not sufficient; restore validation is part of the operator contract
- export-first services should prefer their generated recovery artifact first, with raw state retained for exact-state recovery and forensic fallback
- restore prep should verify bucket credentials, restic password access, available snapshots, and target service stop/isolation requirements before modifying runtime state

## Sovereign Binary Cache

niks3 (Mic92/niks3) is the fleet sovereign Nix binary cache, running on `oci-melb-1` with PostgreSQL and Cloudflare R2 backend.

Read path:
- Consumers read directly from `s3://nix-cache?...` — no HTTP endpoint, no credentials needed (bucket is public-read)
- Substituter priority: `nixbuild.net` first, sovereign S3 second, `cache.nixos.org` third
- Both hosts and CI can consume the cache as a standard Nix S3 substituter via `policy/globals.nix`

Write path:
- Only hosts push, post-deploy, via `modules/services/niks3-push.nix`
- Pushers authenticate with host-scoped API tokens to the niks3 server (`http://127.0.0.1:5751` local, or `http://oci-melb-1:5751` over Tailscale)
- Server signs NARs with its Ed25519 key (stored in `secrets/services/niks3.yaml`, only on `oci-melb-1`)
- Consumers trust the public key from `policy/globals.nix`
- Reference-tracking GC runs daily, 30-day retention

## Network and Access Model

Current model:

- Cloudflare + Caddy on `do-admin-1` is the public edge bastion for explicitly declared web routes
- Tailscale remains the private connectivity and cross-host upstream fabric
- Approved gated public services are exposed through edge policy (Cloudflare Access where required) with private-origin upstream preference
- `tailscale-upstream` is the default cross-host route transport mode
- `direct` is reserved for explicit edge-local localhost upstream exceptions
- `tailscale-only` remains the mode for routes that must not be publicly rendered
- SoulSync route (`soulsync.<primaryDomain>`) is exposed via `tailscale-upstream`, Cloudflare Access, and AOP; day-1 posture is control-plane-first with best-effort playback suppression and documented residual UI behavior if upstream playback controls cannot be fully disabled
- Bifrost baseline mode is file-driven and host-local on `oci-melb-1`; `config_store`, UI-managed config mutation, and other runtime-mutated control-plane state are intentionally out of baseline scope
- Repo-owned AI gateway aliases (`shrublab-text`, `shrublab-image`, `shrublab-embedding`, `shrublab-fallback`) sit behind one host-local OpenAI-compatible endpoint for downstream consumers such as Karakeep

Recovery posture:

- normal operator access remains Tailscale-first over SSH
- both active hosts may enable a console-only `rescue` user for provider/serial-console break-glass access when the normal network path is unavailable
- the `rescue` user is password-authenticated for local console use, denied for SSH login, and remains separate from the normal identity-backed admin flow
- host recovery secret registration remains feature-owned by `modules/shared/host-recovery.nix`, while hosts only bind the host secret file path and enable the feature
- recovery readiness is exercised with a declared weekly reboot timer so console/login regressions are more likely to surface during routine operations rather than only during an outage

## Admin Surface Model

Current admin-service shape:

- `do-admin-1` hosts the private admin surface composition under `modules/applications/admin/default.nix`
- Quantum replaces Filebrowser as the file-management UI
- Quantum source topology is split between reusable service wiring and host-owned source declarations:
  - reusable runtime/container logic lives in `modules/services/admin/quantum.nix`
  - host-specific source declarations live beside the host, currently `hosts/do-admin-1/quantum.nix`
- Quantum on `do-admin-1` exposes:
  - a local `do-admin-1` source
  - remote host sources that are explicitly declared and mounted through the chosen transport model

Current Cockpit shape:

- Cockpit uses per-host sessions rather than login-page host chaining
- public entrypoints are shared-host subpaths:
  - `cockpit.shrublab.xyz/do-admin-1`
  - `cockpit.shrublab.xyz/oci-melb-1`
- `do-admin-1` local Cockpit upstream is proxied over localhost HTTPS with a host-local generated CA/leaf pair trusted explicitly by Caddy
- `oci-melb-1` is exposed through host-local `tailscale serve --https=9443`, and the edge host proxies to that Tailscale HTTPS endpoint
- Cockpit-specific transport ownership stays in Cockpit-owned modules:
  - `modules/services/admin/cockpit.nix`
  - `modules/services/admin/cockpit/loopback-tls.nix`
  - `modules/services/admin/cockpit/tailscale-serve.nix`
- host overlays such as `hosts/do-admin-1/cockpit-auth.nix` and `hosts/oci-melb-1/cockpit-auth.nix` only provide host-specific values (service-user secret path, local enable flags, public host/urlRoot overrides)

Potential later model:

- edge HA/failover and advanced policy hardening once phase-1 operational posture is stable

## Deployment Architecture

Bootstrap and rollout order:

- host installation and baseline with `nixos-anywhere`
- regular host updates via `deploy-rs` (`just deploy <host>`)
- dry-activation and validation via `just activate <host>` and `just check`
- remote network-owner cutovers are installed with `deploy-rs --boot` and applied on reboot rather than live-switched over SSH
- recovery baseline rollouts must verify the `rescue` user contract, scheduled reboot timer, and rollback path before the change is treated as complete

Fleet tooling posture:

- structure now for future fleet tools
- `deploy-rs` is the primary host deployment path (`deploy.nodes` in flake output)
- per-host deploy metadata is defined in `lib/deploy/hosts.nix`, with reusable wiring in `lib/deploy/default.nix`
- keep `nixos-anywhere` for bootstrap and break-glass flows; use `deploy-rs` for regular host updates
- GitHub Actions is the canonical hosted validation and deploy automation surface:
  - lightweight validation runs on PRs to `main` and pushes to non-`main`
  - exact deploy-profile remote-build validation is reserved for PRs to `main` and manual `workflow_dispatch` runs
  - pushes to `main` run validation first, then serial fail-fast deploys (`do-admin-1` before `oci-melb-1`)
  - operators may also run the deploy workflow manually from any selected branch via `workflow_dispatch`; that manual path still uses the same validation and serial deploy ordering
  - CI joins the tailnet temporarily with `tailscale/github-action@v4` and reaches hosts over Tailscale-only addresses
  - the top-level deploy workflow keeps shared validation and explicit ordering logic, while the reusable per-host deploy workflow owns host prebuild + deploy steps
  - deploy workflow structure keeps shared nixbuild and per-host deploy logic in reusable GitHub Actions surfaces rather than duplicating job steps for each host
  - deploy auth is intended to rely on Tailscale SSH policy for the `dev` user rather than a repository-stored CI deploy private key
  - CI-specific SSH relaxations for deploy-rs are passed inline as workflow command options rather than through a generated SSH config file
  - CI deploys also pass `deploy-rs --remote-build` inline so the target host becomes the realization point and fetches directly from configured substituters instead of using the GitHub runner as an extra store-path transfer hop
- nixbuild.net is the CI build plane for mixed-architecture validation:
  - GitHub Actions installs Nix with `nixbuild/nix-quick-install-action`
  - GitHub Actions configures nixbuild with `nixbuild/nixbuild-action` using GitHub OIDC plus an attenuated `NIXBUILD_TOKEN`
  - CI remote-builds host toplevels against `ssh-ng://eu.nixbuild.net` so `x86_64-linux` runners can validate both active host architectures without a custom runner fleet
- Host-side Nix consumption remains substitute-only in phase 1:
  - hosts inherit one shared substitute/trust baseline through `modules/profiles/base-server.nix`
  - current substitute defaults point at `nixbuild.net` over `ssh://eu.nixbuild.net`
  - host-side substitute/trust settings are policy-driven through `policy/globals.nix` and applied by the common base-server profile rather than repeated in host files
  - CI auth remains separate and uses GitHub OIDC plus `NIXBUILD_TOKEN`
  - the account-specific nixbuild signing key is public but must still be populated explicitly in `policy/globals.nix` before substitute consumption is relied on
  - repo-local `deploy-rs` topology stays unchanged for operator workflows; the CI-only `--remote-build` override exists specifically to keep GitHub-hosted deploy runs off the store-path data plane where hosts already have direct substituter access
- before any bootstrap/deploy operation, run `just bootstrap-preflight host=<host>` to enforce access-safety invariants (`openssh` enabled, tcp/22 allowed, declarative `dev`/`root` SSH keys present)

Operator commands:

- deploy: `just deploy oci-melb-1` (or `just deploy do-admin-1`)
- deploy without rollback: `just deploy oci-melb-1 --rollback false`
- network-owner cutover: `nix run .#deploy-rs -- --skip-checks --boot .#do-admin-1`, then reboot from console
- dry-activate: `just activate oci-melb-1`
- checks: `just check` (flake checks plus `tests/check-secret-scope.sh` and `tests/check-web-services-policy.sh`)
- Cloudflare policy export sync: `just tofu-sync`
- Cloudflare runtime render: `just tofu-runtime`
- backups: `just backup-init <host>`, `just backup-run <host>`, `just backup-check <host>`, `just backup-prune <host>`

Recovery verification checklist:

- confirm `services.hostRecovery` is enabled on the target host and points at the host-scoped `system.yaml` secret file
- confirm the `rescue` account exists, is intended for console-only use, and cannot be used for SSH login
- confirm `host-recovery-reboot.timer` is present with the expected weekly cadence
- keep provider/serial console access available until the new generation has been verified
- for `oci-melb-1`, note that some local builds on the x86_64 admin machine remain limited by non-substitutable `aarch64-linux` derivations; use remote/host-side validation when a full local build cannot complete

Note: `just deploy` takes positional host arguments (`just deploy oci-melb-1`), not `host=...`.

Remote networking note:

- `do-admin-1` now uses declarative `systemd-networkd` with static `ens3`/`ens4` addressing, while `cloud-init` remains metadata-only
- switching network ownership on a remote host can drop the active SSH session mid-activation even when the target generation is correct
- treat network-owner transitions as reboot-time changes with provider console available for verification and rollback

## Phase-1 Edge Ingress Operations

Phase-1 ingress is implemented with `modules/applications/edge-ingress.nix` and `modules/services/edge-proxy-ingress.nix`.

Operational posture:

- default web pattern keeps private-origin transport (`tailscale-upstream`) where practical
- `direct` exposure is deferred from normal phase-1 usage and only allowed as explicit edge-local localhost exception
- admin/sensitive public routes require access-gated edge policy and private-origin preference

Operator workflow (do-admin-1 edge host):

- precheck: `just check`
- deploy: `just deploy do-admin-1`
- deploy without rollback waiter: `just deploy do-admin-1 --rollback false`
- rollback (generation): `just rollback do-admin-1`
- runtime checks: `sudo scripts/edge-ingress-operational-checks.sh termix.shrublab.xyz /`

Deferred from phase-1 (intentional):

- cache layer and edge performance tuning
- failover/HA ingress topology
- advanced traffic management (rate limiting/WAF hardening beyond baseline)

## Known Risks and Constraints

- cloud disk naming can vary; stable identifiers are required for reliable runtime mounts
- bidirectional sync can propagate accidental deletes; versioning and conflict policies are mandatory
- temporary no-backup stance is acceptable only while data authority is still evolving
- aggressive cleanup introduces migration churn; documentation must remain authoritative throughout transition
