## Context

See `proposal.md` for motivation. The live home-forge tree currently uses `/srv/storage/media/library` as both the Syncthing/Navidrome/Beets music library and the Engine DJ `M:` root, with generated playlists and a bind-mounted Engine database nested inside it. Physical roots are duplicated in fleet policy, application defaults, leaf defaults, and host wiring. The migration changes live paths on one filesystem and must preserve service databases, Syncthing folder identities, and the Engine database.

## Goals / Non-Goals

**Goals:**

- **MS-1:** Make the host the sole owner of physical application and service-state roots.
- **MS-2:** Give the music application one conventional subtree beneath `/srv/storage/media/music`.
- **MS-3:** Require leaf paths and inject them from the application composition root.
- **MS-4:** Expose only the music subtree to Engine DJ as one `M:` share.
- **PS-1:** Make the bundled guest setup script parse and run under Windows PowerShell 5.1.
- **OP-1:** Migrate live paths with writers quiesced and an explicit rollback boundary.

**Non-Goals:**

- Reorganizing the existing `tagged` music subtree; Beets will handle that separately.
- Changing encrypted secret files or values.
- Updating the `traktor-m3u-sync` output-path contract, which is being replaced separately.
- Introducing generic storage abstractions for future photo or video applications.

## Decisions

### MS-1 — Host-owned roots, no physical path policy

`policy/globals.nix` will stop defining music filesystem roots. `applications.music.dataRoot` and `applications.music.storageRoot` become required options supplied by the host. A host-local `let` binding will provide the same `musicStorageRoot` to the music application, DJ application, and any transitional consumers.

This keeps physical mount placement in host assembly while leaving directory ownership and service composition in modules. The alternative—keeping a fleet default and overriding it per host—retains two authorities for a physical fact.

### MS-2 — Category root plus application root

Home-forge will use:

```text
/srv/storage/media/music/
  library/
  playlists/
  inbox/
  quarantine/
  .versions/
  Engine Library/   (real dir; the Engine database lives here)
```

`/srv/storage/media` remains a category boundary for future music-independent photo or video applications. Engine DJ shares `/srv/storage/media/music`, not the category root, so future categories cannot leak into the guest.

### MS-3 — Conventional derived paths are internal

The music application derives shared subtrees from `storageRoot` and passes concrete paths to leaves. Leaf path options required for an enabled service have no hardcoded defaults. The application remains the owner of shared tmpfiles and ACLs; leaves retain service-specific subtrees and runtime permissions.

The alternative—publishing every derived directory as an overridable application option—adds unsupported topology combinations and preserves the current drift surface.

### MS-4 — Single virtiofs share; Engine Library is a real directory

The DJ module receives an explicit required `sharePath` and exports it as `M:`. The Engine library is a real `Engine Library` directory beneath that root (created by host tmpfiles); the guest sees `M:\Engine Library` directly, with no second share, mount tag, host bind, or guest junction.

This keeps one share root so host and guest view the same layout and the Engine database rides the music storage root's existing backup coverage. A cross-device bind inside `M:` poisoned WinFsp readdir, and a separate `L:` share plus junction reintroduced a second drive; a plain directory on the single share avoids both.

### PS-1 — Windows PowerShell 5.1 compatibility

The setup script will use ASCII punctuation, parenthesized boolean command expressions, and Windows PowerShell 5.1-compatible service removal. VirtIO-FS creation and startup remain `New-Service` and `Start-Service` as requested. The script will be checked for non-ASCII executable text and parsed in the guest before declaring the task complete.

## Risks / Trade-offs

- **[Engine track paths change from `M:\<artist>` to `M:\library\<artist>`]** → Re-import or relink the fresh Engine collection after the migration; regenerate the external playlist artifact later through its replacement integration.
- **[Syncthing interprets a missing old path as deletion]** → Stop Syncthing before the same-filesystem rename, preserve folder IDs and markers, then deploy the new path before restarting it.
- **[A live bind mount blocks or obscures directory movement]** → Stop the Windows VM and unmount the old Engine bind before moving directories.
- **[Navidrome or Beets sees an incomplete tree]** → Stop writers for the migration window; preserve both databases and use same-filesystem renames only.
- **[Leaf default removal exposes previously hidden standalone consumers]** → Evaluate every fleet host and check index coverage for every edited module before deployment.
- **[Existing `tagged` data has unclear workflow ownership]** → Preserve it byte-for-byte beneath the migrated library and defer semantic reorganization to Beets.

## Migration Plan

1. Build and evaluate the new configuration without activating it.
2. Capture path, mount, service, Syncthing-folder, and filesystem-size preflight facts; retain the current and prior generations, confirm a fresh successful state backup, and inhibit the backup timer for the maintenance window.
3. Stop the live writer units (`slskd`, Navidrome, Syncthing, the concrete Beets and Podman units) and gracefully shut down the `windows-dj` domain, then unmount the old Engine Library bind.
4. Create `/srv/storage/media/music`; move the existing audio library, playlist directory, inbox, quarantine, and version archive into their declared sibling paths using same-filesystem renames. Preserve `tagged` unchanged and do not delete stale paths inside the pre-deploy rollback boundary.
5. Activate the new configuration, which creates the new bind, injects new leaf paths, redefines the VM share, and restarts services.
6. Validate Beets path resolution, Navidrome scan/health, Syncthing folder IDs and paths, service units, bind mounts, and guest-visible M-drive layout. Re-enable the backup timer, then remove only the approved stale paths after validation; treat the non-empty Beets pre-import copy as a distinct irreversible cleanup action.

Rollback before service validation: stop writers, unmount the new Engine bind, reverse the same-filesystem renames, and activate the prior NixOS generation. Preserve the prior generation until validation is complete.
