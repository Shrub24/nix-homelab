## Context

`applications.music` is the composition root for the fleet music stack. It already owns shared music paths (`/srv/media`, `/srv/data`), service imports under `modules/services/music/`, and manual/operator workflows such as Beets interactive wrappers and media permission reconciliation.

`traktor-m3u-sync` is an upstream Python CLI/NixOS module that can export Traktor `collection.nml` playlists to `.m3u8` and import `.m3u8` playlists back into a sandbox folder in `collection.nml`. The import side writes the collection file and creates an upstream timestamped backup before save. The first homelab integration should therefore be explicit and manual, not automated.

## Goals / Non-Goals

**Goals:**

- Add Traktor playlist sync as an optional music-stack worker on `oci-melb-1`.
- Use the upstream flake/package/module where possible instead of vendoring a Python derivation immediately.
- Configure manual systemd-triggered export and import jobs.
- Keep collection input, exported playlists, and import-input playlists in predictable `/srv/media` paths.
- Make the Traktor-side path mapping intentionally configurable/placeholder-driven until tested against the real NML.

**Non-Goals:**

- No path watches, timers, automatic bidirectional loops, or Syncthing-triggered automation in the first iteration.
- No bespoke Traktor parser or playlist manipulation code in this repo.
- No public service exposure; this is a local worker only.
- No guarantee that import is safe for unsupervised use until manual runs validate the sandbox behavior.

## Decisions

### TMS-1: Use upstream flake packaging first

Use `github:Shrub24/traktor-m3u-sync` as a flake input and consume its `nixosModules.traktor-m3u-sync` module if compatible with the current nixpkgs lock. The upstream module exposes `services.traktor-m3u-sync.*`, supports `aarch64-linux`, and creates `traktor-m3u-sync-export.service` / `traktor-m3u-sync-import.service` as manual oneshot units.

**Rationale:** The upstream already owns Python packaging, `traktor-nml-utils`, and systemd service definitions. Reusing it keeps this repo focused on fleet-specific paths and operational policy.

**Alternatives considered:** Vendor the Python derivation locally. This gives tighter control but duplicates upstream packaging and should wait until the upstream flake proves incompatible with this fleet.

### TMS-2: Manual systemd services only for iteration

Expose export/import through upstream systemd units `traktor-m3u-sync-export.service` and `traktor-m3u-sync-import.service`; do not add timers or path units yet.

**Rationale:** Import mutates `collection.nml`, and export path mappings need validation against real Traktor paths. Manual triggers allow operator inspection between runs.

**Alternatives considered:** Path watches on `collection.nml` or scheduled exports. These are deferred until the manual flow is boring.

### TMS-3: Separate collection, export, and import paths

Use `/srv/media/traktor/collection.nml` for Syncthing-sourced collection state and `/srv/media/playlists/traktor/` as the playlist workspace, with distinct export and import subdirectories. Prefer generated Nix module options over `configFile` for the first pass so runtime paths remain visible in host evaluation.

**Rationale:** Keeping import input separate from export output prevents immediate feedback loops and makes it clear which files are operator-curated for import.

**Alternatives considered:** Reuse one directory for both directions. This is simpler but increases the risk of accidentally re-importing generated output.

### TMS-4: Placeholder Traktor root mapping

Represent the Traktor-side root path as a configurable placeholder rather than hardcoding `C:/Music` or `D:/Music` in the long-lived design.

**Rationale:** The actual `collection.nml` path roots must be verified from the user's Traktor environment. The NixOS config should make the placeholder explicit so failed path translation is easy to diagnose.

### TMS-5: Treat import as sandbox-only until proven

The import job SHALL target the upstream sandbox-folder behavior (default `Imported Playlists` unless overridden) and remain manual.

**Rationale:** Upstream import destructively rebuilds the sandbox subtree while preserving non-sandbox playlists and creating backups. That is acceptable for testing but should not be hidden behind automation.

## Risks / Trade-offs

- **Incorrect path mapping** → Generated M3U files may reference paths Navidrome cannot resolve. Mitigation: use manual export first and inspect a small generated playlist before relying on it.
- **Import writes `collection.nml`** → Operator could rewrite the sandbox unexpectedly. Mitigation: manual-only import, separate import directory, upstream backups, and documented rollback location.
- **Upstream flake/nixpkgs mismatch** → Python 3.14 or dependency constraints may not fit the current lock. Mitigation: validate with `nix flake check --no-build` and fall back to vendoring only if necessary.
- **Syncthing conflict risk** → Traktor and the host may both modify `collection.nml`. Mitigation: keep import manual and document that the Traktor app should not concurrently write the collection during import.

## Migration Plan

1. Add upstream flake input and evaluate the package/module on the current systems.
2. Compose the worker into `applications.music` with paths under `/srv/media/traktor` and `/srv/media/playlists/traktor`.
3. Deploy to `oci-melb-1` with no automatic timers.
4. Place/sync a real `collection.nml`, run export manually, inspect generated `.m3u8` paths, then run import only with a small curated import directory.
5. Defer automation until manual runs validate path mapping and sandbox behavior.
