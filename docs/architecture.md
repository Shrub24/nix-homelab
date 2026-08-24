# Architecture

## Purpose

This repository is the infrastructure source of truth for a modular NixOS homelab fleet. It is being repurposed from a single developer VPS configuration into a multi-host, service-oriented infrastructure repository.

Primary objective:

- define and operate reproducible NixOS hosts across providers and regions
- start with a small, reliable base and scale architecture over time
- keep security boundaries explicit (network, secrets, host identity)

## Scope

In scope now:

- Oracle Cloud host `oci-melb-1` as a fleet node
- LA host `la-admin-1` as the active admin, edge, and identity node
- private-first service topology with a designated public edge bastion (Cloudflare + Caddy)
- native NixOS services: `navidrome` and `syncthing`
- optional Navidrome extension services: `audiomuse` (PostgreSQL + Redis + Flask/worker, managed via Podman containers) as a Navidrome-facing music-intelligence layer for Symfonium similar/radio behavior
- music service modules regrouped under `modules/services/music/` as a coherent feature subtree
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
- LA adoption of a preinstalled NixOS system is separate from later AU edge and US-East workload expansion; later work is not part of this migration

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

- `hosts/oci-melb-1/default.nix` and `hosts/la-admin-1/default.nix` as thin host assembly entrypoints
- `hosts/<host>/default.nix` for host identity, facts, feature enables, and narrow overrides
- `hosts/<host>/facter.json` for committed hardware facts via `hardware.facter.reportPath`
- `hosts/<host>/<component>.nix` for host-specific component overlays
- `modules/applications/<name>/default.nix` for feature composition roots (multi-service stacks), e.g. `modules/applications/music.nix`
- `modules/services/<domain>/<name>.nix` for reusable service modules grouped by domain (e.g. `modules/services/music/navidrome.nix`, `modules/services/music/audiomuse.nix`, `modules/services/music/syncthing.nix`)
- `modules/services/<name>.nix` for standalone leaf service modules outside a domain subtree
- `modules/services/virtualisation/windows-vm.nix` for the reusable declarative Windows VM layer (libvirt instances, attachment to the host-owned always-on bridge, loopback SPICE, virtiofs shares)
- `modules/applications/dj/` for the DJ composition root (Engine DJ library hosting on a Windows VM; see `docs/runbooks/engine-dj-guest-setup.md`)
- `modules/core/base.nix` for shared baseline NixOS policy
- `modules/core/users.nix` for shared user declarations
- `modules/profiles/base-server.nix` for common host profile composition, including shared Nix substitute/trust defaults
- `modules/providers/oci/default.nix` for OCI-specific host-safe defaults
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

- preinstalled NixOS hosts adopt non-destructively with `nixos-rebuild boot --target-host` through the existing sudo account, then reboot via the provider console; non-NixOS or repartitioned targets reimage with `nixos-anywhere`/`disko` through `just bootstrap <host> <addr>`
- two-step secrets bootstrap is the default because it reduces pre-install key handling risk
- the age recipient is derived only from the persistent SSH host key after its fingerprint is verified through the provider console; live `ssh-keyscan` results are diagnostic only and are never persisted as a recipient

Accepted advanced alternative:

- pre-generated host identity material can be used when first-boot decryption is required
- this is valid but is intentionally treated as a sharper option with higher bootstrap complexity

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
- Tagr is available as an operator-invoked manual metadata/cover fallback editor against canonical media paths
- `/srv/media` remains the authoritative shared media root
- `/srv/data` remains the service-state mount (`/srv/data/syncthing/config`, `/srv/data/navidrome`, `/srv/data/tagr`, `/srv/data/audiomuse`, `/srv/data/karakeep`, `/srv/data/bifrost`)
- canonical ingest/promotion paths:
  - download inbox: `/srv/media/inbox/slskd`
  - canonical library: `/srv/media/library`
  - unresolved/review lane: `/srv/media/quarantine/untagged`
  - approved rescue/staging lane: `/srv/media/quarantine/approved`
  - Traktor collection sync input: `/srv/media/traktor/collection.nml`
  - Traktor playlist workspace: `/srv/media/playlists/traktor/{export,import}`
- quarantine ownership is `music-ingest`; ACL grants explicit `media` read-only (`r-x`/`r-X`) access and `syncthing` write access for review and sync workflows
- Syncthing folder markers are codified with tmpfiles at `/srv/media/library/.stfolder` and `/srv/media/quarantine/.stfolder` owned by `syncthing:syncthing`
- beets remains installed as fallback rescue tooling and no longer owns default automated ingest
- Navidrome scope is explicit (`library + quarantine`) and inbox is excluded from the listening surface
- `modules/applications/music.nix` also defines `music-library` so `dev` and Syncthing share controlled library access
- `slskd` keeps downloads and incomplete state under `/srv/media` (`/srv/media/inbox/slskd` and `/srv/media/slskd-incomplete`)
- Beets state and import logs remain under `/srv/data/beets` (`/srv/data/beets/state`, `/srv/data/beets/logs`)
- Traktor M3U synchronization is a manual worker: `traktor-m3u-sync-export.service` exports NML playlists to M3U, and `traktor-m3u-sync-import.service` imports curated M3U files into the upstream sandbox folder (`Imported Playlists` by default). No timers or path watches are enabled until manual runs prove the path mapping and sandbox behavior.
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
- restic repositories are host-scoped: `shrublab-backup-la-admin-1` and `shrublab-backup-oci-melb-1`; the decommissioned host's repository was retained as migration recovery evidence

Consistency model:

- `export` services generate an app-native recovery artifact before the shared restic job runs; the artifact is the preferred restore input, while raw state remains captured only where it is a real service path
- `quiesce` services may later stop or stabilize around the backup window if required
- `live` services are captured without explicit coordination in the current baseline

Current export-first services:

- Kanidm via upstream automatic portable backups (`/var/lib/kanidm/backups/backup-*.json.gz`) — export-only contract; the live database is intentionally not restic-covered, and the unused `/srv/data/kanidm` path is not server state
- Vaultwarden via SQLite `.backup` export plus raw state coverage; the export stages under `/srv/data/state-backups/vaultwarden/db.sqlite3`
- Tagr via SQLite `.backup` export plus raw state coverage; the export stages under `/srv/data/state-backups/tagr/tagr.sqlite3`
- PostgreSQL shared cluster (OCI) via NixOS `services.postgresqlBackup` logical cluster export at `/srv/data/state-backups/postgres/all.sql.gz` (plus a previous-good artifact); the raw `/srv/data/postgres` directory is not described as portable backup coverage

Current live-state services:

- Syncthing, Navidrome, Beets state, Termix, Beszel hub, Karakeep, Bifrost non-log app state, Phoenix, Paperless local state/media/consume, paperless-gpt instances, and `/srv/media` library/quarantine (excluding `.versions`)
- Beszel hub coverage uses the real DynamicUser path `/var/lib/private/beszel-hub`, never the compatibility symlink `/var/lib/beszel-hub`
- AudioMuse — Postgres-only backup scope (durable app state); Redis queue/cache and temp audio working files are excluded from canonical backup scope per spec
- optional Cockpit loopback TLS material (`/var/lib/cockpit-loopback-tls`) when enabled

Explicitly excluded or external:

- ntfy is not restic-covered: auth users/tokens are declarative SOPS input and `auth.db` is recreated; cache/history/attachments are accepted ephemeral state (no attachments exist today). If attachments become authoritative, add their real path to restic before enabling them
- slskd local DB/history, Beszel agent state, and ACME/Caddy state are reproducible and intentionally excluded
- Karakeep object assets in its external R2 bucket are not in restic; they are an external recovery dependency, not a covered path, and no replication/versioning is claimed

Operator workflow:

- run an on-demand backup: `just backups run <host>` (starts `restic-backups-state.service`)
- inspect status/logs: `just backups status <host>` and `just backups logs <host>`
- backup failure monitoring: a failed `restic-backups-state.service` run surfaces through the fleet notification pipeline
- stage one path from a snapshot without touching live state: `just backups restore-stage <host> <snapshot> <absolute-include-path>` (writes to a root-only directory under `/var/tmp/state-restore/` and prints it)
- schedule, retention, and integrity checks follow the NixOS-declared restic policy in `modules/services/state-backups.nix` (`services.restic.backups` with `initialize`, `checkOpts`, `pruneOpts`, and the scheduled timer); the timer runs daily at 03:30 with a 1h randomization, retention is keep-daily 7 / keep-weekly 5 / keep-monthly 12, and the check uses `--read-data-subset=1/20`; there are no separate init/check/prune recipes

Restore posture:

- restore validation is part of the operator contract, not a post-hoc step; the canonical procedure is `docs/runbooks/state-restore.md`
- restores are staged first — never write restic output directly into `/`
- export-first services restore from their generated artifact first, with raw state retained for exact-state recovery and forensic fallback
- restore prep should verify available snapshots and target service stop/isolation requirements before modifying runtime state; repository credentials live in the deployed unit's environment and SOPS-rendered files, and the restore-staging recipe handles them

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

## Dependency Management

Ownership model:

- **Renovate** owns flake input updates (`flake.lock` via the `nix` manager) and OCI image reference updates (`policy/oci-images.nix` via a custom regex manager matching tag+digest form).
- **nvfetcher** owns non-flake upstream source metadata for custom package derivations (version, hash, source URL). Generated outputs land in `pkgs/_sources/generated.nix`, configured from `nvfetcher.toml` at the repo root.
- OCI image refs are centralized in `policy/oci-images.nix` and consumed by service modules as projections.
- Non-flake package source metadata is consumed by package code from `pkgs/_sources/generated.nix` (nvfetcher-generated; no wrapper needed).

Automation boundaries:

- Renovate runs on a schedule and opens PRs for flake input and OCI image updates.
- `nvfetcher-refresh` (GitHub Actions, `.github/workflows/nvfetcher-refresh.yml`) runs weekly and on manual dispatch, regenerates `pkgs/_sources/generated.nix`, and opens or updates a PR when changes are detected.
- Neither tool pushes dependency updates directly to `main`.

Operator commands:

- `just deps refresh` — regenerate nvfetcher-managed source metadata locally.

Adding a new non-flake upstream source:

1. Add a `[[package]]` section to `nvfetcher.toml` with the source name, fetcher, and version query.
2. Run `just deps refresh` to regenerate `pkgs/_sources/generated.nix`.
3. Import the generated metadata from `pkgs/_sources/generated.nix` in the consuming derivation.

Adding a new OCI image:

1. Add the image reference in `image:tag@sha256:digest` form to `policy/oci-images.nix`.
2. The image is available to service modules via `ociImages.<name>` (passed through `specialArgs`).
3. Renovate will propose digest and tag updates on its next scheduled run.

## Network and Access Model

### Network ownership (native systemd-networkd)

Fleet hosts own physical networking through the import-activated networking aspect (`modules/profiles/networking.nix`), not scripted networking or dhcpcd:

- hosts import the aspect and supply required `fleet.networking` facts: the uplink interface, plus bridge name and MAC when bridged, and a DNS override only when pinned
- the aspect emits native `systemd.network.{networks,netdevs}` units matched by exact interface name only — Podman bridges, `tailscale0`, veth, and libvirt links stay unmanaged by construction
- physical addressing is DHCPv4 with MAC-based client identity so provider/router leases and reservations survive
- `systemd-resolved` is the fleet resolver engine; per-link provider/DHCP DNS stays primary for routing domains, with `FallbackDNS` resilience
- `home-forge` runs an always-on host-owned `br0` bridge over `eno1` with a pinned MAC so the router reservation holds; applications do not own physical networking
- `oci-melb-1` disables `IPv6AcceptRA` on its uplink until the provider provisions IPv6
- network-owner cutovers are boot-staged (`deploy-rs --boot`), validated after a console reboot, then proven repeatable with a second ordinary reboot

Current model:

- Cloudflare + Caddy on `la-admin-1` is the public edge bastion for explicitly declared web routes
- Tailscale remains the private connectivity and cross-host upstream fabric
- Approved gated public services are exposed through edge policy (Cloudflare Access where required) with private-origin upstream preference
- `tailscale-upstream` is the default cross-host route transport mode
- `direct` is reserved for explicit edge-local localhost upstream exceptions
- `tailscale-only` remains the mode for routes that must not be publicly rendered
- ntfy notification dispatch is public-route based: LA's ntfy listener binds loopback (`127.0.0.1:2586`), local LA publishers post over that loopback origin, and cross-host publishers (e.g. `oci-melb-1`) post to the Cloudflare-backed public `https://ntfy.shrublab.xyz` route; the notification daemon sets an explicit `User-Agent` on its ntfy HTTP requests so Cloudflare Browser Integrity Check does not block them, and its server URL derives from the policy catalog
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

- `la-admin-1` hosts the private admin surface composition under `modules/applications/admin/default.nix`
- Quantum replaces Filebrowser as the file-management UI
- Quantum source topology is split between reusable service wiring and host-owned source declarations:
  - reusable runtime/container logic lives in `modules/services/admin/quantum.nix`
  - host-specific source declarations live beside the host, currently `hosts/la-admin-1/quantum.nix`
- Quantum on `la-admin-1` exposes:
  - a local `la-admin-1` source
  - remote host sources that are explicitly declared and mounted through the chosen transport model

Current Cockpit shape:

- Cockpit uses per-host sessions rather than login-page host chaining
- public entrypoints are shared-host subpaths:
  - `cockpit.shrublab.xyz/la-admin-1`
  - `cockpit.shrublab.xyz/oci-melb-1`
- `la-admin-1` local Cockpit upstream is proxied over localhost HTTPS with a host-local generated CA/leaf pair trusted explicitly by Caddy
- `oci-melb-1` is exposed through host-local `tailscale serve --https=9443`, and the edge host proxies to that Tailscale HTTPS endpoint
- Cockpit-specific transport ownership stays in Cockpit-owned modules:
  - `modules/services/admin/cockpit.nix`
  - `modules/services/admin/cockpit/loopback-tls.nix`
  - `modules/services/admin/cockpit/tailscale-serve.nix`
- host overlays such as `hosts/la-admin-1/cockpit-auth.nix` and `hosts/oci-melb-1/cockpit-auth.nix` only provide host-specific values (service-user secret path, local enable flags, public host/urlRoot overrides)

Potential later model:

- edge HA/failover and advanced policy hardening once phase-1 operational posture is stable

## Deployment Architecture

Bootstrap and rollout order:

- preinstalled NixOS hosts adopt non-destructively (`nixos-rebuild boot --target-host` through the existing sudo account, reboot via provider console); non-NixOS or repartitioned targets reimage with `nixos-anywhere`/`disko` via `just bootstrap <host> <addr>`
- regular host updates via `deploy-rs` (`just deploy <host>`)
- dry-activation and validation via `just _activate <host>` and `just checks all`
- remote network-owner cutovers are installed with `deploy-rs --boot` and applied on reboot rather than live-switched over SSH
- recovery baseline rollouts must verify the `rescue` user contract, scheduled reboot timer, and rollback path before the change is treated as complete

Fleet tooling posture:

- structure now for future fleet tools
- `deploy-rs` is the primary host deployment path (`deploy.nodes` in flake output)
- per-host deploy metadata is defined in `lib/deploy/hosts.nix`, with reusable wiring in `lib/deploy/default.nix`
- cross-host consumers resolve stable service IDs through the policy catalog (`config.repo.web.catalog`); physical deployment facts (`edgeHost`, `deployOrder`) live only in `lib/deploy/hosts.nix` and must never be interpreted as NixOS nodes
- keep `nixos-anywhere` for bootstrap and break-glass flows; use `deploy-rs` for regular host updates
- GitHub Actions is the canonical hosted validation and deploy automation surface:
  - lightweight validation runs on PRs to `main` and pushes to non-`main`
  - exact deploy-profile remote-build validation is reserved for manual `workflow_dispatch` runs
  - full deploys are manual-only via `workflow_dispatch`, with validation first and serial deploy order (`la-admin-1` before `oci-melb-1`)
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
- before any bootstrap/deploy operation, run `just _preflight <host>` to enforce access-safety invariants (`openssh` enabled, tcp/22 allowed, declarative `dev`/`root` SSH keys present)

Operator commands:

- deploy: `just deploy oci-melb-1` (or `just deploy la-admin-1`)
- deploy without rollback: `just deploy la-admin-1 --rollback false`
- network-owner cutover: `nix run .#deploy-rs -- --skip-checks --boot .#la-admin-1`, then reboot from console
- dry-activate: `just _activate oci-melb-1`
- checks: `just checks all` (repo-owned validation checks: secret scope, ssh fingerprint, web policy/catalog, host-phase contracts, restore contracts)
- Cloudflare policy export sync: `just tofu-sync`
- Cloudflare runtime render: `just tofu-runtime`
- backups: `just backups run <host>`, `just backups status <host>`, `just backups logs <host>`, `just backups restore-stage <host> <snapshot> <path>`

Runbooks:

- `docs/runbooks/host-initialization.md` is the canonical generic bring-up runbook (adoption vs reimage, fact capture, host-key-to-age, handoff, first boot, deploy-rs steady state)
- `docs/runbooks/state-restore.md` is the canonical state-restore runbook (staging, apply, ownership, validation for every backed-up service)
- `docs/runbooks/admin-host-migration.md` records LA transfer facts and the cutover sequence only

Recovery verification checklist:

- confirm `services.hostRecovery` is enabled on the target host and points at the host-scoped `system.yaml` secret file
- confirm the `rescue` account exists, is intended for console-only use, and cannot be used for SSH login
- confirm `host-recovery-reboot.timer` is present with the expected weekly cadence
- keep provider/serial console access available until the new generation has been verified
- for `oci-melb-1`, note that some local builds on the x86_64 admin machine remain limited by non-substitutable `aarch64-linux` derivations; use remote/host-side validation when a full local build cannot complete

## AudioMuse Deployment Lifecycle

AudioMuseAI is an optional Navidrome similarity extension composed from `applications.music.audiomuse.enable`. The feature toggle deploys infrastructure; E2E validation requires additional operator steps.

### Lifecycle stages

| Stage | What happens | Who completes it |
|---|---|---|
| **1. Deploy toggle** | Set `applications.music.audiomuse.enable = true` in host config, add SOPS secret keys (see secret template), deploy with `just deploy <host>`. AudioMuse Podman containers, Postgres, Redis, Navidrome plugin binary, and runtime flags are placed. Service is deployable but not usable end-to-end. | Operator (repo config) |
| **2. First-run AudioMuse setup** | Reach the AudioMuse web UI on `<host-tailscale-ip>:8000` (or the port configured in `services.audiomuse.port` via Tailscale). Complete the upstream setup wizard: create admin user, configure Navidrome base URL if not auto-detected. Wizard populates the AudioMuse application database. | Operator (SSH + browser over Tailscale) |
| **3. Navidrome plugin enablement** | In the Navidrome Admin UI (`<host>:4533` over Tailscale), navigate to Plugins → audiomuse.ai. Enable the plugin, set API URL to the AudioMuse web container address, and supply the API token matching the SOPS `audiomuse/api_token` key. | Operator (browser over Tailscale) |
| **4. Similar/radio validation (E2E)** | On a Symfonium client connected to the Navidrome/OpenSubsonic endpoint over Tailscale, select a track and invoke similar or radio. Confirm results are returned and reflect AudioMuse-backed similarity (not Navidrome's fallback). | Operator (Symfonium client on tailnet) |

### Infrastructure vs. validation distinction

- **Deployed infrastructure** (stage 1): Podman containers running, plugin binary installed, Postgres persisting, Navidrome flags active. Verified by `systemctl status podman-audiomuse-*`, container health, and Navidrome plugin directory inspection.
- **E2E validated** (stage 4): Symfonium actually returns similar/radio results sourced from AudioMuse. Verified by end-user playback test.

The feature is not accepted as working until stage 4 is confirmed. Stages 2–4 cannot be fully automated because upstream AudioMuse persists setup state in application-managed data (not a declarative import/export interface).

### Exposure and access

- AudioMuse follows the current repo exposure model: internal-service-first, private over Tailscale. Do not add a new public ingress route for AudioMuse unless the existing edge policy explicitly composes one.
- Default Navidrome plugin URL for AudioMuse is `http://host.containers.internal:8000` (via the Podman host bridge interface).
- Operator bootstrap access to the AudioMuse web UI is over Tailscale to the host port (`<tailscale-ip>:8000`).
- Navidrome admin UI is already available over Tailscale (`<tailscale-ip>:4533` or the declared edge route if configured).

### Secrets contract

AudioMuse registers these SOPS-backed keys through `services.audiomuse.secretFiles.host` (consumed from the existing music application host secret file):

| Key | Purpose |
|---|---|
| `audiomuse/user` | AudioMuse admin username (wizard pre-fill) |
| `audiomuse/password` | AudioMuse admin password (wizard pre-fill / first-run auth) |
| `audiomuse/api_token` | API token shared with the Navidrome plugin |
| `audiomuse/jwt_secret` | JWT signing secret for the AudioMuse API |
| `audiomuse/postgres_password` | Password for the `audiomuse` Postgres role |

Add these keys to the music application secrets file (`secrets/applications/music.yaml`) using the standard SOPS workflow. Do not manually decrypt or edit encrypted secret payloads.

### Backup scope

AudioMuse durable state is Postgres only (the shared cluster on OCI); `/srv/data/audiomuse/redis` and `/srv/data/audiomuse/temp` audio working files are intentionally excluded from canonical backup scope. Restoring AudioMuse follows the PostgreSQL logical-export restore in `docs/runbooks/state-restore.md`; in summary:
1. Restore the shared cluster from the `services.postgresqlBackup` logical export (`all.sql.gz`), not from a raw data-directory copy.
2. Start containers (Postgres carries the restored data, Redis and worker re-populate from the API).
3. Re-run setup wizard if application-level records were stored only in the database after the snapshot time.

Known gap: AudioMuse's own application-level records (users, keys, Navidrome binding metadata) live in Postgres and are only as current as the last backup. Navidrome plugin configuration (enablement, API URL, token) is stored in the Navidrome application database and backed up as part of the Navidrome live-state backup.

Note: `just deploy` takes positional host arguments (`just deploy oci-melb-1`), not `host=...`.

Remote networking note:

- the decommissioned host used declarative `systemd-networkd` with static `ens3`/`ens4` addressing while `cloud-init` remained metadata-only (historical; the host is retired)
- switching network ownership on a remote host can drop the active SSH session mid-activation even when the target generation is correct
- treat network-owner transitions as reboot-time changes with provider console available for verification and rollback

## Phase-1 Edge Ingress Operations

Phase-1 ingress is implemented with `modules/applications/edge-ingress.nix` and `modules/services/edge-proxy-ingress.nix`.

Operational posture:

- default web pattern keeps private-origin transport (`tailscale-upstream`) where practical
- `direct` exposure is deferred from normal phase-1 usage and only allowed as explicit edge-local localhost exception
- admin/sensitive public routes require access-gated edge policy and private-origin preference

Operator workflow (la-admin-1 edge host):

- precheck: `just check`
- deploy: `just deploy la-admin-1`
- deploy without rollback waiter: `just deploy la-admin-1 --rollback false`
- rollback (generation): `just rollback la-admin-1`
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
