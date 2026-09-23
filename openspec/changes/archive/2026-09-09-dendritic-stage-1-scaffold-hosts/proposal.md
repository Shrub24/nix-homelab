## Why

The verified Stage 0 baseline is ready, but fleet construction still lives in a hand-written `flake.nix`, host assemblies sit outside the module tree, and broad `specialArgs` couple lower-level modules to flake implementation details. Introduce the smallest Dendritic scaffold that makes host and aspect ownership explicit while preserving every host's evaluated configuration.

**Core Value:** Establish one typed, auto-discovered fleet composition model without changing runtime behavior, deployment topology, or security boundaries.

## What Changes

- Add flake-parts and `denful/import-tree`, with `flake.modules` support and an explicit temporary exclusion boundary around unconverted NixOS leaves.
- Publish NixOS aspects through `flake.modules.nixos.<aspect>` and construct hosts through typed `nixos.configurations.<host>` records.
- Move all three host assemblies atomically from `hosts/<host>/` to `modules/hosts/<host>/`; underscore-prefix host-private/raw files that must not auto-import.
- Preserve all existing host feature selection and relocate host overlays, facts, and bootstrap metadata without executing superseded ownership work.
- Eliminate lower-level `self`, `inputs`, and `ociImages` arguments instead of retaining a compatibility `specialArgs` bridge.
- Resolve flake-input modules in their owning aspects, custom packages through flake-parts system context, OCI image references through typed policy, and repository provenance by lexical closure over `inputs.self`.
- Keep `nixosConfigurations`, packages, checks, deploy-rs nodes, and bootstrap data compatible with current operator commands.
- Update path-sensitive tests, scripts, and minimum factual documentation in the same change.
- Prove all three hosts equivalent to the Stage 0 baseline; only repository-source/provenance derivation differences are acceptable.
- Apply the approved completion refinements: materialize typed host records through `inputs.nixpkgs.lib.nixosSystem`, and inline OCI bootstrap metadata into its registry record while deriving registry-owned fields in the bootstrap projection.

Key constraints:

- No service, unit, package, firewall, secret, filesystem, user, boot, deployment, or topology behavior may change.
- No encrypted secret or `.sops.yaml` recipient policy may change.
- `normalize-fleet-boundaries` remains superseded and incomplete; relocation must not implement its unchecked ownership tasks implicitly.
- `flake-file`, Den, cross-repository topology ownership, and extraction to `nix-fleet` remain deferred.

## Capabilities

### New Capabilities

None. This change replaces fleet composition mechanics while preserving operator and host behavior.

### Modified Capabilities

- `fleet-infrastructure`: Host construction becomes a typed flake-parts registry under `modules/hosts/<host>/` while preserving the existing `nixosConfigurations` and deploy surfaces.
- `repository-structure`: Host assemblies join the auto-discovered module tree, with explicit exclusions for private host data and unconverted leaves.
- `bootstrap-storage`: Host fact and bootstrap metadata paths move with host ownership without changing adoption or reimage behavior.
- `admin-module-structure`: Admin host-local assembly moves under `modules/hosts/<host>/` without changing application or service ownership.

## Impact

- Adds flake inputs for flake-parts and `denful/import-tree` and rewrites `flake.nix` as a minimal flake-parts entrypoint.
- Adds scaffold/registry modules and relocates `hosts/{la-admin-1,oci-melb-1,home-forge}` under `modules/hosts/`.
- Updates current consumers of `self`, `inputs`, and `ociImages`, plus path-sensitive tests, scripts, CI references, and factual documentation.
- Preserves `lib/deploy/hosts.nix`, `policy/web-services.nix`, OpenTofu, secret readership, encrypted secrets, deployment order, host names, and flake output names.
