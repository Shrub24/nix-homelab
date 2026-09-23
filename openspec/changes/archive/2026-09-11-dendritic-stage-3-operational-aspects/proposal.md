## Why

Stage 2 left five operational leaves imported and enabled almost identically by every host so their ownership could be resolved separately from the foundation. They now have clear boundaries: backups and cache upload form one host-egress capability, nixbuild SSH trust is builder access, and Beszel agent enrollment is observability-agent capability.

**Core Value:** Make operational capabilities explicit host selections while preserving backup recovery, cache upload, builder trust, monitoring, secrets, and deployment behavior.

## What Changes

- Publish `backups`, `builder-access`, and `observability-agent` as explicit NixOS aspects selected by all three current hosts.
- Make `backups` compose state backups, the niks3 upload client, and post-deploy closure upload; derive the existing bucket convention from the host name while retaining real host variants.
- Make `backups` self-contained: it imports the `niks3-auto-upload` upstream module itself and injects the required `nix-path-filter` package into post-deploy through a typed option — no hidden `fleet-packages` dependency.
- Require notification composition when backups are enabled without making either aspect import the other; `notify` owns monitor composition (canonical apprise contract).
- Derive the conventional host-scoped secret path (`secrets/hosts/${hostName}/system.yaml`) inside the `backups` and `observability-agent` aspects, defaulting the state-backup and Beszel secret-file options to it and gating enablement on the file's existence — preserving two-step secret bootstrap on every host without changing ciphertext or readership.
- Make `builder-access` own only nixbuild.net SSH trust/configuration; substituter policy remains in the base aspect.
- Make `observability-agent` own Beszel agent authentication and enrollment; the Beszel hub remains an admin-service leaf.
- Remove the repeated five-leaf host import block and repeated enablement that these aspects replace.
- Preserve the existing `nix.settings.post-build-hook = lib.mkForce ""` as a classified compatibility constraint of upstream `niks3-auto-upload`: the daemon/socket is needed by post-deploy upload while its automatic Nix hook must remain disabled. Do not add another override or hide it elsewhere.
- Keep the `services/` and `shared/` import-tree exclusions because both roots still contain unconverted leaves.

Key constraints:

- No encrypted-secret, `.sops.yaml`, recipient, deployment-topology, bootstrap, or workflow edits.
- No hidden aspect imports, hidden `fleet-packages` dependency, generic composition bus, compatibility wrapper, or new `mkForce`.
- Preserve OCI's niks3 token ownership override and loopback cache endpoint.
- Preserve all three current host selections, including builder access on home-forge.
- Any unexplained runtime or recovery delta is a hard stop.

## Capabilities

### New Capabilities

None. This is a behavior-preserving ownership refactor of existing operational capabilities.

### Modified Capabilities

- `fleet-infrastructure`: Hosts select operational aspects explicitly instead of repeating their leaf imports and enablement.
- `state-backups`: Backup selection owns state backup and cache-upload composition and requires notification monitoring explicitly.
- `sovereign-binary-cache`: Post-deploy cache push moves under the backups aspect without changing its activation trigger or upload behavior.
- `nixbuild-build-plane`: Builder SSH trust becomes a narrowly owned aspect while substituter policy remains unchanged.
- `internal-service-auth`: Beszel agent enrollment becomes an explicit observability-agent aspect with unchanged secret boundaries.

## Impact

- Affects `modules/flake/aspects.nix`, `modules/flake/registry.nix`, the three host assemblies, the five deferred operational leaves, and focused scaffold/backup contracts.
- Adjusts the `notify` aspect to own monitor composition (canonical apprise contract); no new delta spec because the canonical apprise spec already mandates it.
- Removes the `niks3-auto-upload` upstream module import from all registry records (OCI keeps the niks3 server module import).
- Updates current architecture, decisions, migration tracking, and backup/operator documentation.
- Does not move the niks3 server, Beszel hub, service contributors to state backups, secret files, or deploy topology.
- Does not shrink `modules/flake/_unconverted-nixos-dirs.nix` in this stage.
