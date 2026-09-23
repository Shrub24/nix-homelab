## Context

See `proposal.md` for motivation and the four delta specs for observable contracts. Stage 0 established a verified three-host baseline and archived the preparatory cleanup. The current flake still constructs each host manually with `lib.nixosSystem` and passes `self`, `inputs`, and `ociImages` through `specialArgs`; host assembly remains under `hosts/`.

D-047 settles the target: flake-parts, `denful/import-tree`, `flake.modules.nixos.<aspect>`, a typed `nixos.configurations.<host>` registry, and one atomic relocation of all hosts. External validation confirmed that `flake.modules` requires `inputs.flake-parts.flakeModules.modules` and import-tree's `filterNot` receives leading-slash relative paths. The registry materializes complete NixOS systems through `inputs.nixpkgs.lib.nixosSystem`, not generic `lib.evalModules`; `nixosSystem` wraps nixpkgs' lower-level `eval-config.nix` while preserving the public flake integration contract.

## Goals / Non-Goals

**Goals:**

- Introduce the minimum Dendritic discovery, aspect, and host-registry foundation.
- Preserve every current flake output and all three evaluated host configurations.
- Remove the broad module argument bus completely at cutover.
- Make the temporary boundary around unconverted NixOS leaves explicit and removable.
- Keep host-private facts, bootstrap metadata, and disk layouts beside their host.

**Non-Goals:**

- Converting every service leaf into a standalone aspect.
- Changing feature placement, secret readership, deployment order, network policy, or service configuration.
- Implementing any unchecked task from `normalize-fleet-boundaries`.
- Introducing Den, `flake-file`, a shared topology repository, or the future `nix-fleet` library.
- Rewriting all architecture documentation before the later documentation-closure stage.

## Decisions

### DS-1 — One minimal flake-parts entrypoint owns discovery

`flake.nix` will retain only input declarations and `flake-parts.lib.mkFlake`. The root module imports:

1. `inputs.flake-parts.flakeModules.modules`;
2. one `denful/import-tree` result over `modules/`;
3. a named, inspectable `filterNot` predicate for directories that still contain plain NixOS modules.

Import-tree's built-in underscore exclusion protects genuinely private Nix files. JSON facts need no exclusion because discovery only selects `.nix` files.

The temporary predicate will enumerate unconverted paths rather than infer module type. A missed exclusion should fail evaluation loudly; no fallback blanket-import root will be added.

Alternative considered: rename every legacy leaf with an underscore. Rejected because it creates broad path churn that must later be reversed.

### DS-2 — Typed host records materialize existing outputs

A flake-parts module declares `nixos.configurations` as `lazyAttrsOf (submodule ...)`. Each record contains:

- required target `system`;
- a deferred NixOS `module` containing the host's explicit imports and configuration;
- optional host-local facter path and bootstrap data where applicable;
- a read-only evaluated `configuration`.

`configuration` is produced through `inputs.nixpkgs.lib.nixosSystem` with the record's explicit `system`, `modules = [ config.module ]`, and no `specialArgs`. The public wrapper calls nixpkgs' lower-level evaluator while supplying flake-library and source integration that a direct `eval-config.nix` call would otherwise duplicate. `flake.nixosConfigurations` maps the typed registry to those evaluated configurations. This preserves mixed-architecture evaluation without relying on the evaluator's current system.

All three hosts enter the registry in the same cutover. `home-forge` remains a deploy-rs node exactly as it is today; deploy ordering remains in `lib/deploy/hosts.nix`.

Alternative considered: construct hosts independently with `lib.nixosSystem` directly in `flake.nix`. Rejected because that retains a hand-maintained host list outside the typed registry. Materializing each typed registry record through `inputs.nixpkgs.lib.nixosSystem` does not have that drawback.

### DS-3 — Aspects are explicit imports, not automatic activation

Stage 1 publishes only the aspects required to own cross-cutting flake dependencies and composition infrastructure. Host records select them inside their deferred module's `imports`; discovery does not enable workloads merely because files exist.

Existing application and service modules remain ordinary NixOS leaves behind the temporary filter and are imported by selected aspects or host composition. Multiple files may contribute to one `flake.modules.nixos.<aspect>` later, but normal NixOS option conflict rules still apply.

Alternative considered: convert every leaf during scaffold introduction. Rejected because it combines mechanical architecture migration with behavioral refactoring and destroys the equivalence boundary.

### DS-4 — Replace each broad argument at its ownership boundary

The cutover removes every lower-level NixOS module parameter named `self`, `inputs`, or `ociImages`.

- **Repository provenance:** a flake-level base/provenance aspect closes lexically over `inputs.self` and sets `system.configurationRevision` plus `/etc/nixos-source`; `modules/core/base.nix` no longer silently depends on `args.self`.
- **Custom packages:** packages remain defined in `perSystem`; owning aspects select the host-matched package set with `withSystem pkgs.stdenv.hostPlatform.system` and feed existing package options or the narrow consuming module. No generic package argument bus is introduced.
- **Input-owned modules:** the DJ aspect closes over `inputs.traktor-m3u-sync`; the common CLI aspect closes over `inputs.nix-index-database`.
- **OCI images:** a NixOS policy module declares typed `repo.ociImages` data from `policy/oci-images.nix`; consuming services read `config.repo.ociImages` rather than a flake argument.
- **Deploy outputs:** deploy wiring receives the materialized configuration attrset directly instead of dereferencing `self.nixosConfigurations` inside `lib/deploy/default.nix`.

Alternative considered: retain renamed `repoInputs` or `repoPackages` special arguments. Rejected because that preserves the same hidden coupling under a different name.

### DS-5 — Host ownership moves atomically

`hosts/{la-admin-1,oci-melb-1,home-forge}` move to `modules/hosts/`. Relative paths are updated mechanically. Sole-consumer disko layouts move beside their hosts:

- `disko-single-disk-split.nix` → `modules/hosts/oci-melb-1/`;
- `disko-two-disk.nix` → `modules/hosts/home-forge/`.

OCI bootstrap metadata is inlined into its typed host record. The transitional `_bootstrap-config.nix` used during the initial cutover is deleted; host overlays and facter reports otherwise move verbatim. Dead storage modules outside this move are left for a later proven cleanup.

Alternative considered: pilot one host. Rejected because a split registry would require two composition systems and a compatibility bridge.

### DS-6 — Operator surfaces stay stable

The refactor preserves `nixosConfigurations`, packages, checks, formatter, dev shells, deploy-rs nodes, and deploy metadata. A typed `flake.bootstrap.nodes.<host>` projection exposes bootstrap values from the registry; `hostName` and `flake` are derived from the registry key rather than stored. `scripts/resolve-host-config.sh` consumes that JSON output instead of parsing Nix source indentation or exporting a source-file path.

Path-sensitive contract tests, scripts, runbooks, and factual architecture references move in the same change. Historical decision text remains historical unless it incorrectly presents an old path as current.

Alternative considered: keep direct `--file` parsing of `_bootstrap-config.nix`. Rejected because the registry already owns the data and source-text parsing is fragile.

### DS-7 — Equivalence is proved against Stage 0

Before cutover, record each host's toplevel derivation and targeted values that can be hidden by provenance handling. After cutover:

1. evaluate all three host drvPaths;
2. run `nix-diff` from each Stage 0 derivation to its Stage 1 derivation;
3. classify every difference;
4. accept only repository-source/provenance movement caused by the source tree;
5. explicitly compare `system.configurationRevision`, `/etc/nixos-source`, boot, filesystem, firewall, secret, service, user, package, and deploy surfaces;
6. run formatting, contract checks, and the repository's canonical `nix flake check --no-build --no-write-lock-file --refresh path:.` evaluation gate; run full builds only on builders that support each target architecture.

Any unexplained runtime delta blocks completion. A local full `nix flake check` platform mismatch is an environment limitation, not a substitute for the canonical evaluation gate or architecture-specific CI builds. The active production hosts are not deployed as part of this change.

## Risks / Trade-offs

- **[A plain NixOS leaf leaks into flake-parts discovery]** → Keep one named path predicate, add a contract check for its inventory, and require all-host evaluation.
- **[Relative paths break during host relocation]** → Move whole host directories atomically, update paths mechanically, and run path-sensitive tests before equivalence review.
- **[Provenance silently disappears when `self` is removed]** → Move provenance to lexical aspect ownership and compare both revision and source-link values explicitly.
- **[Per-system packages resolve for the evaluator instead of the target]** → Select packages with each evaluated host's `pkgs.stdenv.hostPlatform.system` and evaluate both architectures.
- **[Registry and deploy metadata become competing topology stores]** → Registry owns evaluation composition only; `lib/deploy/hosts.nix` remains the physical deployment SSOT.
- **[The transition implements deferred ownership cleanup accidentally]** → Relocate host overlays verbatim and review against the still-unchecked `normalize-fleet-boundaries` tasks.
- **[New inputs refresh unrelated lock entries]** → Update only the new flake inputs and review `flake.lock` changes.

## Migration Plan

1. Capture Stage 0 host derivations and targeted option/output values.
2. Repair only the malformed canonical specs this change must modify, preserving their current requirements.
3. Add pinned flake-parts/import-tree inputs and the registry/discovery scaffolding.
4. Perform the argument elimination, host relocation, and output cutover as one working-copy operation.
5. Update path-sensitive contracts and minimum factual documentation.
6. Run contract, flake, mixed-architecture, and provenance-aware `nix-diff` gates.
7. Obtain independent code review, remediate at most one safe pass, and run strict OpenSpec validation.

Rollback is the prior JJ change (`dendritic-stage-0-pre-clean` archive state). No deployment or data migration occurs.
