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
ls -la /srv/storage/media/music '/srv/storage/media/music/Engine Library'   # share root + Engine dir exist
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

The command stages both into `/srv/data/windows-vm/windows-dj/`, redefines the domain in installer mode (CD-ROM-first boot), and starts it. The instance already enables emulated TPM 2.0 for Windows 11.

Start a SPICE tunnel from a tailnet device, then open the console:

```sh
just ops::spice
remote-viewer spice://127.0.0.1:5900    # or virt-viewer
```

1. Run Windows setup. At disk selection the disk list is empty — click **Load driver**, browse the virtio-win CD, and install `viostor` (storage) for your Windows version. Add `NetKVM` (network) the same way if you want network during setup.
2. Complete installation and activate with the supplied license.
3. Secure Boot is not emulated by this domain's firmware; if Windows 11 setup refuses, use an installation image with the check relaxed or fall back to Windows 10.
4. Inside the guest: run `virtio-win-guest-tools.exe` from the virtio-win CD (virtio-fs driver, SPICE agent). The setup share `S:` (WinFsp, Mesa, `setup.ps1`) is hash-pinned via Nix — mount once then run:

   ```powershell
   # Admin CMD first — temporary mount until services exist:
   "C:\Program Files\Virtio-Win\viofs\virtiofs.exe" -t setup -m S:
   # then Admin PowerShell:
   powershell -ExecutionPolicy Bypass -File S:\setup.ps1
   ```

   This installs WinFsp, registers `M:`/`S:` via `New-Service`/`Start-Service`, removes the legacy `L:` Engine-library share, disables sleep, and installs the Mesa fallback.

5. Leave installer mode:

   ```sh
   ssh dev@home-forge -- windows-vm-windows-dj-install --clear
   ```

Reinstalling later is the same flow: run the install command again, then `--clear` afterwards.

## 3. Map the library share

Shares: `media` (RW, whole music root `/srv/storage/media/music`) → `M:`; `setup` (RO, Nix store) → `S:`. Step 2.4 already creates `M:`/`S:` via `S:\setup.ps1` — this section is the result:

- `M:\Engine Library` is a real directory on the music share (host `<storageRoot>/Engine Library`), created by host tmpfiles — there is no separate Engine share, mount tag, or guest junction
- the operator points the Windows Music known-folder directly at `M:` so Engine resolves `Music\Engine Library` to `M:\Engine Library`; `setup.ps1` creates no link and never moves library files
- `M:` holds the canonical media library (music at `M:\library`); `M:\playlists` no longer receives sync output — playlists are written straight into the Engine library DB (see below)
- Sleep/hibernate is disabled; Mesa `opengl32sw.dll` is installed if Engine was found
- The legacy `VirtioFS-Library` and `VirtioFS-EngineLibrary` services (old `L:` mappings) are removed by `S:\setup.ps1` as cleanup

## Navidrome playlist sync (engine-direct)

Navidrome exports playlists as M3Us. `playlist-sync` batch-exports every playlist as `/music`-rooted M3Us into `/srv/data/traktor-m3u-sync/import/` (stale M3Us replaced, empties skipped) and starts the import job. It fetches playlists through Navidrome's Subsonic API using the `navidrome_username`/`navidrome_password` secret — it never reads the Navidrome DB directly — and never runs automatically.

1. Run the sync command on `home-forge`, then check both jobs (`playlist-sync` needs root because it drives a system-level `systemd-run` transient unit and starts the import job):

   ```sh
   ssh dev@home-forge -- sudo playlist-sync
   ssh dev@home-forge -- sudo systemctl status 'traktor-m3u-sync-import@navidrome' 'traktor-m3u-sync-export@engine' --no-pager
   ```

2. The export job publishes playlists directly into the Engine library database at `<storageRoot>/Engine Library/Database2/m.db` (host `/srv/storage/media/music/Engine Library/Database2/m.db`, guest `M:\Engine Library\Database2\m.db`) with `track_path_prefix=../library`, so tracks resolve relative to the Engine Library dir on `M:`.
3. In the guest, open Engine DJ and confirm the synced playlists appear and their tracks resolve from `M:\library`. The iTunes-XML import path is superseded; investigate a failed job before retrying.

The import and engine-export jobs bind to `dj-library-writers.target`, so starting them stops the VM first and starting the VM stops them (single-writer discipline; see V8).

The fetcher accepts both library-relative paths and absolute paths rooted at `<musicStorageRoot>/library` and emits `/music/<relative>` exactly once. Navidrome's `DefaultReportRealPath=true` covers new clients; the existing `playlist-sync` player must be toggled to report real paths in the Navidrome UI (per-player setting) or the API returns music-folder-relative paths instead.

The worker's SQLite state is `/srv/data/traktor-m3u-sync/store.db`. Removing it resets import tracking only; it never changes Navidrome playlists or media and does not revert tracks already published into the Engine database.

## 4. Engine DJ Desktop and the SC6000

- Install Engine DJ Desktop **≥ 4.3.4** (Remote Library security fix); current line is 5.x.
- Autologon (required — Remote Library needs a live desktop session): `netplwiz` → uncheck "Users must enter a user name and password" and set the password, or Sysinternals `Autologon64.exe`.
- `Failed to initialize graphics backend for OpenGL`: virtio-gpu has no GL — `S:\setup.ps1` copies `S:\opengl32sw.dll` (Mesa 26.2.0, hash-pinned) to the Engine install dir as `opengl32sw.dll`.
- SC6000 pairing: both devices share the LAN through `br0` (same L2). On the SC6000: Source → Engine DJ Desktop section → select the computer. Accept the pairing dialog inside Engine Desktop at the SPICE console (first connection needs someone present).
- Tracks stream from the VM; cues/grids sync bidirectionally in real time.

## 5. Validation gate

These checks established the settled layout. Re-run them after material virtiofs, QEMU, WinFsp, or Engine changes; corruption triggers design R1's guest-local DB fallback.

| #   | Check                                         | Pass criteria                               |
| --- | --------------------------------------------- | ------------------------------------------- |
| V1  | Engine launches against the shared library    | No errors; library opens                    |
| V2  | Import tracks from the media share            | Tracks import, analyze, play                |
| V3  | SC6000 Remote Library connect                 | Player sees the VM source; track loads      |
| V4  | Clean guest shutdown, host-side DB inspection | Files readable; SQLite integrity ok (below) |
| V5  | Guest reboot                                  | Tracks resolve; SC6000 reconnects           |
| V6  | Navidrome playlist sync (engine-direct)       | Playlists appear in Engine DJ after the import→export chain; tracks resolve from `M:\library` |
| V7  | Backup quiesce                                | Backup stops the VM, runs, restarts it      |
| V8  | Writer conflict semantics                     | Starting either side stops the other        |

V4 — after shutting down the guest cleanly:

```sh
sqlite3 '/srv/storage/media/music/Engine Library/Database2/m.db' 'PRAGMA integrity_check;'
# expect: ok
```

V6 — run the playlist sync above (export M3Us, start the import job, chained engine export), then confirm the playlists appear in Engine DJ and tracks resolve from `M:\library`.

V7 — with the VM running:

```sh
sudo systemctl start restic-backups-state
# during the run: virsh domstate windows-dj -> "shut off"
# after the run: virsh domstate windows-dj -> "running"
```

V8 — writer conflict checks (the writer jobs bind to `dj-library-writers.target`, which conflicts with the VM):

```sh
# target vs VM: starting either stops the other
sudo systemctl start dj-library-writers.target   # VM unit deactivates, guest shuts down
sudo systemctl start windows-vm-windows-dj       # target deactivates before guest starts
# writer chain vs VM: starting the import/export stops the VM first
sudo systemctl start traktor-m3u-sync-import@navidrome   # VM shuts down, then import runs
sudo systemctl start windows-vm-windows-dj               # writer unit deactivates before guest starts
```

Record results. Any database corruption or locking misbehavior: stop, do not retry against the same data, and switch to the fallback layout per design R1 before proceeding.

## Single-writer discipline reference

The Engine library directory (`<storageRoot>/Engine Library`) alternates ownership:

| Writer                                   | Mechanism                                                             |
| ---------------------------------------- | --------------------------------------------------------------------- |
| VM (Engine DJ)                           | runs while `windows-vm-windows-dj.service` is active                  |
| playlist-sync import/export jobs         | bind to `dj-library-writers.target` (`BindsTo`), which conflicts with the VM unit |
| restic state backup                      | quiesce hook stops the VM only if running, restarts it afterwards; the job conflicts with `dj-library-writers.target` |

Never edit files under the library directory while the VM is running.

VM config changes (memory, shares, SPICE port) are redefined at deploy time and apply at the guest's next boot; they never bounce a running guest. To apply immediately: `sudo systemctl restart windows-vm-windows-dj`.
