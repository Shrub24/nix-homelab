# Architecture

## Pattern Overview

**Overall:** Host-centric NixOS fleet infrastructure with modular service composition, provider-aware isolation, and blast-radius-secured secrets.

**Key Characteristics:**

- **Flake-driven:** Single `flake.nix` pins all inputs; flake-parts discovery reaches every host contributor under `modules/hosts/<host>/`, and the generic host registry (`modules/flake/host-registry.nix`) materializes their typed `nixos.hosts.<id>` records into `nixosConfigurations` per host
- **Aspect composition:** Source ownership and deployment variability are independent axes. Normal feature source files are auto-discovered flake-parts contributors under their domain directory (`modules/<domain>/`) or, for materialization and fleet-baseline concerns, `modules/flake/`; several may merge into one `flake.modules.nixos.<aspect>` deployment aspect — `identity-client` is composed from two such contributors. Host records select deployment aspects explicitly (selection is enablement) — the five foundation aspects `base`, `shell`, `networking`, `tailscale`, `notify`, the four operational aspects `state-backups`, `cache-publisher`, `builder-access`, `observability-agent`, the `dj`, `music`, and `identity-client` deployment aspects, and the eighteen placement aspects `oci`, `edge`, `cockpit`, `push-server`, `identity-provider`, `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, and `omniroute` (D-053, revised by D-054: `admin-hub` was removed and the former hub members are individual aspects), plus the fleet-level `internal-contracts` contract module selected by every host (D-056). `provenance`, `oci-images`, `fleet-packages`, and `web-policy` are infrastructure support modules, not host-facing capabilities
- **Hosts are thin:** Host contributors (`modules/hosts/<host>/default.nix`) declare one typed host record — target system, Tailscale identity, the explicit aspect selection, and reimage facts — while the NixOS composition itself stays host-private in `_nixos.nix` and underscore-prefixed fragments
- **Shared capabilities are consumer-registered:** a capability that serves unrelated services exposes a typed registry those services contribute to, instead of holding a participant list. `services.state-backups.services.<name>`, `services.notification-daemon.monitor.units.<unit>`, and the PostgreSQL consumer registry (`services.postgres.consumers.<name>`, D-058) are the three instances of the pattern. Two of them separate the mechanism from a declaration-only surface every participant imports — `state-backups` renders the capture job in `modules/backups/state-backups.nix` while `modules/backups/_consumer.nix` declares the registry and the capture settings, and PostgreSQL keeps the clusters in `modules/database/postgres.nix` with the declaration-only contract in `modules/database/postgres/_consumer.nix` — so a participant's registration evaluates on a host that does not run the mechanism. PostgreSQL additionally separates a host declares `services.postgres.instances.<name>` (port and data directory are host facts) and selects the `postgres` aspect, a consumer registers its database, credential, extensions, and setup SQL from its own module, and endpoint resolution prefers the host's own cluster (`services.postgres.localEndpoint`) before the internal contract
- **Applications compose services:** Discovered concern owners (`modules/<domain>/<concern>.nix` plus private `modules/<domain>/_<concern>/` leaves) wire multi-service stacks behind one host-selected `flake.modules.nixos.<aspect>` toggle; the legacy `modules/applications/` evaluator-class root was deleted in Stage 7 (D-053)
- **Services own their internals:** Leaf service modules own enabling runtime config, `sops.secrets`, `sops.templates`, systemd units, and assertions
- **Provider isolation:** Cloud/platform quirks live in the host-selected `oci` aspect (`modules/oci/oci.nix`, which carries the provider body inline) — workload modules stay provider-agnostic; the legacy `modules/providers/` root was deleted in Stage 7 (D-053)
- **Policy-driven:** Fleet-wide defaults and web-service endpoint definitions in `policy/` are the single source of truth
- **Secret blast-radius:** `.sops.yaml` path-scoped rules limit decryption to only the hosts that need each secret

## Layers

**Flake Entrypoint (`flake.nix` + `modules/flake/`):**

- Purpose: Pins all inputs and composes every flake output through flake-parts — host `nixosConfigurations`, devShell, packages, checks, deploy topology, and the `bootstrap.nodes` projection
- Location: `flake.nix` (minimal entrypoint), flake-parts modules under `modules/flake/`
- Contains: Input pins (`nixpkgs`, `disko`, `sops-nix`, `deploy-rs`, `niks3`, `flake-parts`, `import-tree`) and `denful/import-tree` discovery of `modules/` with the enumerated `filterNot` boundary (`modules/flake/_unconverted-nixos-dirs.nix`) now empty — every root under `modules/` is discovered (`core`/`profiles` left in Stage 2, `shared`/`storage` in Stage 5, `applications`/`providers` in Stage 7 D-053, `hosts` in Stage 8 after every host became a discovered contributor, `services` in the post-Stage-8 services-tree conversion). The boundary file stays as the inspectable, contract-tested list; an entry returns only when a genuinely transitional plain-module directory appears, and underscore-renaming whole roots is not completion
- Depends on: All submodules and library code
- Used by: `nix build`, `nixos-rebuild`, `deploy-rs`, CI workflows

**Host Layer (`modules/hosts/`):**

- Purpose: One typed canonical host record per host plus the host-private NixOS composition it selects
- Location: `modules/hosts/<host>/default.nix` — a discovered flake-parts contributor declaring `nixos.hosts.<id>` (HIC-1/HIC-2)
- Contains: `default.nix` (the record: `system`, `tailscale.{hostname,tailnetSuffix}`, `composition.{extraModules,aspects,fragments}`, and reimage `bootstrap` metadata where applicable, which projects to `flake.bootstrap.nodes.<host>`), the private `_nixos.nix` composition, underscore-prefixed host fragments (`_disko-*.nix`, `_cockpit-auth.nix`, `_admin-runtime.nix`), and `facter.json` (kept un-prefixed because its path is a host-derivation input)
- Depends on: Published aspects (`flake.modules.nixos.<aspect>`) selected by the record, input-provided NixOS modules (`extraModules`), and concern-owned feature sources (aspects and their sibling contributors)
- Used by: `modules/flake/host-registry.nix`, which validates every record (named `host-registry:` errors for duplicate host IDs, malformed IDs, ID/key mismatches, duplicate Tailscale identities, and missing required fields) and materializes `flake.nixosConfigurations` through `inputs.nixpkgs.lib.nixosSystem`; `modules/flake/registry.nix` projects `flake.bootstrap.nodes` from the same records

**Application Layer (former `modules/applications/`, deleted in dendritic Stage 7 / D-053):**

- Purpose: Composition roots that wire multiple interacting services behind one toggle; own shared paths and cross-service wiring, while concrete leaf mechanics live with their service owners
- Location: concern-owned contributors under their domain directory — `modules/music/music.nix` (dendritic Stage 6 / D-052) with the DJ contributor `modules/music/dj.nix` and its engine sibling `modules/music/dj-engine.nix`, `modules/identity/identity-provider.nix`, `modules/admin/cockpit.nix`, and the individual admin workload contributors `modules/admin/{termix,vaultwarden,homepage,gatus,beszel,webhook}.nix` (the former `admin/` coordinator split, dissolved by D-054), and `modules/edge/edge.nix` (former `edge-ingress.nix`). Stage 8 (D-056) moved these concern owners out of the flat `modules/flake/` bucket
- Contains: No `modules/applications/` root remains and no compatibility wrapper or underscore-renamed replacement root exists. Stacks whose mechanics belong to a service keep those leaves beside the concern owner (`paperless` has no application wrapper: the stack is composed directly from `modules/flake/paperless/{core,gpt}.nix`, and the music leaves live under `modules/music/**`)
- Depends on: Service modules, `policy/globals.nix`, `lib/secrets.nix`
- Used by: Host-record aspect selection only — hosts import no application implementation

**Service Leaf Layer (beside the owning concern):**

- Purpose: Leaf implementation modules for individual workloads — systemd services, Podman containers, runtime config
- Location: `modules/<domain>/<name>.nix` (a discovered aspect file or a sibling contributor of an existing aspect), with underscore-private helpers at `modules/<domain>/_<concern>/`
- Contains: Service enable flags, `sops.secrets` registrations, `sops.templates`, systemd units, assertions, restart semantics, multi-instance patterns (e.g., paperless-gpt with llm/docling OCR isolates)
- Depends on: `lib/secrets.nix`, runtime paths from the owning concern contributor
- Used by: flake-parts discovery, which publishes the file's own aspect, or the concern-owned contributor that imports it as a sibling; host records never import a workload service directly

**Deployment Aspect Layer (domain directories + `modules/flake/` for baseline and materialization):**

- Purpose: Cross-cutting host baseline published as selected deployment aspects — the five foundation aspects `base`, `shell`, `networking`, `tailscale`, `notify`, the four operational aspects `state-backups`, `cache-publisher`, `builder-access`, `observability-agent`, the `dj`, `music`, and `identity-client` deployment aspects, and the eighteen placement aspects `oci`, `edge`, `cockpit`, `push-server`, `identity-provider`, `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, `webhook`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, `omniroute` (D-053's placement surface, revised by D-054: `admin-hub` was removed with no replacement bundle and the former hub members are self-contained aspects). Selection is enablement: host registry records select the aspects they enable, selecting `dj` enables `applications.dj`, and selecting `identity-client` enables both of its contributors. Aspect relationships are modeled by semantics — intrinsic composition (the owner directly imports a required implementation with no meaningful independent placement), policy co-selection (independently placeable capabilities selected together by host policy, optionally with a named assertion), and optional integration (activates only when both contracts are present; neither selects the other) — rather than a universal no-aspect-import rule
- Location: concern-owned contributors discovered under their domain directory (Stage 8 / D-056 relocation) — foundation `modules/flake/{shell,networking,tailscale}.nix` and the two-contributor `base` (`modules/flake/base/{foundation,host-recovery}.nix`); notifications `modules/notifications/{notify,push-server}.nix`; operational `modules/backups/state-backups.nix` (with the declaration-only `modules/backups/_consumer.nix`), `modules/cache/cache-publisher.nix`, and `modules/flake/{builder-access,observability-agent}.nix`; application/identity `modules/music/{music,dj}.nix` and the two-contributor `identity-client` (`modules/identity/identity-oidc.nix` + `modules/identity/kanidm-host-auth.nix`); internal contracts `modules/fleet/internal-contracts.nix`; placement `modules/oci/oci.nix`, `modules/edge/edge.nix`, `modules/admin/{cockpit,termix,vaultwarden,homepage,gatus,beszel,webhook}.nix`, `modules/identity/identity-provider.nix`, `modules/cache/niks3-cache.nix`, `modules/database/postgres.nix`, and `modules/flake/{paperless,ai-gateway,karakeep,phoenix,omniroute}.nix`. A second contributor joins a concern by publishing the same aspect name from a sibling file (`modules/flake/base/host-recovery.nix`, `modules/cache/cache-publisher/{upload-client,post-deploy}.nix`, `modules/music/{dj-engine,windows-vm}.nix`, `modules/edge/edge-ingress-application.nix`); `_` is reserved for a value-imported helper, declaration-only contract, or data directory beside its owner (`modules/flake/shell/p10k.zsh`, `modules/music/_beets/runners.nix`, `modules/admin/homepage/_data.nix`, `modules/backups/_consumer.nix`)
- Contains: `base` (policy, users, host-recovery import, and the typed `fleet.foundation.bootLoader` / `fleet.foundation.buildTmpfsSize` host facts), `shell` (zsh/p10k, wezterm, nix-index comma), `networking` (native networkd contract rendered from `fleet.networking` facts), `tailscale` (auth-key secret registration and nullable `services.tailscale.debugMtu`), `notify` (notification-daemon enablement with withSystem-resolved packages), `state-backups`/`cache-publisher`/`builder-access`/`observability-agent` (operational capabilities, D-049; the combined `backups` aspect was split by D-055), `dj` (application enablement, D-050), `identity-client` (two discovered contributors nesting their own OIDC and host-auth/Kanidm bodies inline; D-051), and the Stage 7 and decoupling placement aspects — `oci` (provider boot/serial console), `edge` (edge/origin proxy plus the guarded policy projection), `cockpit`, `push-server` (LA ntfy), `identity-provider` (sole owner of Kanidm runtime/provisioning and the OIDC provisioning secret-source map), the individual admin workload aspects `termix`, `vaultwarden`, `homepage`, `gatus`, `beszel`, and `webhook` (each with its own enablement, runtime, and secret contracts), and the OCI/home-forge workloads `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, `omniroute` (D-053, revised by D-054). Aspect selection is independent: `la-admin-1` selects the capabilities it wants, no aspect owns or configures a sibling, and real cross-aspect dependencies fail through named contract assertions rather than missing-option errors. An aspect may import its own helper or sibling contributor — e.g. `modules/flake/tailscale.nix`, `modules/notifications/notify.nix`, `modules/flake/base/host-recovery.nix`, `modules/cache/cache-publisher/{upload-client,post-deploy}.nix`, `modules/music/dj-engine.nix`, `modules/edge/edge-ingress-application.nix`, and the OCI provider body nested in `modules/oci/oci.nix` — without creating a public dependency
- Depends on: Its own sibling contributors and underscore-private helpers under the same domain directory, plus `policy/`

**Infrastructure Support Modules (`modules/flake/{provenance,oci-images,fleet-packages,web-policy}.nix`):**

- Purpose: Typed repository data, package projections, provenance, and resolved web policy for lower-level consumers — infrastructure wiring, not host-facing deployment capabilities
- Location: concern-owned contributors under `modules/flake/`
- Contains: `provenance` (source provenance), `oci-images` (typed OCI image policy data), `fleet-packages` (per-system package projection), `web-policy` (resolved `repo.web` hosts/catalog/currentHost from `policy/web-services.nix`; selected on every host because the notification defaults and host policy consume it, D-051)
- Retirement: each support module disappears as its consumers migrate to native projections (feature-owned lexical capture, intrinsic registry/base composition, feature contributors injecting their own packages)

The former `modules/core/` and `modules/profiles/` directories were deleted in dendritic Stage 2 (`dendritic-stage-2-foundation-aspects`); their behavior became the foundation aspects above or the operational aspects and feature leaves selected in host records. Dendritic Stage 3 (`dendritic-stage-3-operational-aspects`) converted the five deferred operational leaves into the `backups`, `builder-access`, and `observability-agent` aspects (see `docs/decisions.md` D-049): `backups` composes state backups, the niks3 upload client, and post-deploy closure upload; `builder-access` owns only nixbuild.net SSH trust; `observability-agent` owns Beszel agent enrollment. Dendritic Stage 4 (`dendritic-stage-4-source-model-realignment`, D-050) replaced the central `modules/flake/aspects.nix` with concern-owned discovered contributors, classified `provenance`/`oci-images`/`fleet-packages` as infrastructure support, made `dj` selection enable `applications.dj`, and reframed plain class-oriented leaves and the filter as transitional (see `docs/decisions.md` D-050). Dendritic Stage 5 (`dendritic-stage-5-shared-source-contributors`, D-051) deleted the `shared`/`storage` roots, relocated the private leaves to `_aspects`/`_backups`/`_builder-access`, promoted `web-policy` to the all-host support quartet, merged the two identity contributors into `identity-client`, and shrank the filter from six entries to four. Dendritic Stage 7 (`dendritic-stage-7-placement-aspects`, D-053) converted every remaining deployed product/platform capability into a discovered placement aspect, relocated the admin/edge/DJ/OCI implementations beside their concern owners, deleted `modules/applications/` and `modules/providers/`, and shrank the filter to exactly `hosts` and `services`. Dendritic Stage 8 (`dendritic-stage-8-host-identity-contracts`, D-056) made host identity canonical and discovered: every host declares a typed `nixos.hosts.<id>` record from its own contributor, the concrete `nixos.configurations` table and the transitional loader were deleted, `modules/flake/registry.nix` was reduced to the `flake.bootstrap.nodes` projection, deploy and web metadata gained fail-closed canonical-host-ID validation, the tailnet suffix gained a single authority, the two internal transport contracts (`postgres`, `niks3Write`) were added under `modules/fleet/`, and the settled concern contributors moved into domain directories. The OCI cache server (`modules/cache/niks3-cache.nix`) is a leaf owned by the `niks3-cache` aspect. The post-Stage-8 services-tree conversion then converted the remaining service leaves into discovered contributors — each became its own aspect file, a sibling contributor of its owner aspect, or an underscore-private helper beside that owner — and emptied the import-tree exclusion.

**Provider Layer (former `modules/providers/`, deleted in dendritic Stage 7 / D-053):**

- Purpose: Isolate cloud/platform-specific hardware, kernel, and network defaults
- Location: the discovered `oci` aspect (`modules/oci/oci.nix`, provider body inline)
- Contains: OCI-specific safe defaults (GRUB device, `console=ttyAMA0` kernel parameter, `serial-getty@ttyAMA0`)
- Used by: Host registry aspect selection on `oci-melb-1` only; hosts import no provider implementation

- **Bifrost Gateway:** `modules/flake/ai-gateway.nix` — AI gateway service with OpenRouter and CrofAI provider support; exposes container-base URLs for LLM provider endpoints

**Storage Layer (host-local layouts):**

- Purpose: Declarative disk partitioning and filesystem layout via `disko`
- Location: host-local layouts only, beside their consumer under `modules/hosts/<host>/_disko-*.nix` (underscore-private since Stage 8 / D-056); the shared `modules/storage/` menu was removed in dendritic Stage 5 (D-051)
- Contains: `_disko-single-disk-split.nix` (split root/data/nix/media) on `modules/hosts/oci-melb-1/`, `_disko-two-disk.nix` on `modules/hosts/home-forge/`; LA is a preinstalled-NixOS adoption with no disko layout
- Depends on: `disko` flake input
- Used by: Host modules, `nixos-anywhere` bootstrap

**Policy Layer (`policy/`):**

- Purpose: Canonical fleet-wide non-secret defaults and web service endpoint definitions
- Location: `policy/`
- Contains: `globals.nix` (S3, Nix substituters, AI gateway, application defaults, and the single `tailnet.suffix` authority read by both the host records and the web policy), `web-services.nix` (SSOT for endpoint routing; plain data whose host-backed origins are validated against canonical host records), `identity.json`, `bifrost-config.json`
- Used by: All layers via `import ../../policy/globals.nix`

**Library Layer (`lib/`):**

- Purpose: Reusable Nix helpers for secrets, deploy wiring, and policy resolution
- Location: `lib/`
- Contains: `secrets.nix` (secret option helpers), `deploy/default.nix` (deploy-rs node wiring), `deploy/hosts.nix` (host metadata), `policy.nix` (web policy resolution and Cloudflare export)
- Used by: Concern-owned aspect contributors, service modules, `flake.nix`

**Secrets Layer (`secrets/`):**

- Purpose: SOPS-encrypted values scoped by blast radius with explicit `.sops.yaml` rules
- Location: `secrets/`
- Contains: Host-scoped (`secrets/hosts/<host>/system.yaml`, `oidc.yaml`), application-scoped (`secrets/applications/<name>.yaml`), service-scoped (`secrets/services/<name>.yaml`), fleet-shared (`secrets/common.yaml`), identity secrets, OpenTofu secrets, templates
- Depends on: `.sops.yaml` recipient policy, `sops-nix` activation-time decryption
- Used by: Host, application, and service modules

**Notification Layer (`modules/notifications/` + `pkgs/`):**

- Purpose: HTTP notification dispatch with dual-channel delivery (Telegram via apprise, UnifiedPush via ntfy), plus a `notify` CLI wrapper and a systemd service monitor
- Location: `modules/notifications/notify.nix` (the `notify` aspect, which carries the daemon body inline), `pkgs/notification-daemon/`, `pkgs/notify/
- Contains: `pkgs/notification-daemon/notification_api/main.py` (FastAPI app with `/health`, `/notify`, and `/debug/test-notify` endpoints), tier-to-topic mapping, dual-dispatch to apprise + ntfy; `pkgs/notify/default.nix` (CLI wrapper that POSTs to the daemon); `svc-monitor` Python script for automated systemd OnFailure/ExecStopPost notification hooks

**CI/CD Layer (`.github/workflows/` + `.github/actions/`):**

- Purpose: GitHub Actions automation for validation and deployment
- Location: `.github/workflows/`, `.github/actions/`
- Contains: `ci.yml` (lightweight automatic validation plus manual host remote-builds), `deploy.yml` (manual full deploy pipeline), `deploy-host.yml` (reusable host deploy), `actions/setup-nixbuild/` (composite action for nixbuild.net setup)
- Depends on: nixbuild.net, Tailscale GitHub Action for tailnet access
- Used by: Repository automation

## Data Flow

**Host Bootstrap Flow:**

Host initialization is conditional on target state — see `docs/runbooks/host-initialization.md`:

1. **Adoption** (existing preinstalled NixOS on a live disk): consume a committed `nixos-facter` report directly (`hardware.facter.reportPath`) with only root/ESP by-UUID mounts hand-maintained, then apply the first generation with `nixos-rebuild boot --target-host <initial-user>@<addr> --use-remote-sudo --flake .#<host>` and reboot from the provider console. No reimage tooling is involved.
2. **Reimage** (bare, foreign OS, or destructive layout): `just bootstrap` sources `scripts/resolve-host-config.sh`, which resolves the typed `flake.bootstrap.nodes.<host>` projection (bootstrap metadata owned by the host's `nixos.hosts.<id>` record; `hostName` and `flake` derived from the record key by `modules/flake/registry.nix`) and passes it to `deploy.sh`; `nixos-anywhere` runs over SSH with `--flake` target and `disko` partitioning — `deploy.sh`
3. Host installs with base config, no host-scoped secrets yet (two-step bootstrap default)
4. Post-install: retrieve SSH host key, derive age recipient via `ssh-to-age` — `just host-age <host>`
5. Add age recipient to `.sops.yaml`, re-encrypt host secrets, deploy — operator workflow

**Deployment Flow:**

1. Operator runs `just deploy <host>` — main `justfile`
2. `deploy-rs` reads host metadata from `lib/deploy/hosts.nix` — `lib/deploy/default.nix`; `modules/flake/deploy.nix` first validates every node key, `edgeHost`, and `deployOrder` entry against the declared canonical host IDs and fails closed with a named `deploy: unknown host reference …` error
3. `deploy-rs` builds the host profile and activates over SSH with rollback protection
4. Post-deploy hook sends `notify info` on success or `notify warning` on failure — `justfile` deploy recipe with inline notification
5. CI deploys follow same pattern with `--remote-build` and serial ordering (`la-admin-1` → `oci-melb-1`)

**Secret Resolution Flow:**

1. Host config binds secret file paths (e.g., `applications.music.secretFiles.host`)
2. Application/service module registers `sops.secrets` entries referencing that file
3. `sops-nix` decrypts at activation time — secrets are plaintext only during runtime
4. `sops.templates` render config files with secret placeholders replaced
5. `.sops.yaml` path-scoped rules control which age recipients can decrypt each file

**Web Service Routing Flow:**

1. `policy/web-services.nix` defines services with subdomain, origin, exposure mode (plain data; host-backed origin FQDNs are composed from canonical host IDs plus the single `policy/globals.nix` `tailnet.suffix` authority)
2. `modules/flake/web-policy.nix` validates the policy before resolution — unknown host keys and host-backed origins whose FQDN does not match a declared record's derived `tailscale.fqdn` fail closed with named `web-policy:` errors
3. `lib/policy.nix` resolves host services — `resolveHostServices` merges defaults
4. the discovered `edge` aspect (`modules/edge/edge.nix` + `modules/edge/edge-ingress-application.nix`) enables the Caddy reverse proxy with role-based configuration (edge/origin/none) — selected by `la-admin-1` (edge) and `oci-melb-1` (origin), with routes projected from this policy for the edge role only
5. `lib/policy.nix` exports Cloudflare DNS configuration via `resolveCloudflareHosts`
6. `scripts/export-web-services-policy.sh` generates JSON for OpenTofu consumption
7. OpenTofu manages Cloudflare DNS records and Access policies

**Media Ingest Flow:**

1. `slskd` downloads to `/srv/media/inbox/slskd`; each `DownloadDirectoryComplete` event restarts `slskd-settle.timer` (scoped polkit grant for the `slskd` user), which starts the pipeline 60s after the last event
2. `dropbox` path watcher (`systemd.paths.dropbox-inbox`, target declared via `pathConfig.Unit`) triggers on new files
3. `ffmpeg-preprocess.service` converts lossless to AIFF; timer persistence provides boot catch-up for unprocessed inbox media
4. `beets-inbox.service` imports preprocessed files into library
5. Completed files moved to `/srv/media/library`, quarantined files to `/srv/media/quarantine`
6. SoulSync provides control-plane ingest with Discogs-first metadata
7. Operator invokes `beets-quarantine-interactive` for manual quarantine review
8. Syncthing syncs library and quarantine to connected devices
9. Runner failures notify via `notify` CLI to the notification daemon — `beets-notify-failure@` systemd template unit

**Notification Dispatch Flow:**

1. Caller sends notification via `notify` CLI (`echo "msg" | notify <tier> <title> <type> <topic>`) or HTTP POST to `http://127.0.0.1:5555/notify`
2. Notification daemon dual-dispatches via apprise (Telegram with topic routing) AND ntfy (UnifiedPush with per-topic channels)
3. `svc-monitor` systemd oneshot unit injects OnFailure/ExecStopPost hooks — captures journal context and POSTs to notification daemon
4. Deploy notifications (`just deploy`) use `notify info/warning` inline in the justfile recipe

**Paperless Document Management Flow:**

1. `services.paperless.enable` toggles the Paperless document management stack
2. Paperless core (`modules/flake/paperless/core.nix`) runs the Django-based document management system with OIDC authentication via Kanidm
3. Paperless-GPT (`modules/flake/paperless/gpt.nix`) provides AI document enhancement with a docling-serve sidecar for OCR and document analysis (imported as a submodule of `services.paperless`; the host file configures it directly via `services.paperless.paperless-gpt` with per-instance enables (`instances.llm.enable`, `instances.docling.enable`) and the shared sidecar toggle (`docling.enable`))
4. Both services connect through the shared PostgreSQL mechanism (`modules/database/postgres.nix`, D-058) with niks3-managed backup
5. Post-consume hook triggers a notification via the notification daemon on new document ingestion

**Bifrost AI Gateway Flow:**

1. `services.bifrost-gateway.enable` toggles the Bifrost AI gateway
2. `modules/flake/ai-gateway.nix` manages the gateway with OpenRouter and CrofAI provider support
3. Provider endpoints are exposed via container-base URLs configured in `policy/bifrost-config.json`
4. API keys for Gemini, DeepSeek, CrofAI, and OpenRouter are encrypted in `secrets/services/bifrost-gateway.yaml`
5. Paperless-gpt instances use the bifrost endpoint for LLM OCR provider

## Key Abstractions

**Host Identity:**

- Purpose: Declares the canonical host record — stable host ID, target system, Tailscale identity, deferred NixOS composition, and reimage facts
- Location: `modules/hosts/<host>/default.nix` (the record) validated and materialized by `modules/flake/host-registry.nix`; physical deploy facts stay in `lib/deploy/hosts.nix`
- Pattern: One discovered contributor per host publishing `nixos.hosts.<id>`; identity is declared once and referenced (never restated) by deploy metadata and web policy, which both fail closed on unknown host IDs

**Internal Transport Contracts:**

- Purpose: Typed cross-host transport endpoints so consumers never restate a provider host name
- Location: `modules/fleet/internal-contracts.nix` (HIC-4)
- Pattern: Exactly two contracts — shared PostgreSQL and the private Niks3 write API — each declaring provider host ID, port, and the resolved private endpoint (`host`/`fqdn`/`url`) derived from the provider record; consumers read `config.repo.internal.*`. Named fail-closed checks: unknown provider, provider host that does not enable the required capability, and declared-port drift. Identity (Kanidm) and ntfy stay web-catalog contracts (`repo.web.catalog`)

**Application Stack:**

- Purpose: Multi-service feature composition with shared paths, secrets, and tmpfiles
- Location: `modules/<domain>/<concern>.nix`, publishing `flake.modules.nixos.<aspect>`, with a sibling contributor or underscore-private helper beside the owner under `modules/<domain>/`
- Pattern: Selection supplies the application's enable flag; the host keeps dataRoot + secretFiles passthrough only; the contributor imports sub-services, defines shared paths, and uses `lib.mkMerge` for conditional composition

**Edge Ingress Application:**

- Purpose: Host-level reverse proxy composition with role-based configuration
- Location: `modules/edge/edge.nix` (discovered aspect) + `modules/edge/edge-ingress-application.nix`
- Pattern: Selection supplies `applications."edge-ingress".enable`; the host keeps only `role` (edge/origin/none) and its application-scoped secret binding; the implementation imports `modules/edge/edge-ingress-runtime.nix`

**Paperless Service:**

- Purpose: Document management stack with Paperless core, OIDC auth, and optional AI enhancement
- Location: `modules/flake/paperless/core.nix` (imports the `gpt.nix` submodule)
- Pattern: Enable flag + dataRoot + two secret files (host/oidc); `services.paperless.paperless-gpt` configured directly by the host, with multi-instance enables (`instances.llm.enable`, `instances.docling.enable`) and a shared docling sidecar toggle (`docling.enable`); seeds Django groups for OIDC sync

**Bifrost Gateway Service:**

- Purpose: AI gateway service with OpenRouter and CrofAI provider support
- Location: `modules/flake/ai-gateway.nix`
- Pattern: Enable flag + dataRoot + encrypted API keys; exposes container-base URLs for LLM provider endpoints; uses `policy/bifrost-config.json` for configuration

**Service Module:**

- Purpose: Single workload with enable flag, runtime config, secrets, and systemd integration
- Location: `modules/<domain>/<name>.nix`
- Pattern: Options → config with `lib.mkIf`, explicit `secretFiles.*` contract inputs, `sops.secrets` ownership internal to the module

**Secrets Contract:**

- Purpose: Typed option inputs for secret file paths with required assertions
- Location: `lib/secrets.nix`
- Pattern: `mkSecretFileOption`, `mkSecretKeyOption`, `mkRequiredSecretAssertion`, `mkSecretsFromMap`

**Web Policy SSOT:**

- Purpose: Declarative endpoint definitions consumed by Caddy, Cloudflare, and OpenTofu
- Location: `policy/web-services.nix` (data), `modules/flake/web-policy.nix` (canonical-host validation + resolution into `repo.web`), `lib/policy.nix` (resolver)
- Pattern: Defaults + host service map → host-ID/FQDN validation against the canonical records → resolved by `lib/policy.nix` → exported as JSON for OpenTofu

**Disko Storage Layout:**

- Purpose: Declarative partition, filesystem, and mount point definitions
- Location: `modules/hosts/<host>/_disko-*.nix` (host-local, underscore-private)
- Pattern: `disko.devices.disk.main` with GPT layout, ext4 filesystems, labeled partitions

**Notify CLI:**

- Purpose: Python CLI wrapper that POSTs notification payloads to the daemon
- Location: `pkgs/notify/default.nix`
- Pattern: Reads stdin as message body, accepts positional args (tier, title, type, topic), POSTs to `NOTIFY_URL` (default `http://127.0.0.1:5555/notify`)

**Systemd Service Monitor:**

- Purpose: Automated notification hooks for systemd unit failures and lifecycle events
- Location: `modules/notifications/notify.nix` (inline `svc-monitor` script)
- Pattern: `OnFailure=svc-monitor@<unit>.service` + `ExecStartPost`/`ExecStopPost` hooks; captures journal context and dispatches to notification daemon

## Entry Points

**`flake.nix`:**

- Location: `flake.nix`
- Triggers: `nix build`, `nixos-rebuild`, `deploy-rs`, CI
- Responsibilities: Define all outputs — `nixosConfigurations`, `devShells`, `packages`, `deploy`, `checks`

**Host Contributor (`modules/hosts/<host>/default.nix`):**

- Location: `modules/hosts/oci-melb-1/default.nix`, `modules/hosts/la-admin-1/default.nix`, `modules/hosts/home-forge/default.nix`
- Triggers: `denful/import-tree` discovery, then materialization of the record into `flake.nixosConfigurations.<host>` by `modules/flake/host-registry.nix`
- Responsibilities: Declare the canonical record — target system, Tailscale identity, `composition.extraModules`/`.aspects`/`.fragments` (the explicit aspect selection), reimage `bootstrap` metadata, and host-private fragments; typed foundation facts and secret file bindings stay in the private `_nixos.nix` composition

**Bootstrap (`deploy.sh`):**

- Location: `deploy.sh`
- Triggers: `just bootstrap <host> <target>`
- Responsibilities: Read bootstrap config, derive age recipient, invoke `nixos-anywhere` with flake/disk config
- Adoption path: existing preinstalled NixOS hosts follow `docs/runbooks/host-initialization.md` (`nixos-rebuild boot`) instead of `deploy.sh`

**Deploy (root `justfile`):**

- Location: `deploy` recipe defined directly in the root `justfile` (the orphaned `.just/deploy.just` module was deleted)
- Triggers: `just deploy <host>`
- Responsibilities: Run `deploy-rs` with host profile, skip checks, optional auto-rollback, send `notify info/warning` on deploy outcome

**Notification Daemon (`pkgs/notification-daemon/`):**

- Location: `pkgs/notification-daemon/notification_api/main.py`
- Triggers: HTTP POST to `/notify` with JSON body (`tier`, `title`, `message`, `type`, `topic`); or `echo "msg" | notify <tier> <title> <type> <topic>` via CLI
- Responsibilities: Dual-dispatch notifications via apprise (Telegram with topic routing) AND ntfy (UnifiedPush with per-topic channels)

## Error Handling

**Strategy:** Fail closed at evaluation time — assertions (`lib.mkRequiredSecretAssertion`) prevent activation when required secret files are missing. `sops-nix` handles decryption failures at activation time. Systemd services use `Restart=on-failure` for runtime recovery. `deploy-rs` provides built-in rollback on activation failure. Pre-deploy checks (`just checks all`) run flake validation, secret scope checks, and web policy contract validation before any deployment.

## Cross-Cutting Concerns

**Logging:** NixOS `services.journald` with 300M max use, 7-day retention. Service-specific logging via `journalctl -u <unit>`. Notification daemon uses Python `logging` module.

**Caching:** Nix store optimization via `auto-optimise-store = true`. Substituters: `nixbuild.net` (priority 0), nix-community cachix, sovereign niks3 cache (`cache.shrublab.xyz`). CI uses nixbuild.net as the remote build plane.

**Storage:** Mutable service state on `/srv/data/<service>` mount (ext4, labeled `srv-data`). Media on `/srv/media` (ext4, labeled `srv-media`). Nix store on separate `/nix` partition on split-disk layouts. Disk layouts are host-local disko files beside their host. Backup via restic to per-host Cloudflare R2 buckets.

**Published provenance:** each host carries its own configuration at `/etc/nixos-source` (`modules/flake/provenance.nix`, `environment.etc."nixos-source".source = self.outPath`). Local evaluation uses the Git-tree form `.#`, so that copy is the tracked configuration set (~5.5 MB) rather than the raw working directory (440 MB, including VCS metadata, `.terraform` provider binaries, editor caches, and plaintext credential files), and `system.configurationRevision` is populated (`self.rev`/`self.dirtyRev`) instead of `null`. The Git index is therefore a precondition: `tests/check-flake-source-tracking.sh` fails when a jj-tracked file is missing from it, and index-mutating Git commands are not used in this colocated repository (D-057).

**Secrets:** All secrets encrypted with `sops` + `age`. Decrypted at activation time by `sops-nix`. Path-scoped `.sops.yaml` rules enforce blast-radius boundaries. No plaintext secrets in git.

**CI/CD:** GitHub Actions with nixbuild.net for cross-architecture builds (aarch64 from x86_64 runner). Tailscale `tailscale/github-action@v4` for tailnet access. Serial deploy ordering: `la-admin-1` → `oci-melb-1`. `--remote-build` for CI to avoid store-path transfer.

**Identity:** Kanidm-based OIDC provides single-sign-on for admin services. Kanidm is self-hosted on `la-admin-1`. OIDC client configurations are generated from `policy/identity.json`. Host-level SSH auth integrates with Kanidm groups.

**Notifications:** All hosts run the notification daemon, enabled by the `notify` foundation aspect (`services.notification-daemon.enable`). Deploy outcomes, beets runner failures, and monitored systemd service lifecycle events dispatch via the daemon. The `notify` CLI wrapper provides a stdin-pipe interface for any script to send notifications. The dispatch daemon and CLI are the extractable half: they hold no fleet identity, topic, or route literal, so a future `nix-fleet` copy needs only the typed policy inputs. Publisher membership, ntfy topic ACLs, and the ntfy auth-file binding are homelab policy and encrypted secrets — they stay in this repository (`modules/notifications/push-server.nix` policy, `modules/notifications/notify.nix` runtime, `secrets/services/ntfy*.yaml` readership).
