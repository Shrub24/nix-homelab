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
├── modules/             # Flake-parts modules + NixOS modules (flake composition, hosts, applications, services, providers, storage, shared, foundation-aspect leaves)
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

- Purpose: Flake-parts composition modules discovered by `denful/import-tree` from `flake.nix`
- Contains: `registry.nix` (typed `nixos.configurations.<host>` host registry materialized through `inputs.nixpkgs.lib.nixosSystem`, plus the `flake.bootstrap.nodes` projection), `aspects.nix` (published `flake.modules.nixos.<aspect>` cross-cutting modules — the five foundation aspects `base`, `shell`, `networking`, `tailscale`, `notify` plus the three operational aspects `backups`, `builder-access`, `observability-agent`), `_aspects/` (private foundation-aspect implementations: `base.nix`, `shell.nix` with `p10k.zsh`, `networking.nix`), `packages.nix`, `deploy.nix`, `dev.nix`, `dj.nix`, `scaffold.nix`, and `_unconverted-nixos-dirs.nix` (the temporary enumerated `filterNot` boundary for directories still holding plain NixOS leaves)
- Key files: `modules/flake/registry.nix`, `modules/flake/aspects.nix`, `modules/flake/_aspects/base.nix`, `modules/flake/_unconverted-nixos-dirs.nix`

The former `modules/core/` and `modules/profiles/` directories no longer exist: dendritic Stage 2 (`dendritic-stage-2-foundation-aspects`) converted their contents into the foundation aspects above (with typed `fleet.foundation` host facts), and dendritic Stage 3 (`dendritic-stage-3-operational-aspects`) converted the five deferred operational leaves into the `backups`, `builder-access`, and `observability-agent` aspects; no host imports the deleted wrappers or the five leaves directly.

**`modules/hosts/`:**

- Purpose: Per-host NixOS configuration entrypoints — thin assembly of modules, each registered as a `nixos.configurations.<host>` record in `modules/flake/registry.nix`
- Contains: `default.nix`, committed `facter.json` (`hardware.facter.reportPath`), host-specific overlays, and sole-consumer disko layouts beside their host; reimage bootstrap metadata lives inline in the host's registry record
- Key files: `modules/hosts/oci-melb-1/default.nix`, `modules/hosts/la-admin-1/default.nix`, `modules/hosts/home-forge/default.nix`

**`modules/applications/`:**

- Purpose: Composition roots for multi-service feature stacks
- Contains: Application modules with `enable` flags, sub-service wiring, shared paths, ACLs
- Key files: `modules/applications/music/default.nix`, `modules/applications/admin/default.nix`, `modules/applications/edge-ingress.nix`

**`modules/services/`:**

- Purpose: Leaf service implementation modules — individual workloads with enable flags and secrets
- Contains: Service configs for niks3, Tailscale, Bifrost, Karakeep, ntfy, notification-daemon, paperless (includes paperless-gpt submodule with multi-instance llm/docling OCR), postgres-shared, edge proxy, admin services (Cockpit, Kanidm, Vaultwarden, Quantum, Termix, Beszel, Gatus, Homepage, Webhook). Music-related services (Syncthing, Navidrome, Beets, slskd, Tagr, AudioMuse) live under `modules/services/music/`.
- Key files: `modules/services/tailscale.nix`, `modules/services/music/syncthing.nix`, `modules/services/music/navidrome.nix`, `modules/services/music/beets/default.nix`, `modules/services/music/slskd.nix`, `modules/services/music/tagr.nix`, `modules/services/music/audiomuse.nix`, `modules/services/ntfy.nix`, `modules/services/bifrost-gateway.nix`, `modules/services/paperless/default.nix`, `modules/services/paperless/paperless-gpt.nix`, `modules/services/postgres-shared.nix`, `modules/services/admin/cockpit.nix`
- **bifrost-gateway.nix**: AI gateway service with OpenRouter and CrofAI provider support

**`modules/services/notification-daemon/`:**

- Purpose: NixOS module for the notification dispatch daemon
- Contains: `default.nix` (service options, systemd unit, `svc-monitor` script, CLI wrappers)
- Key files: `default.nix`

**`pkgs/`:**

- Purpose: Custom Nix packages/derivations
- Contains: `default.nix` (package set aggregator), `_sources/` (nvfetcher output: `generated.nix`, `generated.json`), `notification-daemon/` (Python FastAPI daemon source, `pyproject.toml`, `default.nix`), `notify/` (CLI wrapper that POSTs to the daemon)
- Key files: `pkgs/default.nix`, `pkgs/_sources/generated.nix`, `pkgs/notification-daemon/default.nix`, `pkgs/notify/default.nix`

**`modules/providers/`:**

- Purpose: Cloud/platform-specific hardware and network defaults
- Contains: `oci/default.nix`
- Key files: `modules/providers/oci/default.nix`

**`modules/storage/`:**

- Purpose: Declarative disk partitioning via disko (shared layouts; sole-consumer layouts live beside their host under `modules/hosts/`)
- Contains: `disko-root.nix`, `disko-single-disk.nix`
- Key files: `modules/hosts/oci-melb-1/disko-single-disk-split.nix` (split root/data/nix/media layout), `modules/hosts/home-forge/disko-two-disk.nix`

**`modules/shared/`:**

- Purpose: Shared cross-cutting modules — host recovery, identity OIDC, Kanidm auth, niks3 post-deploy, conventional cache-upload client defaults, nixbuild SSH, web policy
- Key files: `modules/shared/host-recovery.nix`, `modules/shared/identity-oidc.nix`, `modules/shared/kanidm-host-auth.nix`, `modules/shared/niks3-post-deploy.nix`, `modules/shared/niks3-upload-client.nix`, `modules/shared/nixbuild-ssh.nix`, `modules/shared/web-policy.nix`

**`policy/`:**

- Purpose: Canonical source of truth for fleet-wide non-secret defaults and web service definitions
- Contains: `globals.nix` (S3, Nix substituters, AI gateway, music/admin/defaults), `web-services.nix` (SSOT endpoint routing), `oci-images.nix` (Renovate-managed OCI image refs, tag+digest), `identity.json` (Kanidm OIDC client config), `bifrost-config.json` (AI gateway model config)
- Key files: `policy/globals.nix`, `policy/web-services.nix`, `policy/oci-images.nix`

**`lib/`:**

- Purpose: Reusable Nix library functions
- Contains: `secrets.nix` (secret option helpers), `deploy/default.nix` (deploy-rs wiring), `deploy/hosts.nix` (host metadata), `policy.nix` (web policy resolution)
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

**Entry Points:** `flake.nix`: Minimal flake-parts entrypoint; outputs — `nixosConfigurations`, `devShells`, `packages`, `deploy`, `checks`, `bootstrap` — are composed by the flake-parts modules under `modules/flake/`

**Configuration:** `.sops.yaml`: SOPS recipient policy with path-scoped secret rules

**Host Definitions:** `modules/hosts/oci-melb-1/default.nix` (Oracle Cloud aarch64), `modules/hosts/la-admin-1/default.nix` (LA x86_64 admin/edge/identity): Thin host assembly modules registered in the typed host registry (`modules/flake/registry.nix`)

**Deploy Metadata:** `lib/deploy/hosts.nix`: Hostname, SSH user, system architecture, remote-build flag per host; `edgeHost` and `deployOrder` are the only physical deployment facts (serial order `la-admin-1` → `oci-melb-1`)

**Core Logic:** `modules/`: Flake-parts composition (`modules/flake/`), host assemblies (`modules/hosts/`), and all NixOS module code organized by application, service, provider, storage, and shared layer, plus the foundation-aspect leaves under `modules/flake/_aspects/`

**Policy SSOT:** `policy/web-services.nix`: All public web service endpoint definitions with origin, exposure mode, and Cloudflare config

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

**Host names:** `kebab-case`: `oci-melb-1`, `la-admin-1`

**Secret file names:** `kebab-case`: `system.yaml`, `oidc.yaml`, `edge-ingress.yaml`, `bifrost-gateway.yaml`

- Host secrets: `secrets/hosts/<host>/system.yaml`
- Host OIDC secrets: `secrets/hosts/<host>/oidc.yaml`
- Application secrets: `secrets/applications/<name>.yaml`
- Service secrets: `secrets/services/<name>.yaml`

## Where to Add New Code

**New host:** `modules/hosts/<host-name>/default.nix` — create thin assembly declaring identity, typed foundation facts (`fleet.foundation.bootLoader`, `fleet.foundation.buildTmpfsSize`), feature enables, and secret bindings. Add a `nixos.configurations.<host-name>` record in `modules/flake/registry.nix` that imports the five foundation aspects (`aspects.base`, `aspects.shell`, `aspects.networking`, `aspects.tailscale`, `aspects.notify`) plus the three operational aspects (`aspects.backups`, `aspects.builder-access`, `aspects.observability-agent`) and the host's feature leaves. Add entry to `lib/deploy/hosts.nix`. Add host-scoped `.sops.yaml` rules.

**New application stack:** `modules/applications/<name>/default.nix` — composition root with `enable` flag, shared paths, and sub-service wiring. Use `secretFiles.host` for secret passthrough.

**New edge ingress host:** `modules/applications/edge-ingress.nix` — role-based (edge/origin/none), imports `modules/services/edge-proxy-ingress.nix`.

**New paperless stack deployment:** `modules/hosts/<host>/default.nix` — set `services.paperless.enable = true` and bind `services.paperless.secretFiles.host` and `.oidc` to host-scoped secret files. Optionally enable paperless-gpt via `services.paperless.paperless-gpt = { docling.enable = true; instances.llm.enable = true; instances.docling.enable = true; }` for AI document enhancement with docling-serve sidecar. Ensure `services.postgres-shared.enable = true` on the target host.

**New service:** `modules/services/<name>.nix` (standalone) or `modules/services/<domain>/<name>.nix` (grouped) — leaf module with `enable` flag, `secretFiles.*` contracts, and `sops.secrets` ownership. Use `lib/secrets.nix` helpers.

**New foundation/operational aspect:** `modules/flake/aspects.nix` — publish a `flake.modules.nixos.<name>` record that imports its private implementation leaf under `modules/flake/_aspects/` (or a service/shared leaf). Host registry records select the aspect explicitly; selection is enablement and no aspect imports another aspect.

**New provider:** `modules/providers/<name>/default.nix` — provider-specific safe defaults. Import in relevant host's `default.nix`.

**New storage layout:** `modules/storage/disko-<name>.nix` for shared layouts; place sole-consumer host layouts beside the host (e.g., `modules/hosts/oci-melb-1/disko-single-disk-split.nix`). Add sizing options pattern from `disko-single-disk-split.nix`.

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
