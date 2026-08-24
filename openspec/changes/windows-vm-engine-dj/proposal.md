# Proposal: windows-vm-engine-dj

## Why

The SC6000 needs an Engine DJ library authority that lives on Linux storage alongside the rest of the fleet's media state. Engine DJ Desktop is Windows/macOS-only, so the pragmatic path is a KVM/QEMU Windows VM on `home-forge` that serves Engine Remote Library to the SC6000 over the LAN while the underlying library database and music stay on plain ext4 — readable and writable by future Linux-side sync workers (libdjinterop, m3u→Engine, extending the Traktor sync pattern). `home-forge` has landed with the fleet-standard profile; this change stacks on top of it.

## What Changes

- Add a reusable Windows VM capability on `home-forge`: libvirtd/KVM with guest NICs attached to the host-owned always-on `br0` bridge (already provided by the fleet networking aspect over `eno1`), SPICE display reachable over Tailscale only, and virtiofs share plumbing. Designed so future Windows-only services (e.g., Lexicon/rekordbox USB export) reuse the same VM layer rather than spawning ad-hoc VMs.
- Add an Engine DJ application module as the first consumer: a dedicated virtiofs share exposing `/srv/data/engine-dj/library` (ext4) into the guest at a stable drive letter, with a fixed guest-side symlink (`Music\Engine Library`) because Engine's path model does not tolerate relocation.
- Enforce single-writer discipline between Linux workers and the guest via systemd `Conflicts=`: the Engine library directory is exclusively owned by the VM while it runs, and by Linux-side tooling (libdjinterop sync worker) while it is stopped.
- Keep the Engine SQLite database (`Database2/m.db`) on the shared ext4 directory so Linux workers can operate on it directly when the VM is down; music files remain ordinary Linux files under `/srv/media`, shared read-only into the guest.
- Scope backups: the library directory joins restic state-backups for `home-forge`; the VM system disk is treated as disposable/rebuildable.
- Guest software installation (Windows license activation, Engine DJ Desktop ≥ 4.3.4, virtio-win drivers) stays operator-driven inside the guest; Nix owns VM shape, shares, locks, and workers only.
- Remote GUI access is SPICE over Tailscale; no public exposure of any VM surface.

## Capabilities

### New Capabilities

- `windows-vm`: Reusable KVM/QEMU Windows VM layer — libvirtd enablement, guest attachment to the host-owned always-on bridge (consume-only; the layer never owns physical networking), Tailscale-only SPICE access, virtiofs share definitions, and per-instance options that additional Windows workloads can consume.
- `engine-dj-library`: Engine DJ library hosting on Linux storage — virtiofs-backed library share with stable guest paths, single-writer mutual exclusion between the guest VM and Linux sync tooling, backup scope, and the integration seam for future libdjinterop-based sync workers.

### Modified Capabilities

<!-- None: existing media-services requirements (Syncthing/Navidrome flows) are unchanged; Engine Remote Library is a new, separate consumer of Linux-hosted media. -->

## Impact

- **New modules:** `modules/services/virtualisation/windows-vm.nix`, `modules/applications/dj/` (composition root + engine-dj consumer).
- **Host wiring:** `hosts/home-forge/default.nix` enables the application.
- **Storage:** new `/srv/data/engine-dj/library` service-state directory; no disk-layout change.
- **Networking:** guests attach to the host-owned always-on `br0` bridge over `eno1` (fleet networking aspect); the VM layer adds no bridge or interface ownership; firewall rules scoped to the LAN segment plus loopback SPICE; no public ingress.
- **Dependencies:** nixpkgs libvirt/QEMU/SPICE from the active baseline (no new flake inputs expected); virtio-win ISO supplied out-of-band by the operator like other install media.
- **Risks carried into design:** SQLite-over-virtiofs tolerance is unproven upstream (validation spike required before committing the layout); Engine DJ's Qt6/OpenGL requirements make virtio-gpu driver installation mandatory in the guest; Remote Library discovery requires same-L2 presence, which constrains network mode choices.
