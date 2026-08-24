## Why

The fleet's only host, `oci-melb-1`, is an `aarch64` OCI cloud VM whose split-mount storage (`/`, `/nix`, `/srv/data`, `/srv/media` as separate filesystems) and cloud-provider bootstrap path were promoted to universal requirements in `fleet-infrastructure` and `bootstrap-storage`. A second host is now needed: `home-forge`, an `x86_64` HP Z2 G4 workstation (i7-8700, 32 GB DDR4, 1 TB NVMe, 1 TB HDD) managed locally over the LAN. Its accepted design — UEFI/systemd-boot, unencrypted disks, root-backed `/srv/data` + `/nix` as directories on the NVMe, and one ext4 `/srv/storage` mount on the HDD — does not fit the universal "separate `/srv/data` and `/srv/media` mounts" mandate, and it is a fresh destructive `nixos-anywhere`/`disko` install (not an adopted host, not a cloud-provider host). The storage requirement must be generalized so a locally-managed physical host can land without forcing cloud-shaped mounts or a speculative local-provider module.

## Core Value

Bring up `home-forge` as the first locally-managed, locally-deployed `x86_64` host with the minimum spec generalization needed — broaden the storage mandate so predictable root-backed paths and media-opt-in are first-class — while reusing every existing bootstrap, secrets, backup, recovery, and network contract rather than duplicating the active `normalize-fleet-boundaries` refactor.

## Constraints

- **Host/platform**: `home-forge`, x86_64 HP Z2 G4 (i7-8700, 32 GB DDR4, 1 TB NVMe + 1 TB HDD); fresh destructive install from a NixOS live ISO over LAN.
- **Boot**: UEFI + systemd-boot, Secure Boot off, unencrypted disks; no ZFS, no LUKS.
- **Storage**: NVMe = ESP + one ext4 root carrying `/nix` and `/srv/data` as directories; HDD = one ext4 filesystem mounted `/srv/storage`; stable `/dev/disk/by-id` inputs captured from the live installer.
- **Network**: Ethernet DHCP with router reservation; Tailscale `tag:homelab`; no public ingress. No edge role.
- **Scope**: baseline only — Tailscale, host-scoped backup, host-recovery baseline. No MCP/LiteLLM/music/paperless workloads; no app migration.
- **Deploy posture**: CI evaluates/builds `home-forge`; it is excluded from the serial cloud deployment chain. Deployments are local (`nixos-rebuild --target-host` over LAN).
- **Secrets**: two-step sops — base install converges without secrets; the age recipient is derived only from a persistent SSH host key verified at the local console. The agent MAY update `.sops.yaml` rules and secret templates/placeholders but SHALL NOT decrypt, manually edit ciphertext, encrypt, or deploy secrets.
- **Backup**: one host-scoped R2/restic backup contract for high-level/core system state; detailed workload paths across both drives are deferred.
- **No speculative provider module**: no `modules/providers/local` unless concrete hardware quirks require it.
- **Alignment**: must align with, not duplicate, the active `normalize-fleet-boundaries` change (topology SSOT, module-owned secret defaults, CI/topology contracts, generic non-OCI bootstrap safety).

## Relevant existing specs

- `fleet-infrastructure`, `bootstrap-storage` — storage model mandate (MODIFIED in this change).
- `secrets-management` — two-step bootstrap, host recipient derivation, path-scoped recipients, host-scoped backup credentials (covers home-forge; no delta).
- `network-access` — private-first access, Tailscale, firewall, break-glass via local console (covers home-forge; no delta).
- `host-recovery` — recovery baseline (home-forge opts in as a network-managed host; no delta).
- `state-backups` — host-scoped backup contract (home-forge instantiates; scope is per-host design, no delta).

## What Changes

- Generalize the storage mandate in `fleet-infrastructure` and `bootstrap-storage` so service-state locations may be dedicated mounts **or** root-backed directories, and a media location is required only when media workloads are enabled.
- Add `home-forge` as a thin host composing existing modules: a two-disk `disko` layout (ESP + ext4 root on NVMe, ext4 `/srv/storage` on HDD), systemd-boot, DHCP networking, `tag:homelab` Tailscale, `nixos-facter` facts captured from the live ISO or first boot, shared substitute/build-profile consumer, host-scoped R2/restic backups, and the recovery baseline.
- Add `home-forge` to physical topology metadata marked **non-deployable** (excluded from serial cloud deploy order) and to CI build/eval, consuming the `normalize-fleet-boundaries` topology-SSOT consistency contract.
- Add `home-forge` host secret scope and template placeholders (`.sops.yaml`, `secrets/.templates/hosts/system.yaml`); operator-only gate creates ciphertext and registers the verified age recipient.

## Capabilities

### New Capabilities

None — `home-forge` instantiates existing capabilities; no new capability surface.

### Modified Capabilities

- `fleet-infrastructure`: storage model generalized to predictable stable locations (mount or root-backed directory) with media opt-in.
- `bootstrap-storage`: service-state/media separation generalized to predictable locations (mount or root-backed directory) with media opt-in.

## Impact

- Affected specs: `fleet-infrastructure`, `bootstrap-storage` (MODIFIED requirements); `secrets-management`, `network-access`, `host-recovery`, `state-backups` referenced but unchanged.
- Affected code: `hosts/home-forge/` (new), `modules/storage/disko-two-disk.nix` (new), `lib/deploy/hosts.nix`, `flake.nix` (`nixosConfigurations.home-forge`), `.github/workflows/ci.yml`, `.sops.yaml`, `secrets/.templates/hosts/system.yaml`.
- Operator gates (not repo edits): boot live ISO, collect by-id/MAC/IP + facter facts, create the R2 bucket + restic repo, run the secret-free `nixos-anywhere` install, verify the newly persistent host key at the console + derive its age recipient, create ciphertext, run the step-2 local rebuild, and verify the baseline.
- No runtime behavior change to existing hosts; no secret values created or decrypted by the agent.
