## Why

`comma` is useful for running one-off nixpkgs programs, but without a maintained nix-index database it requires a local index build. Use the upstream pre-built database so every fleet host gets the same low-maintenance operator workflow.

**Core value:** keep routine fleet administration reproducible and simple.

## What Changes

- Add `nix-index-database` as a flake input following the fleet nixpkgs input.
- Import its NixOS module for every host.
- Enable its `comma` integration in the shared shell profile.

## Capabilities

### New Capabilities

None. This is operator tooling configuration.

### Modified Capabilities

None.

## Impact

`flake.nix`, `flake.lock`, and `modules/profiles/shell-profile.nix`. No service, network, storage, or secret behavior changes.
