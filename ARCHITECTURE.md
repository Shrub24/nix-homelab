# Architecture

## Pattern Overview

**Overall:** Host-centric NixOS fleet infrastructure with modular service composition, provider-aware isolation, and blast-radius-secured secrets.

**Key Characteristics:**
- **Flake-driven:** Single `flake.nix` pins all inputs; `nixosConfigurations` defines each host
- **Hosts are thin:** Host modules (`hosts/<host>/default.nix`) only declare identity, feature enables, provider/storage/profile imports, and secret path bindings
- **Applications compose services:** Application modules (`modules/applications/<name>/`) wire multi-service stacks behind one operator-facing toggle
- **Services own their internals:** Leaf service modules own enabling runtime config, `sops.secrets`, `sops.templates`, systemd units, and assertions
- **Provider isolation:** Cloud/platform quirks live in `modules/providers/<name>/` — workload modules stay provider-agnostic
- **Policy-driven:** Fleet-wide defaults and web-service endpoint definitions in `policy/` are the single source of truth
- **Secret blast-radius:** `.sops.yaml` path-scoped rules limit decryption to only the hosts that need each secret

## Layers

**Flake Entrypoint (`flake.nix`):**
- Purpose: Pins all inputs and defines host nixosConfigurations, devShell, packages, and deploy topology
- Location: `flake.nix`
- Contains: Input pins (`nixpkgs`, `disko`, `sops-nix`, `deploy-rs`, `niks3`), host definitions, dev shell with admin tooling
- Depends on: All submodules and library code
- Used by: `nix build`, `nixos-rebuild`, `deploy-rs`, CI workflows

**Host Layer (`hosts/`):**
- Purpose: Thin host assembly — identity, facts, feature toggles, provider/storage/profile imports, secret bindings
- Location: `hosts/<host>/default.nix`
- Contains: `hardware-configuration.nix`, `bootstrap-config.nix`, host-specific component overlays (vary per host — e.g., `do-admin-1` has `cockpit-auth.nix`, `networking.nix`, `quantum.nix`, `edge.nix`)
- Depends on: Modules (applications, services, profiles, providers, storage, core, shared)
- Used by: `flake.nix` nixosConfigurations

**Application Layer (`modules/applications/`):**
- Purpose: Composition roots that wire multiple interacting services behind one toggle; own shared paths, ACLs, tmpfiles, and cross-service wiring
- Location: `modules/applications/<name>/`
- Contains: Named stacks — `music/`, `admin/`, `paperless/`, `edge-ingress.nix`
- Depends on: Service modules, `policy/globals.nix`, `lib/secrets.nix`
- Used by: Host modules

**Service Layer (`modules/services/`):**
- Purpose: Leaf implementation modules for individual workloads — systemd services, Podman containers, runtime config
- Location: `modules/services/<name>.nix` or `modules/services/<domain>/<name>.nix`
- Contains: Service enable flags, `sops.secrets` registrations, `sops.templates`, systemd units, assertions, restart semantics
- Depends on: `lib/secrets.nix`, runtime paths from application layer
- Used by: Application modules or directly by hosts

**Profile Layer (`modules/profiles/`):**
- Purpose: Lightweight host/persona baseline — core NixOS config, shell, recovery baseline, Tailscale, and backup defaults
- Location: `modules/profiles/base-server.nix`
- Contains: Base server profile importing `core/base.nix`, `shell-profile.nix`, `host-recovery.nix`, `tailscale`, `beszel-agent-auth`, `state-backups`
- Depends on: Core modules, shared modules
- Used by: Host modules (imported, no enable flags)

**Provider Layer (`modules/providers/`):**
- Purpose: Isolate cloud/platform-specific hardware, kernel, and network defaults
- Location: `modules/providers/<provider>/default.nix`
- Contains: OCI-specific and DigitalOcean-specific safe defaults
- Used by: Host modules

**Storage Layer (`modules/storage/`):**
- Purpose: Declarative disk partitioning and filesystem layout via `disko`
- Location: `modules/storage/disko-*.nix`
- Contains: `disko-root.nix` (root-only), `disko-single-disk.nix` (single partition), `disko-single-disk-split.nix` (split root/data/nix/media)
- Depends on: `disko` flake input
- Used by: Host modules, `nixos-anywhere` bootstrap

**Policy Layer (`policy/`):**
- Purpose: Canonical fleet-wide non-secret defaults and web service endpoint definitions
- Location: `policy/`
- Contains: `globals.nix` (S3, Nix substituters, AI gateway, application defaults), `web-services.nix` (SSOT for endpoint routing), `identity.json`, `bifrost-config.json`
- Used by: All layers via `import ../../policy/globals.nix`

**Library Layer (`lib/`):**
- Purpose: Reusable Nix helpers for secrets, deploy wiring, and policy resolution
- Location: `lib/`
- Contains: `secrets.nix` (secret option helpers), `deploy/default.nix` (deploy-rs node wiring), `deploy/hosts.nix` (host metadata), `policy.nix` (web policy resolution and Cloudflare export)
- Used by: Application modules, service modules, `flake.nix`

**Secrets Layer (`secrets/`):**
- Purpose: SOPS-encrypted values scoped by blast radius with explicit `.sops.yaml` rules
- Location: `secrets/`
- Contains: Host-scoped (`secrets/hosts/<host>/system.yaml`, `oidc.yaml`), application-scoped (`secrets/applications/<name>.yaml`), service-scoped (`secrets/services/<name>.yaml`), fleet-shared (`secrets/common.yaml`), identity secrets, OpenTofu secrets, templates
- Depends on: `.sops.yaml` recipient policy, `sops-nix` activation-time decryption
- Used by: Host, application, and service modules

**Notification Layer (`modules/services/notification-daemon/` + `pkgs/`):**
- Purpose: HTTP notification dispatch with dual-channel delivery (Telegram via apprise, UnifiedPush via ntfy), plus a `notify` CLI wrapper and a systemd service monitor
- Location: `modules/services/notification-daemon/default.nix`, `pkgs/notification-daemon/`, `pkgs/notify/`
- Contains: `pkgs/notification-daemon/notification_api/main.py` (FastAPI app with `/health`, `/notify`, and `/debug/test-notify` endpoints), tier-to-topic mapping, dual-dispatch to apprise + ntfy; `pkgs/notify/default.nix` (CLI wrapper that POSTs to the daemon); `svc-monitor` Python script for automated systemd OnFailure/ExecStopPost notification hooks
- Depends on: Python packages (apprise, fastapi, uvicorn), yq-go for ntfy config merge, SOPS-decrypted config at `/etc/notification-daemon/config.json`
- Used by: All hosts via `services.notification-daemon.enable` (deploy notifications, music ingest, systemd monitor)

**CI/CD Layer (`.github/workflows/` + `.github/actions/`):**
- Purpose: GitHub Actions automation for validation and deployment
- Location: `.github/workflows/`, `.github/actions/`
- Contains: `ci.yml` (PR validation), `deploy.yml` (push-to-main deploy pipeline), `deploy-host.yml` (reusable host deploy), `actions/setup-nixbuild/` (composite action for nixbuild.net setup)
- Depends on: nixbuild.net, Tailscale GitHub Action for tailnet access
- Used by: Repository automation

## Data Flow

**Host Bootstrap Flow:**

1. `deploy.sh` reads host config from `hosts/<host>/bootstrap-config.nix` — `scripts/resolve-host-config.sh`
2. `nixos-anywhere` runs over SSH with `--flake` target and `disko` partitioning — `deploy.sh`
3. Host installs with base config, no host-scoped secrets yet (two-step bootstrap default)
4. Post-install: retrieve SSH host key, derive age recipient via `ssh-to-age` — `just host-age <host>`
5. Add age recipient to `.sops.yaml`, re-encrypt host secrets, deploy — operator workflow

**Deployment Flow:**

1. Operator runs `just deploy <host>` — main `justfile`
2. `deploy-rs` reads host metadata from `lib/deploy/hosts.nix` — `lib/deploy/default.nix`
3. `deploy-rs` builds the host profile and activates over SSH with rollback protection
4. Post-deploy hook sends `notify info` on success or `notify warning` on failure — `justfile` deploy recipe with inline notification
5. CI deploys follow same pattern with `--remote-build` and serial ordering (`do-admin-1` → `oci-melb-1`)

**Secret Resolution Flow:**

1. Host config binds secret file paths (e.g., `applications.music.secretFiles.host`)
2. Application/service module registers `sops.secrets` entries referencing that file
3. `sops-nix` decrypts at activation time — secrets are plaintext only during runtime
4. `sops.templates` render config files with secret placeholders replaced
5. `.sops.yaml` path-scoped rules control which age recipients can decrypt each file

**Web Service Routing Flow:**

1. `policy/web-services.nix` defines services with subdomain, origin, exposure mode
2. `lib/policy.nix` resolves host services — `resolveHostServices` merges defaults
3. `applications/edge-ingress.nix` enables Caddy reverse proxy with role-based configuration (edge/origin/none) — imported by `do-admin-1`
4. `lib/policy.nix` exports Cloudflare DNS configuration via `resolveCloudflareHosts`
5. `scripts/export-web-services-policy.sh` generates JSON for OpenTofu consumption
6. OpenTofu manages Cloudflare DNS records and Access policies

**Media Ingest Flow:**

1. `slskd` downloads to `/srv/media/inbox/slskd`
2. `dropbox` path watcher (`systemd.paths.dropbox-inbox`) triggers on new files
3. `ffmpeg-preprocess.service` converts lossless to AIFF
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
2. Paperless core (`modules/services/paperless/`) runs the Django-based document management system with OIDC authentication via Kanidm
3. Paperless-GPT (`modules/services/paperless/paperless-gpt.nix`) provides AI document enhancement with a docling-serve sidecar for OCR and document analysis (imported as a submodule of `services.paperless`, gated by `services.paperless.enableAI`)
4. Both services connect through a shared PostgreSQL instance (`modules/services/postgres-shared.nix`) with niks3-managed backup
5. Post-consume hook triggers a notification via the notification daemon on new document ingestion

## Key Abstractions

**Host Identity:**
- Purpose: Declares host name, architecture, provider, and network identity
- Location: `hosts/<host>/default.nix`, `lib/deploy/hosts.nix`
- Pattern: Thin assembly; one file per host, one entry in deploy metadata

**Application Stack:**
- Purpose: Multi-service feature composition with shared paths, secrets, and tmpfiles
- Location: `modules/applications/<name>/default.nix`
- Pattern: Enable flag + dataRoot + secretFiles passthrough; imports sub-services, defines shared paths, uses `lib.mkMerge` for conditional composition

**Edge Ingress Application:**
- Purpose: Host-level reverse proxy composition with role-based configuration
- Location: `modules/applications/edge-ingress.nix`
- Pattern: Enable flag + role (edge/origin/none) + primaryDomain; imports `modules/services/edge-proxy-ingress.nix`

**Paperless Service:**
- Purpose: Document management stack with Paperless core, OIDC auth, and optional AI enhancement
- Location: `modules/services/paperless/default.nix` (imports `paperless-gpt.nix` submodule)
- Pattern: Enable flag + dataRoot + two secret files (host/oidc); `enableAI` toggle gates paperless-gpt/docling-serve; seeds Django groups for OIDC sync

**Service Module:**
- Purpose: Single workload with enable flag, runtime config, secrets, and systemd integration
- Location: `modules/services/<name>.nix` or `modules/services/<domain>/<name>.nix`
- Pattern: Options → config with `lib.mkIf`, explicit `secretFiles.*` contract inputs, `sops.secrets` ownership internal to the module

**Secrets Contract:**
- Purpose: Typed option inputs for secret file paths with required assertions
- Location: `lib/secrets.nix`
- Pattern: `mkSecretFileOption`, `mkSecretKeyOption`, `mkRequiredSecretAssertion`, `mkSimpleSecret`, `mkSecretsFromMap`

**Web Policy SSOT:**
- Purpose: Declarative endpoint definitions consumed by Caddy, Cloudflare, and OpenTofu
- Location: `policy/web-services.nix`, `lib/policy.nix`
- Pattern: Defaults + host service map → resolved by `lib/policy.nix` → exported as JSON for OpenTofu

**Disko Storage Layout:**
- Purpose: Declarative partition, filesystem, and mount point definitions
- Location: `modules/storage/disko-*.nix`
- Pattern: `disko.devices.disk.main` with GPT layout, ext4 filesystems, labeled partitions

**Notify CLI:**
- Purpose: Python CLI wrapper that POSTs notification payloads to the daemon
- Location: `pkgs/notify/default.nix`
- Pattern: Reads stdin as message body, accepts positional args (tier, title, type, topic), POSTs to `NOTIFY_URL` (default `http://127.0.0.1:5555/notify`)

**Systemd Service Monitor:**
- Purpose: Automated notification hooks for systemd unit failures and lifecycle events
- Location: `modules/services/notification-daemon/default.nix` (inline `svc-monitor` script)
- Pattern: `OnFailure=svc-monitor@<unit>.service` + `ExecStartPost`/`ExecStopPost` hooks; captures journal context and dispatches to notification daemon

## Entry Points

**`flake.nix`:**
- Location: `flake.nix`
- Triggers: `nix build`, `nixos-rebuild`, `deploy-rs`, CI
- Responsibilities: Define all outputs — `nixosConfigurations`, `devShells`, `packages`, `deploy`, `checks`

**Host Assembly (`hosts/<host>/default.nix`):**
- Location: `hosts/oci-melb-1/default.nix`, `hosts/do-admin-1/default.nix`
- Triggers: flake evaluation for a specific host
- Responsibilities: Import modules, set host identity, enable applications/services, bind secret files

**Bootstrap (`deploy.sh`):**
- Location: `deploy.sh`
- Triggers: `just bootstrap <host> <target>`
- Responsibilities: Read bootstrap config, derive age recipient, invoke `nixos-anywhere` with flake/disk config

**Deploy (`justfile` + `.just/deploy.just`):**
- Location: `justfile` with `mod deploy '.just/deploy.just'`
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

**Storage:** Mutable service state on `/srv/data/<service>` mount (ext4, labeled `srv-data`). Media on `/srv/media` (ext4, labeled `srv-media`). Nix store on separate `/nix` partition on split-disk layouts. Backup via restic to per-host Cloudflare R2 buckets.

**Secrets:** All secrets encrypted with `sops` + `age`. Decrypted at activation time by `sops-nix`. Path-scoped `.sops.yaml` rules enforce blast-radius boundaries. No plaintext secrets in git.

**CI/CD:** GitHub Actions with nixbuild.net for cross-architecture builds (aarch64 from x86_64 runner). Tailscale `tailscale/github-action@v4` for tailnet access. Serial deploy ordering: `do-admin-1` → `oci-melb-1`. `--remote-build` for CI to avoid store-path transfer.

**Identity:** Kanidm-based OIDC provides single-sign-on for admin services. Kanidm is self-hosted on `do-admin-1`. OIDC client configurations are generated from `policy/identity.json`. Host-level SSH auth integrates with Kanidm groups.

**Notifications:** All hosts run the notification daemon (`services.notification-daemon.enable`). Deploy outcomes, beets runner failures, and monitored systemd service lifecycle events dispatch via the daemon. The `notify` CLI wrapper provides a stdin-pipe interface for any script to send notifications.
