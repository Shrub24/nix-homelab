# Tasks: windows-vm-engine-dj

## 1. Windows VM layer

- [x] 1.1 Create `modules/services/virtualisation/windows-vm.nix`: libvirtd/KVM enablement, instance options (vcpu, memory, system disk, autostart), guest attachment to the host-owned always-on bridge (consume-only; asserts `fleet.networking.bridge` when instances are enabled), SPICE display bound to private/loopback access
  - refs: `specs/windows-vm/spec.md` (declarative instances, host-owned bridge attachment, private-only display)
- [x] 1.2 Add valid virtiofs share plumbing: named shares with mount tag, read-only enforcement, and libvirt shared-memory backing required by virtiofs
  - refs: `specs/windows-vm/spec.md` (virtiofs share plumbing)
  - notes: first live activation failed at `virsh define` with `unsupported configuration: 'virtiofs' requires shared memory`; fixed by conditional `<memoryBacking><source type="memfd"/><access mode="shared"/></memoryBacking>` emitted only for instances with shares; both XML variants pass `virt-xml-validate`
- [x] 1.3 Wire the module into the import graph (no namespace aggregator exists; the dj application imports it explicitly, matching the repo's explicit-import pattern)
  - refs: `docs/architecture.md`, user directive #335

## 2. Engine DJ application module

- [x] 2.1 Create `modules/applications/dj/default.nix` composition root with `applications.dj.enable`
- [x] 2.2 Create `modules/applications/dj/engine-dj.nix`: library share (`/srv/data/engine-dj/library`, rw) and read-only media share wiring against the VM instance
  - refs: `specs/engine-dj-library/spec.md` (stable mapping, read-only music)
- [x] 2.3 Implement single-writer exclusion: systemd `Conflicts=` between the VM unit and the sync-worker target placeholder, and between the backup job and both writers
  - refs: `specs/engine-dj-library/spec.md` (mutual exclusion, backup scope)
- [x] 2.4 Add `/srv/data/engine-dj/library` to home-forge state-backups scope
  - refs: `specs/engine-dj-library/spec.md` (backup scope)

## 3. Host wiring

- [x] 3.1 Enable `applications.dj` in `hosts/home-forge/default.nix`
  - depends: home-forge host shell (landed)

## 4. Validation spike (operator-assisted)

- [x] 4.1 Write guest setup runbook: Windows install, virtio-win drivers (mandatory GL note), fixed drive letter + one-time `mklink /D`, autologon, Engine DJ ≥ 4.3.4 pin
  - refs: design D3/D6/R2/R4
- [ ] 4.2 Execute validation pass: guest boot, Engine launch on shared library, track import, SC6000 Remote Library connect over bridge, DB integrity across guest reboot
  - notes: installer-mode staging errors when an argument already equals its destination path in installDir (`install: ... are the same file`); patch the stage step to no-op on identical paths before closing this change
  - refs: `specs/engine-dj-library/spec.md` (validation gate)
  - notes: before retrying, clear the stale lone `install.iso` or stage both install and nixpkgs-provided `virtio-win.iso` through the explicit install command; the half-staged state correctly failed closed
- [ ] 4.3 If spike fails, switch to fallback layout (guest-local qcow2 DB + copy-in/copy-out during VM-stopped windows) and update design/spec deltas accordingly
  - refs: design R1 fallback

## 5. Verification

- [x] 5.1 `nix flake check` passes with modules enabled on home-forge evaluation
  - notes: all three hosts' toplevels evaluate clean; domain XML validates against the libvirt RNG schema (`virt-xml-validate`). Full `nix flake check` build phase is blocked locally by the aarch64 host (no local ARM builder — pre-existing; CI builds via nixbuild).
- [ ] 5.2 Confirm read-only enforcement of media share from a guest session
- [ ] 5.3 Confirm conflict semantics: starting worker stops VM and vice versa; backup never overlaps a writer
- [x] 5.4 Update `docs/architecture.md` / `docs/decisions.md` with the VM layer and Engine library decisions
