# Proposal

## Why

Our nix-fleet pin is current (`e5d744156`, the same commit as upstream `main`), but this repository still implements the previous shape of two of its contracts.

- **CI.** The contract makes the routine gate evaluation-only — `nix flake check --no-build --all-systems` plus a separately built formatter check — and keeps "building checks against the fleet's configured builders and cache" in "a separate path: the manually dispatched fleet-build job". Our `ci.yml` carries that build as a job inside the same workflow as validation, so the fleet build is one dispatch away from the routine gate rather than structurally outside it.
- **Package updates.** The contract replaced nvfetcher with one native interface: `flakeModules.packageUpdates` over `nix-update --use-update-script`, with each repository registering the `packages.<system>` outputs it owns. This repository still ships the nvfetcher scaffolding — `nvfetcher.toml`, a generated `pkgs/_sources/`, a weekly `nvfetcher-refresh` workflow and a `just deps refresh` recipe — while owning no nvfetcher source at all: the config declares no package entry, the generated file carries only its header, and nothing imports it.

**Core Value:** routine CI evaluates and never builds the fleet, and package pins have exactly one updater, matching the contracts nix-fleet publishes.

## What Changes

- Import `inputs.nix-fleet.flakeModules.packageUpdates` and register the one package this repository owns, `windows-dj-setup`. The repository gains `nix run .#update` (interactive picker over flake inputs and package updates) and `nix run .#update-packages` (batch, and `-- --check` for a cheap release check).
- Give `windows-dj-setup` the contract's package-side policy: a `passthru.updateScript` that refreshes its two coupled pins as one unit, and a `passthru.checkUpdate` reporting the newest stable WinFsp release.
- Remove nvfetcher entirely — the config, the generated directory, the refresh workflow, the `just deps` recipe and its module import, and the treefmt exclusions for the deleted directory — rather than leaving a second, unused update engine registered.
- Replace the scheduled refresh workflow with the contract's own: run the registered updaters, evaluate the refreshed tree, open one pull request. It refreshes pins and does not accept them.
- Move the fleet build out of `ci.yml` into `fleet-build.yml`, dispatched manually and only on `main`. `ci.yml` keeps validation, so routine CI cannot build the fleet.
- Correct the two stale canonical specs: `dependency-source-management` (nvfetcher to the packageUpdates contract) and `nixbuild-build-plane` (nixbuild.net and a substitution-only framing to the fleet's own builders and the fleet's nix-fleet-derived substituters).

### Constraints

- No host, secret, placement or deploy change; nothing is deployed.
- Routine CI must not build fleet outputs. The gate itself still builds its own sandboxed tooling — the formatter check and the flake.nix freshness comparator — exactly as nix-fleet's validate job builds its formatter check.
- `flake.lock` stays Renovate's. Neither workflow writes it.
- The DJ VM's setup media content and `setup.ps1` are unchanged; only the pins' refresh path changes.
- No second update engine, and no registration of a package this repository does not own.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `dependency-source-management`: ownership by source type names the package-updates contract instead of nvfetcher, the committed-generated-metadata requirement is removed, and the reviewable-refresh requirement now describes the package batch and its pull request.
- `nixbuild-build-plane`: the CI build-plane and substituter requirements are corrected to the fleet's own builders and the fleet's substituters, with routine CI evaluation-only and the build path in its own dispatched workflow.

## Impact

Workflows (`.github/workflows/ci.yml`, new `fleet-build.yml` and `package-updates-refresh.yml`, deleted `nvfetcher-refresh.yml`), the flake surface (new `modules/flake/package-updates.nix`), the package (`pkgs/windows-dj-setup/default.nix` plus a new update script), removals (`nvfetcher.toml`, `pkgs/_sources/`, `.just/deps.just`, its `justfile` import, two `treefmt.toml` lines), docs (`STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `ARCHITECTURE.md`, a decision record) and the two spec files above.

No remote operation, no secret change and no host activation. Acceptance is the existing validate gate plus the repository's own battery run locally.
