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
- home-forge host as the media/DJ workload node (music application and Engine DJ Windows VM)
- private-first service topology with a designated public edge bastion (Cloudflare + Caddy)
- native NixOS services: `navidrome` and `syncthing`
- the complete music application runs on `home-forge` rooted at the host-selected music application root `/srv/storage/media/music`; AudioMuse compute runs there with its PostgreSQL database in OCI's shared cluster over Tailscale (Navidrome-facing music-intelligence layer for Symfonium similar/radio behavior)
- music service modules regrouped as a coherent feature subtree under the music domain (`modules/music/`), with the Stage 6 private implementation leaves for Beets secrets/CLIs, ingest, and storage/permission ownership (D-052; the leaves became sibling contributors in the post-Stage-8 services-tree conversion)
- the music stack is composed by the discovered home-forge-only `music` deployment aspect (`modules/music/music.nix`, selected from the `home-forge` host record), whose selection provides `applications.music.enable`; `dj` remains a separately selected aspect and consumes the read-only `applications.music.contract.{storageRoot,libraryDir,playlistsDir}` — worker adoption of `libraryDir`/`playlistsDir` in the Engine export job paths is deferred (D-052)
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
- implemented (D-047 Stage 1, in `dendritic-stage-1-scaffold-hosts`): composition uses flake-parts with `denful/import-tree` discovery over `modules/`, named `flake.modules.nixos` aspects, and a typed `nixos.configurations.<host>` registry (`modules/flake/registry.nix`) that materializes `nixosConfigurations` through `inputs.nixpkgs.lib.nixosSystem`; host assemblies live under `modules/hosts/<host>/` and the old `specialArgs` bus is gone (Stage 8 / D-056 replaced the concrete table with discovered `nixos.hosts.<id>` host records materialized by `modules/flake/host-registry.nix`, reducing `modules/flake/registry.nix` to the `flake.bootstrap.nodes` projection). Dendritic Stage 2 (`dendritic-stage-2-foundation-aspects`) published the five foundation aspects — `base`, `shell`, `networking`, `tailscale`, `notify` — selected explicitly by every host record, and deleted `modules/core/` and `modules/profiles/`. Dendritic Stage 3 (`dendritic-stage-3-operational-aspects`) published the operational aspects — `builder-access` and `observability-agent`, plus the then-combined `backups` aspect (split by D-055 into `state-backups` and `cache-publisher`) — selected by every host record, folding the five deferred operational leaves under them (see D-049). Dendritic Stage 4 (`dendritic-stage-4-source-model-realignment`, D-050) separated source ownership from deployment granularity: normal feature source files are auto-discovered flake-parts contributors (several may merge into one aspect), the central `modules/flake/aspects.nix` was replaced by concern-owned contributors, `provenance`/`oci-images`/`fleet-packages` are classified as infrastructure support, `dj` selection enables `applications.dj`, and plain class-oriented leaves plus the filter are transitional rather than the endpoint. Dendritic Stage 5 (`dendritic-stage-5-shared-source-contributors`, D-051) deleted `modules/shared/` and `modules/storage/`, relocated the remaining private leaves to the concern-owned `_aspects`/`_backups`/`_builder-access` paths, promoted `web-policy` to the all-host support quartet, proved the multi-contributor single-aspect merge with `identity-client` (`identity-oidc.nix` + `kanidm-host-auth.nix`) (D-059 retired that bundle: the OIDC contract is the intrinsic `modules/identity/_oidc.nix` and the capability is `kanidm-host-auth`), and shrank the filter from six entries to four. Dendritic Stage 6 (`dendritic-stage-6-music-composition`, D-052) converted the music stack into the discovered home-forge-only `music` aspect (then at `modules/flake/music.nix`, now `modules/music/music.nix`) (selection provides `applications.music.enable`), moved Beets secret/template/CLI ownership plus the ingest and storage/permission mechanisms into private leaves in the service tree, gave `dj` a typed read-only `applications.music.contract` with a named assertion, and left the four-root filter unchanged. Dendritic Stage 7 (`dendritic-stage-7-placement-aspects`, D-053) published the remaining placement aspects (the OCI/LA/platform set `oci`, `edge`, `cockpit`, `push-server`, `identity-provider` and the OCI/home-forge workloads `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, `omniroute`, plus the then-`admin-hub` bundle), relocated the admin/edge/DJ/OCI implementations beside their concern owners, deleted the `applications`/`providers` evaluator-class roots, and shrank the temporary filter to exactly `hosts` and `services`; it is implementation-complete but not deployed and not archived. The identity/admin decoupling change (`decouple-identity-admin-capabilities`, D-054) then dissolved `admin-hub` and `applications.admin` with no replacement bundle, extracted `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook` as self-contained placement aspects, made identity consumption directional, and removed Quantum from the active module graph as disabled/deferred (re-enable only as a self-contained aspect)
- host identity and contracts (Stage 8 / `dendritic-stage-8-host-identity-contracts`, D-056): each host is a discovered contributor declaring a typed `nixos.hosts.<id>` record (target system, Tailscale identity read from the single `policy/globals.nix` `tailnet.suffix`, deferred composition, reimage facts) that `modules/flake/host-registry.nix` validates with named errors and materializes into `nixosConfigurations`; `modules/flake/registry.nix` is reduced to the `flake.bootstrap.nodes` projection, the import-tree filter is exactly `[ "services" ]`, deploy metadata (`modules/flake/deploy.nix`) and web policy (`modules/flake/web-policy.nix`) fail closed on unknown host references, and `modules/fleet/internal-contracts.nix` publishes the two internal transport contracts (shared PostgreSQL, private Niks3 write API) whose provider host must enable the capability on the declared port — identity and ntfy deliberately stay web-catalog contracts

- flake entrypoint and shared dependencies (D-060): `flake.nix` is generated by `flake-file` from declarations in the tree (`modules/flake/inputs.nix` for the shared baseline and the framework inputs, plus any contributor that declares the input its capability needs), regenerated with `nix run .#write-flake` and gated by a built `check-flake-file` in `just checks all` and CI; nix-fleet owns the pins the repositories share (`nixpkgs`, `flake-parts`, `import-tree`, `sops-nix`, `niks3`), declared here as follows aliases so one nix-fleet revision moves the shared baseline, and `just dev nf-eval`/`nf-build`/`nf-check` evaluate against a local nix-fleet checkout without touching the committed lock

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

- `modules/hosts/oci-melb-1/default.nix`, `modules/hosts/la-admin-1/default.nix`, and `modules/hosts/home-forge/default.nix` as discovered host contributors declaring the typed `nixos.hosts.<id>` records that the generic materializer in `modules/flake/host-registry.nix` turns into `nixosConfigurations`
- `modules/hosts/<host>/default.nix` for the canonical host record (identity, target system, aspect selection, reimage facts) and `modules/hosts/<host>/_nixos.nix` for the host-private composition, facts, feature enables, and narrow overrides
- `modules/hosts/<host>/facter.json` for committed hardware facts via `hardware.facter.reportPath`
- `modules/hosts/<host>/_<component>.nix` for host-specific component overlays (underscore-prefixed files are private and excluded from flake-parts discovery; reimage bootstrap metadata lives in the host's own record)
- discovered concern contributors `modules/<domain>/<concern>.nix` for feature composition roots (multi-service stacks): `modules/identity/`, `modules/notifications/`, `modules/cache/`, `modules/music/`, `modules/admin/`, `modules/edge/`, `modules/oci/`, and `modules/fleet/` (Stage 8 / D-056); Stage 6 converted music and Stage 7 converted admin/edge/DJ/provider/product placement (D-052, D-053), so no `modules/applications/` root remains
- `modules/<domain>/<name>.nix` for reusable service modules grouped by domain (e.g. `modules/music/navidrome.nix`, `modules/music/audiomuse.nix`, `modules/music/syncthing.nix`, `modules/music/ingest.nix`, `modules/music/storage.nix`, and the Beets contributor at `modules/music/beets.nix` with its asset directory `modules/music/beets/files/` and runner helper `modules/music/_beets/runners.nix`)
- `modules/<domain>/<name>.nix` for standalone leaf service modules outside a domain subtree (e.g. `modules/flake/tailscale.nix`, `modules/cache/niks3-cache.nix`)
- `modules/music/windows-vm.nix` for the reusable declarative Windows VM layer (libvirt instances, attachment to the host-owned always-on bridge, loopback SPICE, virtiofs shares)
- `modules/music/dj-engine.nix` for the DJ engine implementation (Engine DJ library hosting on a Windows VM; see `docs/runbooks/engine-dj-guest-setup.md`), a sibling contributor of the discovered `dj` aspect
- concern-owned contributors for the published `flake.modules.nixos.<aspect>` records, located in their domain directory since Stage 8 (D-056) — foundation `modules/flake/{shell,networking,tailscale}.nix` and the two-contributor `base` (`modules/flake/base/{foundation,host-recovery}.nix`); notifications `modules/notifications/{notify,push-server}.nix`; operational `modules/backups/state-backups.nix` (declaration surface `modules/backups/state-backups/_consumer.nix`), `modules/cache/cache-publisher.nix`, and `modules/flake/{builder-access,observability-agent}.nix`; application/identity `modules/music/{music,dj}.nix` and the `kanidm-host-auth` capability (`modules/identity/kanidm-host-auth.nix`, the Kanidm Unix/PAM/SSH integration; D-059 renamed it from `identity-client`) with the intrinsic OIDC contract it reads (`modules/identity/_oidc.nix`); the fleet contract `modules/fleet/internal-contracts.nix`; placement `modules/oci/oci.nix`, `modules/edge/edge.nix`, `modules/admin/{cockpit,termix,vaultwarden,homepage,gatus,beszel,webhook}.nix`, `modules/identity/identity-provider.nix`, `modules/cache/niks3-cache.nix`, `modules/database/postgres.nix`, and `modules/flake/{paperless,ai-gateway,karakeep,phoenix,omniroute}.nix` (each owning its capability's top-level enablement; `admin-hub` was removed and its members split into individual aspects by D-054) — plus the infrastructure support quartet `provenance`, `oci-images`, `fleet-packages`, `web-policy` in `modules/flake/`; four of the contributors above consume a shared nix-fleet mechanism through one local convention contributor each (`tailscale`, `builder-access`, `observability-agent` → `beszel-agent`, `niks3-cache`), so the mechanism lives upstream and this repository keeps the fleet's secret paths, policy values, and host-facing option names (D-061), with sibling contributors beside their owner (`modules/flake/base/host-recovery.nix`, `modules/cache/cache-publisher/{upload-client,post-deploy}.nix`, `modules/music/{dj-engine,windows-vm}.nix`, `modules/edge/edge-ingress-application.nix`) and `_` left for value-imported helpers and declaration-only contracts (`modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, `modules/admin/homepage/_data.nix`, `modules/backups/state-backups/_consumer.nix`, `modules/database/postgres/_consumer.nix`, `modules/identity/_oidc.nix`, `modules/identity/_kanidm-packages.nix`). The Stage 6 music leaves converted with the rest of the service tree: they are now discovered contributors under `modules/music/`
- `modules/flake/base/foundation.nix` for shared baseline NixOS policy, users, and the typed `fleet.foundation.bootLoader` / `fleet.foundation.buildTmpfsSize` host facts
- `modules/flake/shell.nix` for the shell baseline (zsh/p10k, wezterm, nix-index comma) with the prompt theme at `modules/flake/shell/p10k.zsh`
- `modules/flake/networking.nix` for the native networkd contract rendered from `fleet.networking` host facts
- `modules/oci/oci.nix` for OCI-specific host-safe defaults, published as the `oci` aspect (selected on `oci-melb-1`) with the provider body inline
- host-local disko layouts beside their consumer (underscore-private since D-056): `modules/hosts/oci-melb-1/_disko-single-disk-split.nix` (split root/data/nix/media), `modules/hosts/home-forge/_disko-two-disk.nix`; the shared `modules/storage/` menu was removed in Stage 5
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

- `lib/secrets.nix` provides reusable helpers: `mkSecretFileOption`, `mkSecretKeyOption`, `mkRequiredSecretAssertion`, `mkSecretsFromMap`
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
- `modules/hosts/oci-melb-1/_disko-single-disk-split.nix` is the canonical declarative boundary for that recovered host shape
- host-specific sizing stays in `modules/hosts/oci-melb-1/_nixos.nix`, while the partition/mount contract remains declarative in the host-local layout

Current media/data flow (music application on `home-forge`):

- the complete music application (Navidrome, AudioMuse compute, Syncthing, slskd/Beets/Tagr ingest services) runs on `home-forge`; `oci-melb-1` disables `applications.music`, retains the shared PostgreSQL cluster (AudioMuse database + backup), and keeps its copied `/srv/media` tree and prior music service state on disk only as rollback insurance
- LA edge routes `music` (Navidrome), `slskd`, and `tagr` to `home-forge` over Tailscale upstreams (`policy/web-services.nix`)
- `home-forge` selects the music application root via `musicStorageRoot` in `modules/hosts/home-forge/default.nix`: `storageRoot=/srv/storage/media/music` with `library/`, `playlists/`, `inbox/`, `quarantine/`, and `.versions/` beneath it; `/srv/data` remains the service-state mount (`/srv/data/syncthing/config`, `/srv/data/navidrome`, `/srv/data/tagr`, `/srv/data/audiomuse`, `/srv/data/beets`)
- `applications.music` requires explicit `storageRoot`/`dataRoot` host bindings with no fleet defaults (`policy/globals.nix` carries no music paths); the discovered `modules/music/music.nix` aspect (selected only on `home-forge`) owns composition and injects the derived paths into the music contributors `modules/music/{beets,ingest,storage}.nix`, with the storage contributor owning creation of the shared roots and layout directories under `storageRoot`; lower-level service modules may add ACLs, marker files, or service-specific subdirectories, but do not redefine those shared root directory ownership contracts
- Navidrome's MusicFolder and Syncthing's `library` folder use `library/`; Engine DJ's `M:` share maps the whole music root through virtiofs (guest sees `M:\library`, `M:\playlists`, `M:\Engine Library`, `M:\inbox`, `M:\quarantine`). `M:\Engine Library` is a real directory on the share (host `<storageRoot>/Engine Library`) — there is no separate Engine share, mount tag, or guest junction; the operator points the Windows Music known-folder directly at `M:` so Engine resolves `Music\Engine Library` to `M:\Engine Library` (see D-044, D-046, and `docs/runbooks/engine-dj-guest-setup.md`). The DJ aspect derives `sharePath`/`musicStorageRoot` from the `applications.music.contract.storageRoot` contract value (host literals removed in Stage 6); worker adoption of `contract.libraryDir`/`contract.playlistsDir` in the Engine export job paths is deferred (D-052)
- Syncthing hub is `home-forge`: sendreceive `library/`, `quarantine/`, and `inbox/` folders are shared with the `arch` and `windows` devices, with staggered versioning archived under `.versions/`
- canonical ingest/promotion paths:
  - download inbox: `<storageRoot>/inbox/slskd` (manual drop area at `<storageRoot>/inbox/dropbox`; incomplete state under `<storageRoot>/inbox/slskd-incomplete`)
  - canonical library: `<storageRoot>/library`
  - unresolved/review lane: `<storageRoot>/quarantine/untagged`
  - approved rescue/staging lane: `<storageRoot>/quarantine/approved`
  - playlist export target: the Engine library DB at `<storageRoot>/Engine Library/Database2/m.db` (`/srv/storage/media/music/Engine Library/Database2/m.db`, a real directory on the `M:` share), written directly by the `traktor-m3u-sync` engine export job (chained from the Navidrome M3U import; `track_path_prefix=../library`; see D-046)
- quarantine ownership is `music-ingest`; ACL grants explicit `media` read-only (`r-x`/`r-X`) access and `syncthing` write access for review and sync workflows
- Syncthing folder markers are codified with tmpfiles under the library, quarantine, and inbox folders owned by `syncthing:syncthing`
- beets remains installed as fallback rescue tooling and no longer owns default automated ingest; its state and import logs remain under `/srv/data/beets`
- Tagr is available as an operator-invoked manual metadata/cover fallback editor against canonical media paths
- Navidrome scope is explicit (`library + quarantine`) and inbox is excluded from the listening surface
- AudioMuse compute (web, worker, local Redis) runs on `home-forge`; its PostgreSQL database stays in OCI's shared cluster over Tailscale/MagicDNS — an OCI/tailnet outage degrades AudioMuse, not core Navidrome
- no duplicate media staging dataset is introduced

Future evolution:

- when moving toward `rclone`/VFS and processing workflows, an ingest pipeline can be introduced
- hook-driven processing is expected later, not required for initial baseline

## Backup Architecture

Current baseline:

- mutable service state is backed up with NixOS-native `services.restic.backups`
- backup scope is state-first: `/srv/data` subtrees and generated recovery artifacts are in scope, and media-root coverage (`/srv/storage/media/music` on `home-forge`, `/srv/media` on `oci-melb-1`) is controlled by host backup policy
- each host writes to its own dedicated Cloudflare R2 bucket using host-scoped credentials and a host-unique restic password
- non-secret transport defaults (`endpoint`, `region`, path-style behavior) stay canonical in `policy/globals.nix`
- restic repositories are host-scoped: `shrublab-backup-la-admin-1`, `shrublab-backup-oci-melb-1`, and `shrublab-backup-home-forge`; the decommissioned host's repository was retained as migration recovery evidence
- the operational capability is split (D-055): `state-backups` is `modules/backups/state-backups.nix` (its declaration surface, including the `services.state-backups.services.<name>` registry producers register in, is `modules/backups/state-backups/_consumer.nix`) and derives the conventional host secret path `secrets/hosts/<host>/system.yaml` plus the `shrublab-backup-<host>` bucket, gating enablement on the secret file's existence (two-step sops bootstrap); `cache-publisher` owns the upstream `niks3-auto-upload` module and the sibling contributors `modules/cache/cache-publisher/upload-client.nix` and `modules/cache/cache-publisher/post-deploy.nix`, resolves its write endpoint through the `niks3Write` internal contract (D-056), injects the post-deploy `nix-path-filter` package per system, and asserts `services.notification-daemon.monitor.enable` (the `notify` aspect owns monitor composition) without importing `notify`. The classified `nix.settings.post-build-hook = lib.mkForce ""` suppression is required because upstream `niks3-auto-upload` has no separate hook-disable option. The OCI cache server leaf is `modules/cache/niks3-cache.nix`, owned by the `niks3-cache` aspect.

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

- Syncthing, Navidrome, Beets state, Termix, Beszel hub, Karakeep, Bifrost non-log app state, Phoenix, Paperless local state/media/consume, paperless-gpt instances, and music library/quarantine excluding `.versions` (`/srv/storage/media/music` on `home-forge`, retained rollback copy under `/srv/media` on `oci-melb-1`) — the music application now runs on `home-forge`, so the listed OCI music-state entries describe retained rollback copies; home-forge has active music-state backup contracts for Navidrome, Syncthing, Beets, Tagr, and media
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
- schedule, retention, and integrity checks follow the NixOS-declared restic policy in `modules/backups/state-backups.nix` (`services.restic.backups` with `initialize`, `checkOpts`, `pruneOpts`, and the scheduled timer); the timer runs daily at 03:30 with a 1h randomization, retention is keep-daily 7 / keep-weekly 5 / keep-monthly 12, and the check uses `--read-data-subset=1/20`; there are no separate init/check/prune recipes

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

- Only hosts push, post-deploy, via `modules/cache/cache-publisher/post-deploy.nix` (composed by the `cache-publisher` aspect; the activation-triggered `niks3-hook send` reuses the upstream `niks3-auto-upload` daemon/socket while the automatic Nix post-build-hook stays suppressed by the classified `nix.settings.post-build-hook = lib.mkForce ""`)
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
2. The image is available to service modules via `config.repo.ociImages.<name>` (typed policy aspect sourced from `policy/oci-images.nix`; no `specialArgs`).
3. Renovate will propose digest and tag updates on its next scheduled run.

## Network and Access Model

### Network ownership (native systemd-networkd)

Fleet hosts own physical networking through the import-activated `networking` foundation aspect (published from `modules/flake/networking.nix`), not scripted networking or dhcpcd:

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
- host recovery secret registration remains feature-owned by `modules/flake/base/host-recovery.nix`, while hosts only bind the host secret file path and enable the feature
- recovery readiness is exercised with a declared weekly reboot timer so console/login regressions are more likely to surface during routine operations rather than only during an outage

## Admin Surface Model

Current admin-service shape:

- `la-admin-1` composes its admin capabilities from independently selected aspects: `identity-provider` (sole owner of Kanidm runtime, provisioning, and the OIDC provisioning secret-source map), `cockpit`, and the individual workload aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook`; there is no `admin-hub` aspect and no `applications.admin` namespace (D-054)
- admin workloads consume the canonical OIDC contract and never configure the provider; shared endpoint data comes from web policy
- Quantum is fully retired rather than disabled: the service leaf, `modules/hosts/la-admin-1/quantum.nix`, the `/srv/data` operator ACL/reconcile unit, the reserved SSH secret registrations, the Kanidm catalog entry, the `policy/identity.json` client, and the OIDC client registration are all removed, and `tests/check-identity-contract-directionality.sh` fails if any of them returns. Any future re-enable lands as a self-contained aspect consuming canonical identity contracts and does not restore admin-hub coupling

Current Cockpit shape:

- Cockpit uses per-host sessions rather than login-page host chaining
- public entrypoints are shared-host subpaths:
  - `cockpit.shrublab.xyz/la-admin-1`
  - `cockpit.shrublab.xyz/oci-melb-1`
- `la-admin-1` local Cockpit upstream is proxied over localhost HTTPS with a host-local generated CA/leaf pair trusted explicitly by Caddy
- `oci-melb-1` is exposed through host-local `tailscale serve --https=9443`, and the edge host proxies to that Tailscale HTTPS endpoint
- Cockpit-specific transport ownership stays in Cockpit-owned modules:
  - `modules/admin/cockpit.nix`
  - `modules/admin/cockpit/loopback-tls.nix`
  - `modules/admin/cockpit/tailscale-serve.nix`
- host overlays such as `modules/hosts/la-admin-1/_cockpit-auth.nix` and `modules/hosts/oci-melb-1/_cockpit-auth.nix` only provide host-specific values (service-user secret path, local enable flags, public host/urlRoot overrides)

Potential later model:

- edge HA/failover and advanced policy hardening once phase-1 operational posture is stable

## Deployment Architecture

Bootstrap and rollout order:

- preinstalled NixOS hosts adopt non-destructively (`nixos-rebuild boot --target-host` through the existing sudo account, reboot via provider console); non-NixOS or repartitioned targets reimage with `nixos-anywhere`/`disko` via `just bootstrap <host> <addr>`
- regular host updates via `deploy-rs` (`just deploy <host>`)
- dry-activation and validation via `just _activate <host>` and `just checks all`
- local evaluation resolves the repository with the Git-tree form `.#`, so the evaluated generation and the published `/etc/nixos-source` carry the tracked configuration set; the Git index is a precondition guarded by `tests/check-flake-source-tracking.sh` (D-057)
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
- hosts inherit one shared substitute/trust baseline through the `base` foundation aspect (`modules/flake/base/foundation.nix`)
- current substitute defaults point at `nixbuild.net` over `ssh://eu.nixbuild.net`
- host-side substitute/trust settings are policy-driven through `policy/globals.nix` and applied by the `base` foundation aspect rather than repeated in host files
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

| Stage                                 | What happens                                                                                                                                                                                                                                                                                                                                                                                                       | Who completes it                        |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------- |
| **1. Deploy toggle**                  | Set `applications.music.audiomuse.enable = true` in the `home-forge` host config, add SOPS secret keys (see secret template), deploy with `just deploy <host>`. AudioMuse Podman containers (web/worker/local Redis), the packaged Navidrome plugin file, and runtime flags are placed; the PostgreSQL database is the shared OCI cluster reached over Tailscale. Service is deployable but not usable end-to-end. | Operator (repo config)                  |
| **2. First-run AudioMuse setup**      | Reach the AudioMuse web UI on the `home-forge` Tailscale IP at the configured AudioMuse port (default 8000). Complete the upstream setup wizard: create admin user, configure Navidrome base URL if not auto-detected. Wizard populates the AudioMuse application database.                                                                                                                                        | Operator (SSH + browser over Tailscale) |
| **3. Navidrome plugin enablement**    | In the Navidrome Admin UI (home-forge `:4533` over Tailscale), navigate to Plugins → audiomuse.ai. Enable the plugin, set API URL to the AudioMuse web container address, and supply the API token matching the SOPS `audiomuse/api_token` key.                                                                                                                                                                    | Operator (browser over Tailscale)       |
| **4. Similar/radio validation (E2E)** | On a Symfonium client connected to the Navidrome/OpenSubsonic endpoint over Tailscale, select a track and invoke similar or radio. Confirm results are returned and reflect AudioMuse-backed similarity (not Navidrome's fallback).                                                                                                                                                                                | Operator (Symfonium client on tailnet)  |

### Infrastructure vs. validation distinction

- **Deployed infrastructure** (stage 1): Podman containers running, plugin binary installed, Postgres persisting, Navidrome flags active. Verified by `systemctl status podman-audiomuse-*`, container health, and Navidrome plugin directory inspection.
- **E2E validated** (stage 4): Symfonium actually returns similar/radio results sourced from AudioMuse. Verified by end-user playback test.

The feature is not accepted as working until stage 4 is confirmed. Stages 2–4 cannot be fully automated because upstream AudioMuse persists setup state in application-managed data (not a declarative import/export interface).

### Exposure and access

- AudioMuse follows the current repo exposure model: internal-service-first, private over Tailscale. Do not add a new public ingress route for AudioMuse unless the existing edge policy explicitly composes one.
- AudioMuse reaches its PostgreSQL database in OCI's shared cluster over Tailscale/MagicDNS (tailnet-only + SCRAM); availability coupling is accepted: an OCI/tailnet outage degrades AudioMuse, not core Navidrome.
- Default Navidrome plugin URL for AudioMuse is `http://host.containers.internal:8000` (via the Podman host bridge interface).
- Operator bootstrap access to the AudioMuse web UI is over Tailscale to the host port (`<tailscale-ip>:8000`).
- Navidrome admin UI is already available over Tailscale (`<tailscale-ip>:4533` or the declared edge route if configured).

### Secrets contract

AudioMuse registers these SOPS-backed keys through `services.audiomuse.secretFiles.host` (consumed from the existing music application host secret file):

| Key                           | Purpose                                                     |
| ----------------------------- | ----------------------------------------------------------- |
| `audiomuse/user`              | AudioMuse admin username (wizard pre-fill)                  |
| `audiomuse/password`          | AudioMuse admin password (wizard pre-fill / first-run auth) |
| `audiomuse/api_token`         | API token shared with the Navidrome plugin                  |
| `audiomuse/jwt_secret`        | JWT signing secret for the AudioMuse API                    |
| `audiomuse/postgres_password` | Password for the `audiomuse` Postgres role                  |

Add these keys to the music application secrets file (`secrets/applications/music.yaml`) using the standard SOPS workflow. Do not manually decrypt or edit encrypted secret payloads.

Database-side ownership follows the database: home-forge runs the cluster that serves AudioMuse, so the role password lives in that host's own `secrets/applications/music.yaml` at `audiomuse/postgres_password` (same file as the keys above) and is read twice on that host — once by the cluster to provision the role, once by the AudioMuse container to authenticate (D-058). The former OCI-side copy in `secrets/services/postgres-shared.yaml` is retired.

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

Phase-1 ingress is implemented with the discovered `edge` aspect (`modules/edge/edge.nix` + `modules/edge/edge-ingress-application.nix`) over `modules/edge/edge-ingress-runtime.nix`.

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
