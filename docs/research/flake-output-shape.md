# Flake output shape

Research note, now partly implemented. What this repository published as flake
outputs, what the dendritic pattern and its references converge on, and the
decisions a rework had to settle. Steps 1 and 2 of the migration sketch landed in
`clean-flake-output-surface` (D-119) — the allowlist, the merged `fleet` output and
the hidden `fixture`; step 3, the roles inside `packages`, is still open and is
what the last section records.

## Method

- The pattern's own definition: `github.com/mightyiam/dendritic` (README, fetched).
- The reference implementation the pattern author points at for a real system:
  `github.com/mightyiam/infra` (`flake.nix`, `outputs.nix`, fetched).
- Mechanisms shipped by our pinned `flake-parts`
  (`6xr58mfvs42ixw6428x3vm9l5h88l2z7-source`): `extras/touchup.nix`,
  `extras/partitions.nix`, `modules/{legacyPackages,nixosModules,overlays}.nix`.
- Documentation: `flake.parts/options/flake-parts-touchup`,
  `flake.parts/options/flake-parts-partitions`, `flake.parts/options/flake-parts-modules`.
- Measurements below are `nix eval` against this tree, not recollection.

## What we publish, measured

The table below is the surface as measured **before** the rework (D-119).

| Output | Content | Declared by |
| --- | --- | --- |
| `nixosConfigurations` | 3 hosts | `modules/flake/host-registry.nix` |
| `modules.nixos` | 60 aspects | every discovered contributor |
| `packages.<system>` | 29 attributes (see below) | `modules/flake/packages.nix`, nix-fleet |
| `checks.<system>` | 10 | treefmt, scaffold contract, deploy checks, nix-fleet |
| `devShells.<system>` | `default` | `modules/flake/dev.nix` |
| `formatter.<system>` | treefmt wrapper | `modules/flake/dev.nix` |
| `apps.<system>` | `update`, `update-packages` | `modules/flake/package-updates.nix` |
| `deploy` | `nodes` (3) | `modules/flake/deploy.nix` |
| `deployHosts` | `nodes` (3), `edgeHost`, `deployOrder` | `modules/flake/deploy.nix` |
| `bootstrap` | `nodes` (1: `oci-melb-1`) | `modules/flake/bootstrap.nix` |
| `nixosModules` | `{}` | flake-parts default |
| `overlays` | `{}` | flake-parts default |
| `legacyPackages.<system>` | `{}` | flake-parts default |

`legacyPackages` above is *this* flake's output, which is empty. nixpkgs'
own `legacyPackages.<system>` — reached as
`(getFlake <this repo>).inputs.nixpkgs.legacyPackages.<system>` — is a different
flake object's output and is fully populated. An empty `legacyPackages` here
therefore does not mean the name is unavailable to scripts; it means this flake
publishes nothing under it, while advertising a name that nixpkgs legitimately
fills. Reaching into the input is one way to read a pinned value; publishing the
value is the other, and the way `pkgs/geopulse/update.py` now does it
(`packages.geopulse-maven-toolchain`, added after this note was first written).

`packages.<system>` by role, same 28 names:

| Role | Count | Examples |
| --- | --- | --- |
| buildable software | 8 | `bifrost`, `geopulse-backend`, `bookorbit-plugins`, `windows-dj-setup` |
| CI bundles and fixtures | 7 | `ci`, `ci-coordinator-*`, `ci-tailscale`, `fixture`, `arm-expensive` |
| data projections | 4 | `cache-api-url`, `cache-root`, `cache-public-key`, `cache-substituter-url` |
| generators | 3 | `write-flake`, `write-inputs`, `write-lock` |
| host activation profiles | 3 | `host-oci-melb-1`, … |
| vendored tools and pins | 4 | `deploy-rs`, `niks3`, `sops-bootstrap`, `geopulse-maven-toolchain` |

## Findings

### 1. Three outputs are flake-parts defaults, not decisions

`flake.nixosModules`, `flake.overlays` and `perSystem.legacyPackages` are declared
by flake-parts core (`modules/nixosModules.nix`, `modules/overlays.nix`,
`modules/legacyPackages.nix`) with empty defaults, and are published whether or
not anything populates them. We populate none of them. They cost nothing to
evaluate and print in `nix flake show`, and they invite a reader to believe the
repository offers modules, overlays and a package set for consumption.

Each is an interoperability contract for a consumer of this flake: `nixosModules`
for `imports = [ inputs.x.nixosModules.y ]`, `overlays` for
`nixpkgs.overlays = [ inputs.x.overlays.default ]`, `legacyPackages` for a
published package set. Nothing consumes this flake, and a consumer would reach
our nixpkgs pin through `inputs.nix-homelab.inputs.nixpkgs` regardless, so
re-exporting nixpkgs under `legacyPackages` would add a copy of a set we do not
own. The one non-degenerate use is a *combined* set —
`inputs.nixpkgs.legacyPackages.<system> // self.packages.<system>` — which matters
only to a downstream consumer, and there is none.

### 2. `packages` carries six different kinds of thing under one name

Six roles share one flat namespace, so `packages.<system>.<name>` does not
predict what `<name>` is: a derivation a user builds, a CI bundle, a string, a
JSON data file, a host activation profile, or a generator app's backing
derivation. The name `geopulse-backend` and the name `cache-api-url` live as
siblings and share no contract.

This is the largest single source of the "messy" impression, and it is not
fixable by hiding: our own recipes and workflows read most of these
(`justfile` reads `.#deploy.nodes.<host>.profiles.system.path`, CI reads
`.#checks`, `.just/checks.just` reads `.#checks.<system>.check-flake-file`).

### 3. The deploy topology is published as two bespoke views

`deploy.nodes` and `deployHosts.nodes` are projections of the same
`lib/deploy/hosts.nix` records, but they are not duplicates — measured:

```
deployHosts.nodes.oci-melb-1  → hostName, remoteBuild, sshUser, strictSubstituteOnly, system
deploy.nodes.oci-melb-1       → hostname, profiles, sshOpts, sshUser
```

`deploy` is the deploy-rs schema (consumed by `nix run .#deploy-rs` and
`deployChecks`); `deployHosts` is the fleet view — system, remote-build and
strict-substitute policy, plus `edgeHost` and `deployOrder`. Two views are
defensible; two *bespoke top-level names* are the cost, because a reader needs
both to answer "what is this host" and neither name says which is which.

### 4. `bootstrap` is a projection, not a capability

One host's reimage facts, derived from its `nixos.hosts.<id>` record by
`modules/flake/bootstrap.nix`, published as a top-level output so
`scripts/resolve-host-config.sh` can read it. It is the same class of thing as
`deployHosts`: a typed record projected for a shell script.

### 5. The aspects are the largest visible surface, and the most legitimate

60 entries in `flake.modules.nixos`. This is the dendritic pattern itself —
lower-level configurations stored as option values and published by name — and
it is what makes host records able to select aspects without importing files.
Its size is the fleet's size, not clutter, but it is what a reader sees first in
`nix flake show`.

## What the pattern and its references converge on

1. **Every published attribute is declared in a module.** `mightyiam/infra`'s
   `outputs.nix` is `mkFlake` plus `import-tree` and a `rootPath` argument; there
   is no bespoke output declaration at the flake level. `flake.nix` is rendered
   by `flake-file` from per-module input declarations. We already satisfy this
   (`flake.nix` generated, all outputs from modules).
2. **Standard names for standard things.** `nixosConfigurations`, `packages`,
   `checks`, `devShells`, `formatter`, `apps`, `modules.<class>.<aspect>`. A
   bespoke top-level attribute is a deviation that every consumer has to learn.
3. **Declare options for your own topology, then project.** The pattern's
   stated anti-pattern is *not* declaring options and leaning on existing ones
   instead. nix-fleet's `modules/flake/outputs.nix` is the model: an option
   (`configurations.nixos`, typed `lazyAttrsOf (submodule { module =
   deferredModule; })`) is the source, and `flake.nixosConfigurations` is its
   projection. Our `nixos.hosts.<id>` follows this; `deployHosts` and
   `bootstrap` are projections of `lib/deploy/hosts.nix` and `nixos.hosts`,
   which is the same shape but published at the flake level rather than through
   a declared option.
4. **Internal-only attributes are removed, not documented.** flake-parts ships
   `flakeModules.touchup`: a tree mirroring the output structure where
   `any.enable = false` plus an explicit allowlist publishes *only* the listed
   attributes. Its documented purpose is exactly "hiding attributes from
   `nix flake check` or `nix flake show` that are only meant for internal use".
   Our pin carries it (`extras/touchup.nix`, `flakeModules.touchup`).
5. **`partitions` is not the hiding mechanism.** It splits a flake into
   subflakes to keep `flake.lock` and input copying small (a `dev` partition
   with its own inputs). Useful for us only if the dev-only inputs grow.

## Target shape

| Output | Verdict | Reason |
| --- | --- | --- |
| `nixosConfigurations` | keep | the deployment entrypoint; deploy-rs, `nixos-rebuild`, CI |
| `modules.nixos` | keep | the dendritic aspect registry; host records and tests read it |
| `checks.<system>` | keep | `just checks all` and CI are the gate |
| `devShells`, `formatter`, `apps` | keep | standard, one entry each, all consumed |
| `deploy` | keep | deploy-rs' own schema; cannot be renamed |
| `deployHosts` | keep, or absorb `bootstrap` | the fleet view of the same records; `bootstrap` is one host's slice of the same topology |
| `bootstrap` | collapse or keep | one-host projection read by one script; folding it under the topology output removes a top-level name |
| `nixosModules`, `overlays` | remove | empty flake-parts defaults with no consumer; interop contracts this flake does not offer |
| `legacyPackages` | remove, or use as the nested surface | empty today; the only output that permits nesting, which `packages` does not |
| `packages.<system>` | keep the name, settle the roles | see below |

Implemented in D-119: `deployHosts` and `bootstrap` collapsed into one `fleet`
output, the three empties removed by the allowlist, `packages` left with its roles
and documented (the third option below) with `fixture` hidden.

For `packages`, the choices were not equivalent. `packages` is typed
`lazyAttrsOf types.package` (flake-parts `modules/packages.nix`), so a
non-derivation value fails the type: nesting by role is **not expressible** in
`packages`. `legacyPackages` is typed `lazyAttrsOf types.raw` and is the only
standard output that permits nesting.

- **Nest by role** (`legacyPackages.<system>.hosts.<id>`) — the shape supports it
  and `packages` does not, but it means *using* `legacyPackages` rather than
  removing it, and it splits the surface across two outputs so a reader needs
  both names to find one thing.
- **Move by meaning** — host profiles are already `checks`; `write-*` are
  `apps`; `cache-*` are data read by `policy`; CI bundles belong with CI. This
  removes roles rather than hiding them, at the cost of touching the recipes and
  workflows that read them.
- **Leave and document** — cheapest, and the honest answer if the roles are
  stable and consumed.

Removing the three empty outputs was the only change safe without a decision;
`touchup` with `any.enable = false` plus the allowlist also future-proofs the
surface, because a new output then has to be named deliberately. The `packages`
roles remain the one part of this note with no landed outcome.

## Migration sketch

1. ~~Add `flakeModules.touchup` and publish an explicit allowlist of today's
   outputs.~~ Landed: `modules/flake/output-surface.nix` names nine outputs and
   defaults to off, so `nixosModules`, `overlays` and `legacyPackages` are gone.
2. ~~Decide the topology surface: keep `deployHosts` as the fleet view and fold
   `bootstrap.nodes` under it, or keep both.~~ Landed as one `fleet` output:
   `fleet.hosts.<id>` merges the deploy record with the host's reimage metadata,
   with `edgeHost` and `deployOrder` beside it. `deploy` stayed deploy-rs' schema.
3. Decide `packages` (nest, move, or document) and change its consumers in one
   step, with `just checks all` and `nix flake check` as the gate. **Still open** —
   only `fixture` was hidden (nothing reads it through this flake).

## What landed, and what it cost

The allowlist's cost is that a new output is invisible until it is named, which is
the intended default but is a real failure mode: a contributor publishing
something it expects to be consumed will find it missing from `nix flake show`
rather than from an error. The scaffold contract asserts both directions — the
allowlisted attributes exist and the removed ones do not return — so a rename
fails a check instead of a deployment.

The `fleet` merge was cheaper than expected because the deploy module already
owned the topology validation: the projection closes over the checked records
instead of recomputing them, and `modules/flake/bootstrap.nix` had nothing left to
do. The one real constraint found while checking consumers is that inherited
outputs are not ours to hide freely — nix-fleet's `pin-cache.yml` reads
`packages.<system>.ci-tailscale` from the calling flake, so hiding it would have
broken cache pinning at workflow dispatch.

## Open decisions

1. Should `packages` be reorganised — and if nesting is wanted, is a nested
   `legacyPackages` acceptable in exchange for keeping that output? `packages` is
   typed `lazyAttrsOf types.package`, so nesting is not expressible there.
2. Is a `dev` partition worth it now that `flake.lock` carries dev-only inputs
   (`nix-index-database`, `treefmt-nix`, `flake-file`)?

Settled along the way: `flake.modules.nixos` stays published (it is this
repository's aspect registry and the surface's largest legitimate part), and
`bootstrap` does not deserve a top-level output — it is a per-host slice of
`fleet`.
