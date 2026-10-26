# Tasks — clean flake output surface

Each task ends in an observable check. Do not batch the gates: a rename is only
done when its consumers are updated and the suite that reads them passes.

## 1. Output allowlist

- [x] 1.1 Add a discovered contributor (e.g. `modules/flake/output-surface.nix`)
  that imports `inputs.flake-parts.flakeModules.touchup` and sets
  `touchup.any.enable = lib.mkDefault false` with an explicit allowlist:
  `nixosConfigurations`, `modules`, `packages`, `checks`, `devShells`,
  `formatter`, `apps`, `deploy`, `fleet`.
- [x] 1.2 Hide the inherited fixture:
  `touchup.attr.packages.any.attr.fixture.enable = false`.
- [x] 1.3 Verify: the published attribute list is exactly
  `apps checks deploy devShells fleet formatter modules nixosConfigurations
  packages`; `nixosModules`, `overlays`, `legacyPackages`, `bootstrap` and
  `deployHosts` are absent; `packages.<system>` has no `fixture`;
  `nix flake check --no-build` passes.

## 2. Publish `fleet`

- [x] 2.1 Stop publishing `flake.deployHosts`; publish `fleet.edgeHost`,
  `fleet.deployOrder` and `fleet.hosts` from the same validated topology in
  `modules/flake/deploy.nix`. The per-system profile filter reads
  `checkedDeployTopology` directly instead of round-tripping through the output.
- [x] 2.2 Merge the reimage slice into the per-host key: `modules/flake/bootstrap.nix`
  is deleted and `fleet.hosts.<id>.bootstrap` is published only for hosts whose
  record declares it.
- [x] 2.3 Update the host registry's `bootstrap` description to the published path.
- [x] 2.4 Verify: `fleet.hosts.oci-melb-1` carries `bootstrap` and
  `fleet.hosts.la-admin-1` does not; `fleet` has exactly
  `[deployOrder edgeHost hosts]`; `deploy.nodes` unchanged.

## 3. Update consumers

- [x] 3.1 `justfile`: the deploy recipe reads
  `.#fleet.hosts."$HOST".strictSubstituteOnly`.
- [x] 3.2 `.github/workflows/deploy-host.yml`: both reads move to `.#fleet`.
- [x] 3.3 `scripts/resolve-host-config.sh`: the guard, error message and
  `bootstrap_attr` read `.#fleet.hosts.<host>.bootstrap`; `deploy.sh`'s header
  names the same path.
- [x] 3.4 Verify: the resolver answers `oci-melb-1` (`TARGET_HOST=oci-melb-1`,
  `FLAKE=.#oci-melb-1`) and fails closed for `la-admin-1` with the named error.

## 4. Contract tests

- [x] 4.1 `tests/check-dendritic-scaffold-contract.sh`: the output list becomes the
  allowlist, a new negative loop asserts the removed attributes stay gone, and the
  `deployHosts`/`bootstrap` probes move to `fleet`.
- [x] 4.2 `tests/check-web-service-catalog.sh`: the deploy boundary reads
  `flake.fleet` (`edgeHost`, `deployOrder`, `hosts`).
- [x] 4.3 Verify: `check-web-service-catalog` passes; the scaffold contract run
  covers the new assertions.

## 5. Documentation

- [x] 5.1 `ARCHITECTURE.md`, `STRUCTURE.md`, `docs/architecture.md`,
  `docs/plan.md`, `docs/runbooks/host-initialization.md`: the projection and the
  module inventory name `fleet`/`deploy.nix`, and the Stage-8 narratives carry a
  parenthetical for the fold.
- [x] 5.2 `docs/research/flake-output-shape.md`: the implemented decisions are
  marked, the measured table is labelled as the pre-rework surface, and only the
  open items remain.
- [x] 5.3 `docs/decisions.md`: D-119 records the default-deny surface, the folded
  `fleet` output, and the per-entry audit that kept every inherited package a
  workflow reads.
- [x] 5.4 Verify: `treefmt --fail-on-change` is clean.

## 6. Gates

- [x] 6.1 `nix flake check --no-build` passes; `check-flake-file` still builds, so
  the generated `flake.nix` has not drifted.
- [x] 6.2 `just checks all` (parent session owns this gate).
- [x] 6.3 Recorded as D-119 rather than left in the design artifact.
