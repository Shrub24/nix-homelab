# Tasks

Implementation follows `design.md` CI-1, CI-2, PU-1 to PU-4, DOC-1. Each step is verified before the next; the parent owns the integration gates.

## 1. Package-update contract

- [x] 1.1 Add `modules/flake/package-updates.nix`: import nix-fleet's package-updates flake module and register `windows-dj-setup` as the repository's only owned package. Verify the `update-packages` and `update` apps resolve for both systems, and that the registry file an app binds lists exactly `windows-dj-setup`.
- [x] 1.2 Give `windows-dj-setup` its update policy: `passthru.checkUpdate` (newest stable WinFsp release, compared against `version`) and `passthru.updateScript` (a script that refreshes both coupled pins in `default.nix`). Verify the derivation still evaluates for both systems and that the script's refusal path needs no network.

## 2. Remove nvfetcher

- [x] 2.1 Delete `nvfetcher.toml`, `pkgs/_sources/`, `.github/workflows/nvfetcher-refresh.yml`, `.just/deps.just` and its `justfile` import, and the `pkgs/_sources` lines in `treefmt.toml`. Confirm no tracked file still references any of them.
- [x] 2.2 Add the contract's refresh workflow as `.github/workflows/package-updates-refresh.yml`: scheduled plus dispatch, report written outside the checkout, refreshed tree evaluated, one pull request, and `flake.lock` never written.

## 3. CI split

- [x] 3.1 Move the fleet build out of `.github/workflows/ci.yml` into `.github/workflows/fleet-build.yml`, dispatched manually and only on `main`, carrying the reusable-workflow pin, the builder inputs and the rationale comment. `ci.yml` keeps validation and contains no fleet build.
- [x] 3.2 Confirm both workflows parse and that `ci.yml` exposes no job that builds fleet outputs on any event.

## 4. Docs and specs

- [x] 4.1 Correct `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md` and `ARCHITECTURE.md` for the removed nvfetcher scaffolding, the new workflow set and the update commands.
- [x] 4.2 Record the adoption as a decision entry, and land the two spec deltas (`dependency-source-management`, `nixbuild-build-plane`).

## 5. Verification

- [x] 5.1 Evaluate: both systems' `update-packages` and `update` apps resolve; `windows-dj-setup` evaluates on both systems with `version = 2.1.25156`, `passthru.updateScript` and a `checkUpdate` whose `meta.mainProgram` is set; the batch's own output reads the registry as exactly one package (`package-updates: 0 newer of 1 checked`, `windows-dj-setup 2.1.25156 (current)`).
- [x] 5.2 Run the repository battery (`just checks all`), `treefmt --fail-on-change` and `openspec validate --strict`: all three pass (battery exit 0, formatting clean, change valid; the whole suite of contract tests unchanged and green).
