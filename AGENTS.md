<!-- openspec:project-start source:PROJECT.md -->

## Project

**Modular NixOS Fleet Infrastructure**

This repository is the infrastructure source of truth for a modular NixOS homelab fleet. It is being repurposed from a legacy `dev-vps` setup into a host-centric, service-oriented repository that can reliably bootstrap and operate `oci-melb-1` first, then expand to additional hosts, providers, and architectures over time.

Canonical human-facing architecture and migration guidance lives under `docs/` (`docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/context-history.md`).

**Core Value:** Bring up and operate a clear, reproducible, low-complexity first NixOS host that establishes the right foundation for future fleet growth.

### Constraints

- **Platform**: First host is `oci-melb-1` on Oracle Cloud Free Tier using `aarch64-linux` - the initial solution must work on that concrete target.
- **Compatibility**: Fleet direction should support later mixed `aarch64` and `x86_64` hosts - provider-aware where needed, provider-agnostic where practical.
- **Security**: Secrets must be scoped by blast radius with explicit `.sops.yaml` rules - adding a host must not implicitly expose existing secrets.
- **Network**: Management and service access are private and Tailscale-first - public exposure is not part of the initial baseline.
- **Operations**: First-host bring-up should favor reliability, recoverability, and break-glass access over cleverness - early networking and secret bootstrap sharp edges must stay low.
- **Migration**: Legacy `dev-vps` assumptions and stale documentation should be removed or archived coherently - avoid long-lived dual-mission drift.
- **Storage**: The initial data model uses one persistent mount with predictable service subdirectories - avoid duplicate staging datasets early.
- **Complexity**: Native NixOS services and simple rollout flow come before orchestration tooling - only add higher-complexity systems when real pressure exists.
<!-- openspec:project-end -->

<!-- openspec:stack-start source:research/STACK.md -->

## Technology Stack

## Recommended Stack

### Core Technologies

| Technology       | Version                                            | Purpose                                      | Why Recommended                                                                                                                                                                           |
| ---------------- | -------------------------------------------------- | -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NixOS            | nixos-unstable (active baseline)                   | Base OS and package set                      | Active fleet code defaults to `nixos-unstable`; add stable fallback only as an explicit, documented exception when a concrete regression appears.                                         |
| Flakes           | Built into current Nix (`nix` 2.34.0 on nixos.org) | Reproducible repo entrypoint                 | A fleet repo should have one pinned lockfile, one set of inputs, and one canonical way to build hosts. Flakes are the standard way to do that in 2025-era Nix infra repos.                |
| `nixos-anywhere` | 1.13.0                                             | Remote bootstrap                             | This is the standard bootstrap tool for unattended remote installs. It already composes with `disko`, pushes your flake-defined config, and is purpose-built for SSH-driven installs.     |
| `disko`          | 1.13.0                                             | Declarative partitioning and filesystems     | It removes the last major manual install step. For a fleet repo, disk layout must live in code next to host config, not in a one-off runbook.                                             |
| `sops-nix`       | Pin flake input to a specific rev                  | Secret delivery at activation time           | This is the standard NixOS secret pattern when you want encrypted files in Git but plaintext only on the target during activation. It fits your blast-radius model cleanly.               |
| `sops` + `age`   | `sops` 3.12.2, `age` 1.3.1                         | Secret encryption backend                    | Use `age`, not GPG, for new host and admin recipients. It is simpler operationally, supports ARM builds, and matches the current Nix community default.                                   |
| `deploy-rs`      | Pin flake input to a specific rev                  | Multi-host deployment after day-0            | Use this once `oci-melb-1` is stable and you want repeatable host-targeted deploys with rollback protection. It is a better fit than heavier Nix fleet tooling for a small homelab fleet. |
| `nixos-facter`   | 0.4.3                                              | Hardware facts capture for cloud/host quirks | Use it for captured host facts instead of carrying hand-written hardware guesses. This matters more on cloud ARM/UEFI targets where boot assumptions are easy to get wrong.               |

### Supporting Libraries

| Library                            | Version                                             | Purpose                                          | When to Use                                                                                                                                       |
| ---------------------------------- | --------------------------------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| NixOS `services.tailscale`         | From active nixpkgs baseline                        | Private networking and admin access              | Enable on every host from day 0. Use tagged auth keys, MagicDNS, and Tailscale-only service exposure first.                                       |
| NixOS `services.syncthing`         | From active nixpkgs baseline / upstream 2.0.15 line | Bidirectional media sync                         | Use for the initial library authority model. Turn on folder versioning and explicit device/folder IDs before trusting it with important media.    |
| NixOS `services.navidrome`         | From active nixpkgs baseline / upstream 0.60.3 line | Music streaming service                          | Use after the Tailscale and storage baseline is stable. Point it directly at the Syncthing-managed music path; do not add an ingest pipeline yet. |
| NixOS `hardware.facter.reportPath` | In active nixpkgs baseline                          | Host fact import                                 | Use for `oci-melb-1` after first install so OCI/UEFI details are captured, not guessed.                                                           |
| `ssh-to-age`                       | Current nixpkgs package                             | Convert admin or host SSH keys to age recipients | Use when adding new machine recipients into `.sops.yaml` without introducing GPG.                                                                 |

### Development Tools

| Tool                          | Purpose                           | Notes                                                                                            |
| ----------------------------- | --------------------------------- | ------------------------------------------------------------------------------------------------ |
| `treefmt`                     | Format/repo-wide check for all languages | Runs `nixfmt`, `prettier`, `taplo`, `shfmt`, `tofu fmt` via `treefmt.toml`. Use `--fail-on-change` for CI. |
| `just fmt` / `just fmt-check` | Shortcut for `treefmt` / `treefmt --fail-on-change` | Same as above via `just` recipes. |
| `nix fmt`                     | Format Nix files only            | Stays as the dedicated Nix-only formatter backed by `nixfmt`. `treefmt` wraps it internally so both produce identical results on `.nix` files. |
| `nix flake check`             | Validate flake outputs and checks | Run locally and in CI before applying host changes.                                              |
| `deploy-rs` checks            | Deployment schema validation      | Wire `deploy-rs.lib.<system>.deployChecks` into `flake checks` once you introduce `deploy-rs`.   |
| `nixos-rebuild --target-host` | First-host iteration tool         | Use this before introducing fleet-wide deployment commands; it keeps the early workflow obvious. |

## Installation

# flake.nix inputs (recommended baseline)

# local admin environment

# remote bootstrap for OCI ARM: build or provide an aarch64 kexec/installer path

# then install from a temporary Linux image over SSH

## Alternatives Considered

| Recommended                   | Alternative                        | When to Use Alternative                                                                                                                                                                |
| ----------------------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nixos-anywhere`              | Prebaked OCI custom image pipeline | Use a custom image pipeline only after bootstrap is already boring and you want faster reprovisioning at scale. It is too much machinery for one first host.                           |
| `disko` with GPT + EFI + ext4 | ZFS/bcachefs/btrfs-first layouts   | Use a more advanced filesystem only after you have a concrete need for snapshots, replication, or checksummed subvolume workflows. First host should optimize for recovery simplicity. |
| `sops-nix` + `age`            | `agenix`                           | `agenix` is fine when you want age-only secrets and the simplest possible model. Use it only if you intentionally want to avoid `sops` file formats and templates.                     |
| `deploy-rs`                   | Colmena                            | Use Colmena only when you truly want a dedicated fleet deployment CLI and are comfortable with its slower release cadence. For this repo size, `deploy-rs` is the cleaner step up.     |
| Tailscale                     | Headscale                          | Use Headscale only if you explicitly need self-hosted control plane ownership. It is extra operational surface you do not need for a first private homelab host.                       |

## What NOT to Use

| Avoid                                      | Why                                                                                                                  | Use Instead                                                                                    |
| ------------------------------------------ | -------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `nixos-unstable` as the base branch        | It increases evaluation and package churn exactly when you need deterministic bootstrap and easy rollback.           | `nixos-25.11` for the fleet base; selectively override only where you have a real package gap. |
| Shared reusable Tailscale auth keys        | Tailscale explicitly warns reusable keys are dangerous if stolen. They also blur auditability across hosts.          | One host-scoped tagged auth key per machine, short expiry, stored in host-scoped secrets.      |
| GPG-first secrets for new hosts            | `sops-nix` itself warns GnuPG is operationally sharper on servers. It adds avoidable moving parts for a small fleet. | `age` recipients via admin keys and per-host keys or SSH-to-age conversion.                    |
| ZFS-on-day-1 on OCI Free Tier              | It adds memory, boot, and recovery complexity before you have proven workload pressure for it.                       | ext4 root plus one ext4 data filesystem managed by `disko`.                                    |
| Public ingress/reverse proxy baseline      | It expands the attack surface before the private network, secrets, and service posture are settled.                  | Tailscale-only access for Tailscale, Syncthing, and Navidrome first.                           |
| Full fleet orchestration on the first host | You will spend effort on tooling before validating the operating model.                                              | `nixos-rebuild --target-host` first, then introduce `deploy-rs` when the second host appears.  |

## Stack Patterns by Variant

- Use a temporary supported Linux image as the install source and run `nixos-anywhere` over SSH.
- Provide an `aarch64`-capable installer/kexec path; the upstream README only treats x86_64 kexec as the default and calls out custom images for other architectures.
- Assume UEFI and capture host facts after first boot with `nixos-facter`; do not hand-maintain guessed boot details.
- Use `nixos-rebuild --target-host` for post-install updates.
- Keep secrets bootstrap two-step: install base system first, then add the machine recipient and encrypted host secrets.
- Keep storage to GPT + EFI + `/` + one data mount, with Navidrome reading directly from the Syncthing path.
- Introduce `deploy-rs` and wire its checks into `flake check`.
- Keep `.sops.yaml` path-scoped by host so new machines do not inherit decryption access.
- Split host roles with modules/profiles, but keep provider quirks isolated under host or provider modules.

## Version Compatibility

| Package A                                            | Compatible With                             | Notes                                                                                                             |
| ---------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `nixpkgs@nixos-unstable`                             | Active host configs                         | Primary package baseline for active fleet code.                                                                   |
| `nixos-anywhere@1.13.0`                              | `disko@1.13.0+`, flake-based installs       | `nixos-anywhere` explicitly uses `disko` for partitioning during remote install.                                  |
| `sops-nix`                                           | `sops@3.12.2`, `age@1.3.1`                  | Use flakes and pin the input revision; `sops-nix` decrypts during activation, not evaluation.                     |
| `nixos-facter@0.4.3`                                 | active nixpkgs `hardware.facter.reportPath` | The old external `nixos-facter-modules` repo is deprecated because the module is upstreamed to nixpkgs.           |
| Tailscale / Syncthing / Navidrome on `aarch64-linux` | Oracle Ampere A1                            | All three upstreams publish current ARM64 builds, so OCI ARM is a first-class target rather than an afterthought. |

## Recommended First-Host Shape

- **Bootstrap:** Temporary OCI Ubuntu/Oracle Linux image -> `nixos-anywhere` over SSH -> `disko` applies GPT/EFI/root/data layout -> switch to NixOS.
- **Disk layout:** GPT, EFI system partition, ext4 root, one ext4 data filesystem mounted at a stable path such as `/srv/data` or `/persist/data`; use stable device IDs, not transient `/dev/sdX` names.
- **Secrets:** `sops-nix` with `age`; admin recipients in `secrets/common.*`, host recipients in `hosts/oci-melb-1/secrets.*`; add the host recipient after first boot unless you intentionally choose the sharper pre-generated-key path.
- **Deployments:** Start with `nixos-rebuild --target-host` for `oci-melb-1`; add `deploy-rs` when host count grows.
- **Private networking:** Tailscale on every host, tagged auth key per host, MagicDNS on, no public ingress, optional pre-approved key only if your tailnet uses device approval.
- **Service baseline:** Syncthing manages the library path directly, with versioning enabled on the receiving side; Navidrome reads that same path read-only over Tailscale.

## Sources

- <https://nixos.org/download/> - verified current stable lines: Nix 2.34.0 and NixOS 25.11.
- <https://raw.githubusercontent.com/nix-community/nixos-anywhere/main/README.md> - verified remote SSH install flow and non-x86 kexec caveat.
- <https://github.com/nix-community/nixos-anywhere/releases/tag/1.13.0> - verified current release line.
- <https://raw.githubusercontent.com/nix-community/disko/master/README.md> - verified declarative disk workflow and `disko-install` positioning.
- <https://github.com/nix-community/disko/releases/tag/v1.13.0> - verified current release line.
- <https://raw.githubusercontent.com/Mic92/sops-nix/master/README.md> - verified flakes recommendation, activation-time decryption, age support, SSH-to-age usage, and GPG caveats.
- <https://github.com/getsops/sops/releases/tag/v3.12.2> - verified current `sops` release line and ARM artifacts.
- <https://github.com/FiloSottile/age/releases/tag/v1.3.1> - verified current `age` release line and ARM artifacts.
- <https://raw.githubusercontent.com/serokell/deploy-rs/master/README.md> - verified deployment model, rollback behavior, and `deployChecks` workflow.
- <https://github.com/zhaofengli/colmena/releases/tag/v0.4.0> - verified latest tagged Colmena release is older, supporting a conservative `deploy-rs` recommendation.
- <https://github.com/nix-community/nixos-facter/releases/tag/v0.4.3> - verified current release line and UEFI-related fixes.
- <https://raw.githubusercontent.com/nix-community/nixos-facter-modules/main/README.md> - verified the old module repo is deprecated and upstreamed to nixpkgs.
- <https://tailscale.com/kb/1085/auth-keys> - verified tagged, ephemeral, reusable, and pre-approved auth key guidance.
- <https://github.com/tailscale/tailscale/releases/tag/v1.96.3> - verified current release line and upstream ARM support.
- <https://docs.syncthing.net/users/versioning.html> - verified that versioning is per-folder/per-device and applies to remotely received changes.
- <https://github.com/syncthing/syncthing/releases/tag/v2.0.15> - verified current release line.
- <https://raw.githubusercontent.com/syncthing/syncthing/main/README.md> - verified project goals and security/data-loss posture.
- <https://github.com/navidrome/navidrome/releases/tag/v0.60.3> - verified current release line.
<!-- openspec:stack-end -->

<!-- openspec:conventions-start source:CONVENTIONS.md -->

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.

NEVER TRY TO DECRYPT OR EDIT SECRETS MANUALLY ALWAYS LEAVE IT TO THE USER

<!-- openspec:conventions-end -->

<!-- openspec:architecture-start source:ARCHITECTURE.md -->

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.

<!-- openspec:architecture-end -->

<!-- openspec:workflow-start source:openspec defaults -->

## OpenSpec/OpenAgentsControl Workflow

This repository uses OpenSpec for planning/project state structure and OpenAgentsControl for agent flows.

For implementation work, use OpenSpec change workflows:

- Create changes with OpenSpec for planning and specification
- Use OpenAgentsControl for agent execution flows

Do not make direct repo edits outside established workflows unless the user explicitly asks to bypass them.

<!-- openspec:workflow-end -->
<!-- openspec:profile-end -->

## Code Search

Use `semble search` to find code by describing what it does or naming a symbol/identifier, instead of grep:

​`bash
semble search "authentication flow" ./my-project
semble search "save_pretrained" ./my-project
semble search "save model to disk" ./my-project --top-k 10
​`

Use `semble find-related` to discover code similar to a known location (pass `file_path` and `line` from a prior search result):

​`bash
semble find-related src/auth.py 42 ./my-project
​`

`path` defaults to the current directory when omitted; git URLs are accepted.

If `semble` is not on `$PATH`, use `uvx --from "semble[mcp]" semble` in its place.

## Formatting

Use `treefmt` for cross-language formatting (covers Nix, YAML, TOML, Markdown, shell, JSON, OpenTofu, Python).
Use `nix fmt` for Nix-only formatting (backed by `nixfmt`; `treefmt` wraps it internally so both produce identical results on `.nix` files).

- **Format all:** `treefmt`
- **Check only:** `treefmt --fail-on-change`
- **Nix only:** `nix fmt`

Exclusion SSOT lives in `treefmt.toml` — all managed paths (`secrets/**`, `generated/**`, `pkgs/_sources/generated.*`, `flake.lock`) are defined there.

## Jujutsu Workflow

This repo uses Jujutsu in colocated mode (shared `.git` object store).
All parallel work lives as **anonymous mutable changes** on top of `main@origin`.
A Git-facing bookmark is created only when a feature is ready to publish or open as a PR.

### Start new work

```sh
jj new main@origin          # empty change based on current upstream main
jj describe -m "feat: ..."  # local description, no branch
```

### Split a mixed change

Fileset-directed (non-interactive):

```sh
jj split -p -r @ -o main@origin -m "wip: deps" policy/oci-images.nix openspec/changes/nvfetcher-*
```

- `-p` — both parts become siblings (same parent), not parent/child
- `-o main@origin` — extracted change lands directly on main
- Remaining changes stay in `@`

Interactive (pick hunks):

```sh
jj split -p -i
```

### Rebase onto latest main

```sh
jj git fetch
jj rebase -b @ -o main@origin
```

If rebase hits immutable commits (previously pushed):

```sh
jj rebase --ignore-immutable -b @ -o main@origin
```

### Switch between anonymous changes

```sh
jj log -r 'main@origin.. & mutable()'   # list active changes
jj edit <change_id>                       # switch working copy
```

### Publish a completed change

```sh
jj bookmark set <name> -r @
jj git push -b <name>
```

After push, bookmarked commits become immutable. New work starts from `main@origin`.

### Gotchas

**Immutable commits:** `jj rebase` refuses to rewrite commits on the remote. Use `--ignore-immutable` when rebasing a local stack that includes previously-pushed commits.

**Snapshot warnings:** jj snapshots the working copy on every command. Large files (`.qmd/index.sqlite-wal`) trigger warnings. Fix with `.gitignore` or `jj config set --repo snapshot.max-new-file-size <bytes>`.

**Lockfile conflicts after rebase:** Restore from pre-rebase change: `jj restore --from <change-id> flake.lock`, then regenerate if needed.

**OpenSpec files and split:** OpenSpec change artifacts (`openspec/changes/*/`) must travel with the code they describe. Pass the OpenSpec directory as a fileset argument to `jj split`.

**No pre-commit hooks:** jj bypasses Git hooks. Run `treefmt --fail-on-change` and `nix flake check` manually or at push time.

## Workflow

1. Start with `semble search` to find relevant chunks.
2. Inspect full files only when the returned chunk is not enough context.
3. Optionally use `semble find-related` with a promising result's `file_path` and `line` to discover related implementations.
4. Use grep only when you need exhaustive literal matches or quick confirmation of an exact string.
