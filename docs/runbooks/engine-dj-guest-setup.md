# Engine DJ Guest Setup Runbook

Operator procedure for bootstrapping and validating the Windows guest that hosts Engine DJ Desktop on `home-forge`. Nix owns the VM shape, shares, locks, and backup contract (`modules/services/virtualisation/windows-vm.nix`, `modules/applications/dj/`); everything here happens at the operator console, over SSH/Tailscale, or inside the guest.

Phases:

1. **Wire + deploy** — land the VM layer on the host-owned `br0` bridge
2. **Install** — Windows + virtio drivers inside the guest
3. **Map shares** — one-time library path pinning
4. **Engine DJ + SC6000** — application setup and pairing
5. **Validate** — the gate before relying on the layout

## 1. Wire the config and deploy

No install-specific configuration exists: the install lifecycle runs through the `windows-vm-windows-dj-install` command (staged media + unit restart in, `--clear` out). Config never changes for installation.

In `hosts/home-forge/default.nix`, extend the application block:

```nix
applications.dj = {
  enable = true;
  engine.enable = true;
};
```

Deploy from a clean jj change (`just deploy home-forge`).

**No bridge cutover here:** the `br0` bridge over `eno1` is host-owned always-on topology provided by the fleet networking aspect (`fleet.networking.bridge`), independent of this application. This deploy only attaches the guest NIC to the existing bridge; it does not move interfaces or change host networking. If the bridge is ever missing, eval fails with a consume-only assertion on `services.windows-vm` rather than this module silently re-creating networking.

Post-deploy verification on the host:

```sh
ip -br addr                 # br0 carries the LAN IP; eno1 has none
bridge link                 # eno1 state UP enslaved to br0
systemctl status windows-vm-setup windows-vm-windows-dj
virsh list --all            # windows-dj defined and running
ls -la /srv/data/engine-dj/library /srv/storage/music   # share roots exist
```

The VM idles at the UEFI "no bootable device" screen until install media is staged (next step) — harmless.

## 2. Stage install media and boot the installer

Two ISOs are needed:

- Windows installer; public download from microsoft.com/software-download (or Fido for a direct link); license supplied out-of-band
- virtio-win driver CD, **required**: setup cannot see the virtio system disk until `viostor` is loaded from it. Build it hash-pinned on the workstation from nixpkgs: `nix build nixpkgs#virtio-win.src`

```sh
nix build nixpkgs#virtio-win.src
scp windows11.iso result/virtio-win.iso dev@home-forge:/tmp/
ssh dev@home-forge -- windows-vm-windows-dj-install /tmp/windows11.iso /tmp/virtio-win.iso
```

The command stages both into `/srv/data/windows-vm/windows-dj/`, redefines the domain in installer mode (CD-ROM-first boot), and starts it. Windows 11 only: set `tpm = true` on the instance in `hosts/home-forge/default.nix` and redeploy before this step (emulated TPM 2.0 via swtpm).

Connect to SPICE from any tailnet device:

```sh
ssh -N -L 5900:127.0.0.1:5900 dev@home-forge &
remote-viewer spice://127.0.0.1:5900    # or virt-viewer
```

1. Run Windows setup. At disk selection the disk list is empty — click **Load driver**, browse the virtio-win CD, and install `viostor` (storage) for your Windows version. Add `NetKVM` (network) the same way if you want network during setup.
2. Complete installation and activate with the supplied license.
3. Secure Boot is not emulated by this domain's firmware; if Windows 11 setup refuses, use an installation image with the check relaxed or fall back to Windows 10.
4. Inside the guest, run `virtio-win-guest-tools.exe` from the virtio-win CD. This installs the virtio-fs/WinFsp stack (shares), SPICE agent, and guest agent — mandatory for everything below.
5. Leave installer mode:

   ```sh
   ssh dev@home-forge -- windows-vm-windows-dj-install --clear
   ```

Reinstalling later is the same flow: run the install command again, then `--clear` afterwards.

## 3. Map the library share (do this exactly once)

Shares appear as drives after the guest tools are installed and the guest reboots: mount tag `library` (read-write) and tag `media` (read-only).

1. Note the drive letters; pin them if needed so they never change.
2. Create the Engine library symlink once, from an elevated prompt:

   ```bat
   mklink /D "%USERPROFILE%\Music\Engine Library" "L:\"
   ```

   where `L:` is the library drive. Engine's path model does not tolerate relocation ("Relocate Missing Files" is broken under redirected paths), so this path must never change. Changing the share tag or drive letter invalidates every recorded track path.

## 4. Engine DJ Desktop and the SC6000

- Install Engine DJ Desktop **≥ 4.3.4** (Remote Library security fix); current line is 5.x.
- Configure Windows autologon — Remote Library requires a live interactive desktop session.
- If waveform/UI rendering is unusable under virtio-gpu, drop Mesa3D's `opengl32.dll` into the Engine install dir renamed to `opengl32sw.dll` (software GL fallback; slower but functional).
- SC6000 pairing: both devices share the LAN through `br0` (same L2). On the SC6000: Source → Engine DJ Desktop section → select the computer. Accept the pairing dialog inside Engine Desktop at the SPICE console (first connection needs someone present).
- Tracks stream from the VM; cues/grids sync bidirectionally in real time.

## 5. Validation gate

Run every check below before treating the layout as settled. Upstream does not document Engine-on-virtiofs; corruption found here triggers the design R1 fallback (guest-local DB + copy-in/copy-out during VM-stopped windows).

| #   | Check                                         | Pass criteria                               |
| --- | --------------------------------------------- | ------------------------------------------- |
| V1  | Engine launches against the shared library    | No errors; library opens                    |
| V2  | Import tracks from the media share            | Tracks import, analyze, play                |
| V3  | SC6000 Remote Library connect                 | Player sees the VM source; track loads      |
| V4  | Clean guest shutdown, host-side DB inspection | Files readable; SQLite integrity ok (below) |
| V5  | Guest reboot                                  | Tracks resolve; SC6000 reconnects           |
| V6  | Read-only media enforcement                   | Guest writes to the media drive fail        |
| V7  | Backup quiesce                                | Backup stops the VM, runs, restarts it      |
| V8  | Writer conflict semantics                     | Starting either side stops the other        |

V4 — after shutting down the guest cleanly:

```sh
sqlite3 /srv/data/engine-dj/library/Database2/m.db 'PRAGMA integrity_check;'
# expect: ok
```

V6 — inside the guest, attempt to create a file on the media drive; it must fail.

V7 — with the VM running:

```sh
sudo systemctl start restic-backups-state
# during the run: virsh domstate windows-dj -> "shut off"
# after the run: virsh domstate windows-dj -> "running"
```

V8 — conflict direction checks:

```sh
sudo systemctl start dj-library-writers.target   # VM unit deactivates, guest shuts down
sudo systemctl start windows-vm-windows-dj       # target deactivates before guest starts
```

Record results. Any database corruption or locking misbehavior: stop, do not retry against the same data, and switch to the fallback layout per design R1 before proceeding.

## Single-writer discipline reference

The library directory (`/srv/data/engine-dj/library`) alternates ownership:

| Writer                                   | Mechanism                                                             |
| ---------------------------------------- | --------------------------------------------------------------------- |
| VM (Engine DJ)                           | runs while `windows-vm-windows-dj.service` is active                  |
| Linux workers (future libdjinterop sync) | bind to `dj-library-writers.target`, which conflicts with the VM unit |
| restic state backup                      | quiesce hook stops the VM only if running, restarts it afterwards     |

Never edit files under the library directory while the VM is running.

VM config changes (memory, shares, SPICE port) are redefined at deploy time and apply at the guest's next boot; they never bounce a running guest. To apply immediately: `sudo systemctl restart windows-vm-windows-dj`.
