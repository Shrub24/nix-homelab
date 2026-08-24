# Design: windows-vm-engine-dj

## Context

`home-forge` has landed (fleet-standard profile, facter report, deploy node). The SC6000 sits on the same LAN as `home-forge`. Engine DJ Desktop (Windows-only, Qt6/OpenGL) serves Engine Remote Library to the SC6000 over same-L2 discovery; the library database is SQLite under `Music\Engine Library\Database2\m.db`, and upstream documents that external modification while running corrupts it. Community evidence shows Engine tolerates redirected library paths only via a local-path symlink to another volume, and "Relocate Missing Files" is broken in that mode. Future sync workers will use libdjinterop on Linux against the same database when the VM is down.

## Goals / Non-Goals

**Goals:**
- One reusable Windows VM layer (`windows-vm`) + first consumer (`applications/dj` engine-dj module)
- Library DB and music on plain ext4; guest sees them via virtiofs
- Kernel-mediated single-writer exclusion via systemd `Conflicts=`
- SPICE over Tailscale; same-L2 Remote Library discovery via the host-owned bridge

**Non-Goals:**
- GPU passthrough or waveform-grade graphics performance (library hosting + light GUI only)
- Declarative guest software installation (Windows/Engine/virtio-win installs are operator-driven)
- Sync worker implementation itself (follow-up change; this change provides the seam and the lock)
- Public exposure of any VM surface

## Decisions

**D1 — Consume the host-owned bridge, not macvtap/VFIO.**
Remote Library discovery needs same-L2 broadcast/multicast. The host already runs an always-on host-owned `br0` bridge over `eno1` (fleet networking aspect, parent D-043); the VM layer attaches guest NICs to that bridge, which gives the guest real LAN presence *and* keeps host↔guest traffic (SPICE, management) on the same link. The layer never creates or owns the bridge or its physical interface — a host without a declared `fleet.networking.bridge` is rejected at eval when instances are enabled. macvtap blocks host↔guest on that interface; VFIO wastes the NIC and adds IOMMU complexity with no benefit.

**D2 — Library DB on ext4 via virtiofs share, not NTFS image, not guest-local disk.**
libdjinterop workers need native filesystem access from Linux. An NTFS image would make the DB unreadable without mounting foreign filesystems; a guest-local qcow2 hides the DB from Linux entirely. virtiofs presents an ext4 directory as a guest drive letter (WinFsp-backed, behaves closer to local disk than SMB). Risk acknowledged in R1 with a defined fallback.

**D3 — Fixed symlink inside the guest.**
Engine requires path-stable libraries; mapped drives alone fail upstream. The guest gets a permanent drive letter for the library share and a one-time `mklink /D` from `Music\Engine Library`. Documented in the guest setup runbook, not automated by Nix.

**D4 — Mutual exclusion via systemd `Conflicts=` between the VM unit and future sync-worker units.**
No lockfiles, no libvirt hooks, no polling. Starting either side stops the other. Backup job gains the same `Conflicts=` so snapshots never race a writer.

**D5 — Music shared read-only from `/srv/media`; library share read-write but scoped to `/srv/data/engine-dj/library`.**
Two separate shares: media (ro) and library (rw). Blast radius of a guest compromise or bug is bounded to the library directory.

**D6 — SPICE over Tailscale, listening on loopback/host-only, reached via SSH tunnel or tailnet-bound socket.**
Validated path in community reports for Engine 5.x in a VM; avoids RDP's undocumented OpenGL behavior. Guest must keep an interactive session alive for Remote Library (autologon documented in runbook).

**D7 — Module layout mirrors fleet taxonomy.**
`modules/services/virtualisation/windows-vm.nix`: instance/share options, libvirtd, guest attachment to the host-owned bridge. `modules/applications/dj/default.nix` + `engine-dj.nix`: composition root wiring shares, locks, backup scope. Future Windows apps (Lexicon/rekordbox) add consumer modules, not new virtualization config.

## Risks / Trade-offs

- **[R1] SQLite-over-virtiofs locking unproven for Engine DJ** → Validation spike before production reliance (spec requirement). Fallback: guest-local qcow2 DB + copy-in/copy-out exchange during VM-stopped windows; Linux tooling preserved at cost of a copy step.
- **[R2] Engine 5.x fails to launch without proper guest GL** → virtio-win drivers mandatory in guest setup runbook; Mesa3D software-GL dll drop-in documented as fallback (slow but functional).
- **[R3] Remote Library has had a security advisory (fixed ≥ 4.3.4)** → Runbook pins minimum Engine version; bridge segment is home LAN behind the router, acceptance dialog gates connections.
- **[R4] GUI session required for Remote Library availability** → Autologon + SPICE keepalive documented; VM autostarts on host boot.
- **[R5] Path instability breaks track resolution irrecoverably (Relocate Missing Files broken)** → Drive letter and symlink fixed once in runbook; share definition changes flagged as breaking in module docs.

## Migration Plan

1. Land modules + host wiring with the application enabled on `home-forge`.
2. Operator creates the VM (install media out-of-band), runs the validation spike per spec.
3. Spike passes → connect SC6000, accept pairing, declare layout settled. Spike fails → switch to fallback layout (D2 fallback) before proceeding.
4. Rollback: disable the application toggle; host returns to prior generation with no residual state outside `/srv/data/engine-dj`.

## Open Questions

None blocking; sync-worker design (libdjinterop m3u→Engine) is deliberately deferred to a follow-up change.
