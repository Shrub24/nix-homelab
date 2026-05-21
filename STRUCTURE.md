# Codebase Structure

## Directory Layout

```
dev-vps/
├── .github/         # CI/CD workflows and actions
├── docs/            # Human-facing architecture and planning docs
├── generated/       # Committed generated artifacts (e.g., web policy JSON)
├── hosts/           # Per-host NixOS configuration entrypoints
├── lib/             # Reusable Nix library functions
├── modules/         # NixOS modules (applications, services, profiles, providers, storage)
├── pkgs/            # Custom Nix packages/derivations
├── openspec/        # OpenSpec change management artifacts
├── opentofu/        # OpenTofu infrastructure-as-code (Cloudflare)
├── policy/          # Canonical fleet-wide defaults and web service policy
├── scripts/         # Operator-facing shell utilities
├── secrets/         # SOPS-encrypted secrets with blast-radius scoping
├── tests/           # Validation scripts and contract checks
├── certs/           # TLS certificate material
├── flake.nix        # Flake entrypoint: defines all outputs
├── flake.lock       # Pinned flake input revisions
├── .sops.yaml       # Central SOPS recipient policy with path-scoped rules
├── justfile         # Task runner for bootstrap, deploy, backups, secrets
├── deploy.sh        # nixos-anywhere bootstrap script
├── CONVENTIONS.md   # Module structure and naming conventions
├── ARCHITECTURE.md  # Architecture documentation (this file)
├── STRUCTURE.md     # Codebase structure documentation (this file)
└── README.md        # Project orientation
```

## Directory Purposes

**`hosts/`:**
- Purpose: Per-host NixOS configuration entrypoints — thin assembly of modules
- Contains: `default.nix`, `hardware-configuration.nix`, `bootstrap-config.nix`, host-specific overlays
- Key files: `hosts/oci-melb-1/default.nix`, `hosts/do-admin-1/default.nix`

**`modules/applications/`:**
- Purpose: Composition roots for multi-service feature stacks
- Contains: Application modules with `enable` flags, sub-service wiring, shared paths, ACLs
- Key files: `modules/applications/music/default.nix`, `modules/applications/admin/default.nix`, `modules/applications/edge-ingress.nix`

**`modules/services/`:**
- Purpose: Leaf service implementation modules — individual workloads with enable flags and secrets
- Contains: Service configs for niks3, Tailscale, Syncthing, Navidrome, Beets, SoulSync, slskd, Tagr, Bifrost, Karakeep, Postgres, notification-daemon, edge proxy, admin services
- Key files: `modules/services/tailscale.nix`, `modules/services/syncthing.nix`, `modules/services/navidrome.nix`, `modules/services/beets/default.nix`, `modules/services/bifrost-gateway.nix`, `modules/services/admin/cockpit.nix`

**`modules/services/notification-daemon/`:**
- Purpose: NixOS module for the notification dispatch daemon
- Contains: `default.nix` (service options, systemd unit, CLI wrappers, monitor)
- Key files: `default.nix`

**`pkgs/`:**
- Purpose: Custom Nix packages/derivations
- Contains: `notification-daemon/` (Python FastAPI daemon source, `pyproject.toml`, `default.nix`)
- Key files: `pkgs/notification-daemon/default.nix`, `pkgs/notify/default.nix`

**`modules/profiles/`:**
- Purpose: Host baseline profiles — common config imported by all hosts
- Contains: `base-server.nix` (core base + shell + recovery + tailscale + backups + host identity), `shell-profile.nix`, `p10k.zsh`
- Key files: `modules/profiles/base-server.nix`

**`modules/providers/`:**
- Purpose: Cloud/platform-specific hardware and network defaults
- Contains: `oci/default.nix`, `digitalocean/default.nix`
- Key files: `modules/providers/oci/default.nix`, `modules/providers/digitalocean/default.nix`

**`modules/storage/`:**
- Purpose: Declarative disk partitioning via disko
- Contains: `disko-root.nix`, `disko-single-disk.nix`, `disko-single-disk-split.nix`
- Key files: `modules/storage/disko-single-disk-split.nix` (split root/data/nix/media layout)

**`modules/core/`:**
- Purpose: Shared NixOS baseline policy — openssh, sudo, nix settings, users
- Contains: `base.nix` (ssh, sudo, grub, nix experimental features, timezone), `users.nix` (dev + root SSH keys)
- Key files: `modules/core/base.nix`, `modules/core/users.nix`

**`modules/shared/`:**
- Purpose: Shared cross-cutting modules — host recovery, identity OIDC, Kanidm auth, niks3 post-deploy, nixbuild SSH, web policy
- Key files: `modules/shared/host-recovery.nix`, `modules/shared/identity-oidc.nix`, `modules/shared/kanidm-host-auth.nix`

**`policy/`:**
- Purpose: Canonical source of truth for fleet-wide non-secret defaults and web service definitions
- Contains: `globals.nix` (S3, Nix substituters, AI gateway, music/admin defaults), `web-services.nix` (SSOT endpoint routing), `identity.json` (Kanidm OIDC client config), `bifrost-config.json` (AI gateway model config)
- Key files: `policy/globals.nix`, `policy/web-services.nix`

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
- Contains: `check-secret-scope.sh`, `check-web-services-policy.sh`, phase contract tests (`phase-*.sh`), `fixtures/`
- Key files: `tests/check-secret-scope.sh`, `tests/check-web-services-policy.sh`

**`opentofu/`:**
- Purpose: Infrastructure-as-code for Cloudflare DNS and Access
- Contains: `cloudflare/` directory with OpenTofu config and backend
- Key files: `opentofu/cloudflare/`

**`.github/workflows/`:**
- Purpose: CI/CD automation
- Contains: `ci.yml` (PR validation), `deploy.yml` (push-to-main deploy pipeline), `deploy-host.yml` (reusable host deploy)
- Key files: `.github/workflows/deploy.yml`, `.github/workflows/ci.yml`

## Key File Locations

**Entry Points:** `flake.nix`: Defines all flake outputs — `nixosConfigurations`, `devShells`, `packages`, `deploy`, `checks`

**Configuration:** `.sops.yaml`: SOPS recipient policy with path-scoped secret rules

**Host Definitions:** `hosts/oci-melb-1/default.nix` (Oracle Cloud aarch64) and `hosts/do-admin-1/default.nix` (DigitalOcean x86_64): Thin host assembly modules

**Deploy Metadata:** `lib/deploy/hosts.nix`: Hostname, SSH user, system architecture, remote-build flag per host

**Core Logic:** `modules/`: All NixOS module code organized by application, service, profile, provider, and storage layer

**Policy SSOT:** `policy/web-services.nix`: All public web service endpoint definitions with origin, exposure mode, and Cloudflare config

**Secrets Policy:** `.sops.yaml`: Path-scoped age recipient rules for encrypting/decrypting all secret files

**Task Runner:** `justfile`: All operator commands — bootstrap, deploy, SSH, logs, backups, secrets, checks, OpenTofu

**Bootstrap Script:** `deploy.sh`: nixos-anywhere bootstrap driver with host config resolution and age recipient derivation

## Naming Conventions

**Files:** `kebab-case.nix` for Nix files: `base-server.nix`, `disko-root.nix`, `edge-ingress.nix`, `kanidm-host-auth.nix`

**Directories:** `kebab-case` for module directories: `notification-daemon/`, `edge-ingress/`, `host-recovery/`

**Flake attributes:** `camelCase` for flake outputs: `nixosConfigurations`, `devShells`

**Nix options:** `dot.separated.namespaces`: `applications.music.enable`, `services.bifrost-gateway.enable`, `services.admin.kanidm.enable`
- `applications.<name>` for composition root stacks
- `services.<domain>.<name>` for grouped services
- `services.<name>` for top-level standalone services
- `fleet.<name>` for fleet-wide module options

**Host names:** `kebab-case`: `oci-melb-1`, `do-admin-1`

**Secret file names:** `kebab-case`: `system.yaml`, `oidc.yaml`, `edge-ingress.yaml`, `bifrost-gateway.yaml`
- Host secrets: `secrets/hosts/<host>/system.yaml`
- Host OIDC secrets: `secrets/hosts/<host>/oidc.yaml`
- Application secrets: `secrets/applications/<name>.yaml`
- Service secrets: `secrets/services/<name>.yaml`

## Where to Add New Code

**New host:** `hosts/<host-name>/default.nix` — create thin assembly importing profiles, providers, storage, and applications. Add entry to `lib/deploy/hosts.nix`. Add host-scoped `.sops.yaml` rules.

**New application stack:** `modules/applications/<name>/default.nix` — composition root with `enable` flag, shared paths, and sub-service wiring. Use `secretFiles.host` for secret passthrough.

**New service:** `modules/services/<name>.nix` (standalone) or `modules/services/<domain>/<name>.nix` (grouped) — leaf module with `enable` flag, `secretFiles.*` contracts, and `sops.secrets` ownership. Use `lib/secrets.nix` helpers.

**New profile:** `modules/profiles/<name>.nix` — add to `base-server.nix` imports if it should apply to all hosts.

**New provider:** `modules/providers/<name>/default.nix` — provider-specific safe defaults. Import in relevant host's `default.nix`.

**New storage layout:** `modules/storage/disko-<name>.nix` — disko disk/partition config. Add sizing options pattern from `disko-single-disk-split.nix`.

**New web service route:** `policy/web-services.nix` — add service entry under the relevant host's `services` attribute with subdomain, origin, exposure mode, and Cloudflare config.

**New secret file:** `secrets/<scope>/<name>.yaml` — add corresponding path-scoped rule in `.sops.yaml`. Encrypt with `sops`.

**New script:** `scripts/<name>.sh` — operator-facing utility. Add `just` recipe in `justfile`.

**New CI workflow:** `.github/workflows/<name>.yml` — add job with nixbuild setup and Tailscale connectivity.

**New test:** `tests/<name>.sh` — contract validation script with clear pass/fail output. Add to `just check` if it should run in CI.

**New custom package:** `pkgs/<name>/default.nix` — standard `callPackage`-compatible derivation with source alongside it. Add entry in `flake.nix` packages output via `pkgs.callPackage ./pkgs/<name> { }`.

**New notification daemon feature:** `pkgs/notification-daemon/notification_api/main.py` — add new handler or endpoint in the FastAPI app. Update `pkgs/notification-daemon/pyproject.toml` for new dependencies.

**Local dev workflow:**
1. Create a local config: `just devshell-setup` (decrypts to `/tmp/notification-daemon.json`)
2. Enter the devShell: `nix develop` (daemon auto-starts if config exists)
3. Use `notify` CLI directly: `echo "test" | notify info "test" test system`
4. Exit the devShell — daemon auto-stops via trap
