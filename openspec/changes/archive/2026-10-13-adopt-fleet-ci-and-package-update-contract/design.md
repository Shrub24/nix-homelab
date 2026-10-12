# Design

## CI

**CI-1 — `ci.yml` keeps validation and loses the build job; the fleet build moves to `fleet-build.yml`.**

The contract separates routine validation from the build path. Keeping nix-fleet's own arrangement — the build job inside `ci.yml`, gated by a workflow-dispatch condition — makes "routine CI does not build" a property of one condition rather than of the file's shape. This repository has already had that path mis-scoped once (a branch dispatch cannot reach the main-scoped cache OIDC claim, which is why the guard exists at all). Moving the build into its own file makes the property structural: `ci.yml` contains no job that builds fleet outputs, whatever its conditions.

Cost: one more workflow file, and the build's rationale comment moves with it.

**CI-2 — the validate job keeps its two sandboxed tooling builds.**

Validation still builds the `treefmt` check and `.#checks.<system>.check-flake-file`. Neither compiles a host closure: the first is the formatter (nix-fleet's own validate job builds its formatter check), the second is a seconds-long comparator that catches input-declaration drift — a real PR-time gate worth keeping. "CI must not build" is read as the fleet build plane, not as the gate's own tooling.

Rejected: adopting `nix flake check --no-build --all-systems` verbatim. Evaluation alone cannot pass on a cold store here, because evaluating this flake realises degoog's unsubstitutable bun2nix import-from-derivation (D-082). Rejected: dropping the drift comparator from PR-time validation, which would trade a real gate for a smaller step.

## Package updates

**PU-1 — register exactly what this repository owns.**

`windows-dj-setup` is the only locally authored package. `deploy-rs`, `niks3`, `sops-bootstrap`, `bifrost` and `bifrost-voyage-plugin` are input-derived, the `host-*` entries are deploy profiles, and the CI helper packages belong to nix-fleet's own feature — none is a second writer. A registry entry outside that set would make the batch edit files the repository does not own.

**PU-2 — `windows-dj-setup` gets an update script and a release check.**

The derivation has no single `src` and two upstream repositories (WinFsp and Mesa dist), so nix-update's standard discovery does not apply: the package declares an `updateScript` that refreshes both pins as one unit, which the batch dispatches to through its update-script path. It reports the newest stable WinFsp release through `checkUpdate`, compared against the package `version`. WinFsp is the version carrier because it is the primary pin and the one whose release gates the pair; Mesa is refreshed with it rather than versioned separately.

Rejected: no registry entry — the batch refuses an empty selection, and the two pins would keep drifting by hand. Rejected: a `writeSets` exception — the updater edits only its own directory, which is the default write set.

**PU-3 — delete nvfetcher rather than leave it dormant.**

The scaffolding currently owns no source. Keeping it would leave two canonical updaters for one dependency class, which the contract forbids, and would keep the `deps` module, the scheduled workflow and two treefmt exclusion lines alive to serve nothing.

**PU-4 — the scheduled refresh is the contract's workflow, adapted to what can be evaluated here.**

The batch runs the registered updaters and writes its report outside the checkout; the workflow then evaluates the refreshed tree and opens or updates one pull request. It evaluates the registered package's derivation path rather than running a whole-flake evaluation, which — per CI-2 — cannot pass on a cold store here. Acceptance stays the validate gate that runs on that pull request: a green refresh job is not a green candidate. `flake.lock` is untouched; the batch owns package pins.

## Documentation

**DOC-1 — the two stale canonical specs are corrected, and the file name is left alone.**

`dependency-source-management` and `nixbuild-build-plane` still describe nvfetcher and nixbuild.net as canonical. Both are corrected in place. The spec file name `nixbuild-build-plane` no longer describes its content; renaming a main spec is a structural decision with its own ripple (every reference and the capability index), so it is recorded here and left for a separate change rather than taken silently in this one.
