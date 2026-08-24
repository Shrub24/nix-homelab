## Context

The fleet's only host, `oci-melb-1`, is an `aarch64` OCI cloud VM. Its split-mount storage (`/`, `/nix`, `/srv/data`, `/srv/media` as separate filesystems) and cloud-provider bootstrap path were promoted to universal requirements in `fleet-infrastructure` and `bootstrap-storage`. `home-forge` is the second host: an `x86_64` HP Z2 G4 workstation on the LAN, locally managed. Its accepted design — systemd-boot, unencrypted disks, root-backed `/srv/data` + `/nix`, and one `/srv/storage` HDD mount — violates the universal mount mandate and is a fresh `nixos-anywhere`/`disko` install (not an adopted host). The storage requirement must be minimally generalized; every other need (private access, two-step secrets, host-scoped backups, recovery baseline, topology SSOT) is already covered by existing specs or the active `normalize-fleet-boundaries` change.

## Goals / Non-Goals

**Goals:**

- HFG-1: Generalize the storage mandate so predictable service-state locations may be mounts OR root-backed directories, with media opt-in.
- HFG-2: Add a two-disk `disko` layout (ESP + ext4 root on NVMe, ext4 `/srv/storage` on HDD) with stable `/dev/disk/by-id`; root-backed `/srv/data` and `/nix`.
- HFG-3: Boot via systemd-boot (UEFI, no `bios_grub`, Secure Boot off); capture hardware facts post-first-boot with `nixos-facter`.
- HFG-4: DHCP networking with router reservation; `tag:homelab` Tailscale; no public ingress; no edge role.
- HFG-5: Two-step sops bootstrap — base install without secrets, then age recipient derived from a console-verified persistent SSH host key.
- HFG-6: One host-scoped R2/restic backup contract for core/high-level state (workload paths deferred).
- HFG-7: Opt into the recovery baseline (console rescue operator + reboot exercise); physical console is primary break-glass.
- HFG-8: Add `home-forge` to topology metadata marked non-deployable + CI build/eval; local deploys via `nixos-rebuild --target-host`. Consume `normalize-fleet-boundaries`, do not duplicate.
- HFG-9: Thin host config; x86_64; shared unstable baseline + substitute/build-profile consumer; no provider module unless a concrete quirk requires it.

**Non-Goals:**

- App migration (MCP/LiteLLM/music/paperless) or any workload beyond baseline.
- A local provider module, role-to-host registry, or any abstraction not justified by a concrete second-host need.
- Touching secret values, decrypting, editing ciphertext, encrypting, or deploying secrets (operator-only).
- Duplicating `normalize-fleet-boundaries` (topology SSOT, module-owned secret defaults, CI contracts, generic non-OCI bootstrap safety).
- Changing `network-access`, `secrets-management`, `host-recovery`, or `state-backups` specs (already cover home-forge).

## Decisions

### HFG-1: Minimal storage-mandate generalization (MODIFY, two specs)

The universal "separate `/srv/data` and `/srv/media` mounts" mandate is the only spec barrier. Generalize it in both `fleet-infrastructure` ("Storage model separates service state and media") and `bootstrap-storage` ("Service-state and media mounts are separated"): predictable, stable, `/dev/disk/by-id`-backed locations, each of which MAY be a dedicated mount or a directory on the root filesystem, with a media location required only when media workloads are enabled. The change is strictly permissive — hosts with separate mounts (`oci-melb-1`) remain compliant; it only lifts the universal mandate. Requirement identity is preserved (MODIFIED bodies only); no new capability.

**Alternatives:** Force home-forge into split mounts — rejected; ample NVMe space and root-backed paths optimize recovery simplicity per STACK. Add a `/srv/storage` canonical path to the spec — rejected; `/srv/storage` is a host-declared bulk-storage location covered by the generalized "predictable stable path" principle, not a fleet-wide canonical path.

### HFG-2: Reusable two-disk disko module

Add `modules/storage/disko-two-disk.nix`: GPT, ESP (systemd-boot, `/boot`, `umask=0077`), ext4 root (100%) on `disk.main`; optional ext4 bulk-storage filesystem on `disk.storage` at a host-declared mountpoint (default `/srv/storage`). `/nix` and `/srv/data` are root-backed directories created via `systemd.tmpfiles` (the established pattern from the `reshape-oci-melb-1-storage` change), not partitions. No legacy `bios_grub` partition (UEFI-native, systemd-boot). Host sets `disk.main.device`, `disko-second-disk` (by-id), mountpoint, and sizes.

**Why:** Future physical fleet hosts likely share this shape; a thin host + reusable storage module matches the `oci-melb-1` pattern (host sets device/sizes, module defines layout). Simple enough to land now — not speculative.

**Alternatives:** Inline disko in `hosts/home-forge/` — rejected; would re-create the thin-host/storage-module split that already exists.

### HFG-3: systemd-boot + nixos-facter, no Secure Boot, no LUKS

`boot.loader.systemd-boot.enable`; ESP mounted `/boot` (reuse the disko ESP). Secure Boot off. No LUKS. Generate the facter report from the live ISO or first boot and wire `hardware.facter.reportPath`; do not hand-maintain a `hardware-configuration.nix` hardware guess.

**Why:** STACK recommends UEFI + facter capture and "ext4 root plus one ext4 data filesystem" over ZFS-on-day-1 for the first physical host; unencrypted ext4 optimizes recovery simplicity and is an accepted local-homelab trade-off.

### HFG-4: DHCP + Tailscale tag:homelab, private-only

Ethernet DHCP (router reservation for a stable address); `services.tailscale` with a host-scoped `tag:homelab` auth key; firewall trusts only declared interfaces; no public ingress, no edge role. Reuses `modules/services/tailscale` and the `network-access` contract unchanged.

### HFG-5: Two-step sops bootstrap, operator-verified recipient

Mirror the `oci-melb-1` `hasHostSecrets = builtins.pathExists ../../secrets/hosts/<host>/system.yaml` guard so the base install converges without secrets. The secret-free first boot generates the persistent OpenSSH host key on the installed root. Step 2: operator verifies that key at the physical console, derives the age recipient with `ssh-to-age`, replaces the `home-forge` placeholder recipient in `.sops.yaml`, then creates ciphertext and runs a second rebuild. The agent adds the scope rule + template placeholders only; it never decrypts, edits ciphertext, encrypts, or deploys.

### HFG-6: Host-scoped R2/restic backup, core scope

`services.state-backups` opt-in with a dedicated `home-forge` R2 bucket, `stagingRoot = /srv/data/state-backups`, and credentials in `secrets/hosts/home-forge/system.yaml`. Backup scope = high-level/core system state (config, host identity, recovery material); workload-specific paths across both drives are added only as workloads are introduced, not speculatively. Reuses `fleet-infrastructure` host-scoped backup wiring + `secrets-management` host-scoped backup-credential rules unchanged.

### HFG-7: Recovery baseline opt-in

`services.hostRecovery` opt-in (host-scoped rescue operator + recurring reboot exercise) with rescue material in the host system secret. The physical/supplier console is the primary break-glass path (covered by `network-access`); the rescue operator is defense-in-depth. No `host-recovery` spec change — home-forge qualifies as a network-managed host that opts into the existing baseline.

### HFG-8: Topology non-deployable + CI build, consume normalize

Add `home-forge` to `lib/deploy/hosts.nix` topology metadata marked non-deployable (excluded from `deployOrder`) and to `flake.nix` `nixosConfigurations.home-forge` (x86_64). CI evaluates/builds `home-forge` but does not place it in the serial cloud deploy chain. This consumes `normalize-fleet-boundaries`'s topology-SSOT consistency check ("a `nixosConfiguration` ... explicitly marked as non-deployable") — no competing requirement added.

### HFG-9: No provider module

`home-forge` is locally managed; it composes modules directly with no `modules/providers/local`. A local provider module is deferred unless a concrete hardware quirk (firmware, sensor, driver) requires isolation.

## Risks / Trade-offs

- [Destructive fresh install wipes both disks] → operator gate requires live-ISO by-id capture + explicit data-loss acknowledgment before `nixos-anywhere`.
- [Root-backed `/srv/data` fills root] → 1 TB NVMe, baseline-only workloads; document the trade-off; do not add a separate partition until pressure exists.
- [Two-step secrets delays Tailscale/backup/recovery activation] → `hasHostSecrets` guard is the existing pattern; operator runs step 2 promptly; services activate on the next rebuild.
- [Unencrypted disks] → accepted for local homelab per the change scope; physical security is the workstation's own posture; documented, not lazily removed.
- [Secure Boot off] → accepted homelab baseline; documented.
- [Excluded from serial deploy] → CI eval/build catches regressions; local deploys via `nixos-rebuild`; drift caught by `nix flake check`.
- [Two-disk module lands before a second physical host exists] → module is minimal and general; if a future host needs a different shape, refactor then.

## Migration Plan

1. **Spec generalization (HFG-1):** land MODIFIED storage requirements; `openspec validate --strict`.
2. **Repo implementation (HFG-2..HFG-9):** disko module, host config, topology/CI, secret policy/templates, backup, recovery — each gated by `nix flake check` / eval / secret-scope check.
3. **Operator gates (in order):** ISO boot + by-id/MAC/IP/facter capture → R2/restic repo → secret-free `nixos-anywhere` base install → console-verified persistent host key + age recipient → ciphertext → step-2 local rebuild → verification.
4. **Review gate:** confirm no app migration, no speculative provider module, no ciphertext touched by the agent, alignment with `normalize-fleet-boundaries`.

Rollback: pre-install, revert repo changes; post-install, revert to the previous generation (none for a fresh host) or re-provision.

## Open Questions

- Exact `home-forge` R2 bucket name and restic repository path are operator-supplied at the secret-material gate; the contract (host-scoped, core-state scope) is independent of the specific values.
