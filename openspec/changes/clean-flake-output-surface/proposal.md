# Change: Clean the flake output surface

## Why

The flake's outputs are its public interface, and today that interface is wider
than the repository means to offer. Measured on the current tree, 13 attributes
are published:

- Three are flake-parts defaults nothing populates — `nixosModules`, `overlays`
  and `legacyPackages.<system>`. `nix flake show` therefore advertises modules,
  overlays and a package set for consumption that do not exist.
- Two are this repository's own projections of one topology: `deployHosts`
  (fleet facts: system, remote build, strict-substitute, edge host, deploy order)
  and `bootstrap` (reimage facts for one host). Answering "what is host X" needs
  both, and neither name says which half it holds.
- `packages.<system>` mixes 29 names across six roles — buildable software, CI
  bundles, cache data, generators, host activation profiles, vendored tools — so
  the name does not predict the value. Part of that list is inherited from
  nix-fleet and includes entries (`fixture`) that are upstream's test surface.

## What Changes

- **Publish an explicit output allowlist.** `flake-parts.touchup` is imported and
  the surface becomes default-deny: an output appears only because a module names
  it. `nixosModules`, `overlays` and `legacyPackages.<system>` disappear as a
  consequence, and a future accidental output cannot leak.
- **Publish the fleet topology once, per host.** `deployHosts` and `bootstrap`
  are replaced by one `fleet` output:

  ```nix
  fleet = {
    hosts.<id> = { system; hostName; sshUser; remoteBuild; strictSubstituteOnly; }
      // optionalAttrs hasReimageFacts { bootstrap = { … }; };
    edgeHost = "<id>";
    deployOrder = [ "<id>" … ];
  };
  ```

  `deploy` stays exactly as it is: it is deploy-rs' own schema, not ours.
- **Hide one inherited package.** `packages.<system>.fixture` is nix-fleet's test
  fixture and has no consumer outside nix-fleet's own repository. The remaining
  inherited entries stay published because a workflow or an upstream contract
  names them (see design).
- **Update every consumer** of the renamed paths: the `justfile`, the
  `deploy-host` workflow, `scripts/resolve-host-config.sh`, and the scaffold,
  web-catalog and deploy contract tests.

## Core Value

The fleet stays reproducible and operable: nothing about deployment, bootstrap or
CI changes in behaviour, but the interface an operator, a script or another flake
reads becomes one namespace that says what it holds — and stops advertising
capabilities the repository does not provide.

## Key Constraints

- `deploy.nodes` is deploy-rs' schema and SHALL NOT be renamed, nested or
  extended; `deployChecks` and `nix run .#deploy-rs` read it.
- Every host fact keeps a single source: `lib/deploy/hosts.nix` for deploy
  topology, `nixos.hosts.<id>.bootstrap` for reimage facts. The `fleet` output is
  a projection, never a second declaration.
- `.#` is the local evaluation form (D-057); the Git index stays a precondition
  for every verification step.
- Hidden package outputs are the ones nothing reads. nix-fleet's reusable
  workflows read the calling flake by name, so each name is checked against
  upstream before it is hidden.
- `cache-root` stays published: `promote.yml` and `verify-cache.yml` measure it as
  the cache pin subject, and `checks.packages` builds it.

## Impact

- Affected specs: `flake-output-surface` (new capability); `feature-topology` and
  `fleet-infrastructure` are referenced, not modified.
- Affected code: `modules/flake/deploy.nix`, `modules/flake/bootstrap.nix`,
  `modules/flake/host-registry.nix`, a new output-surface contributor,
  `justfile`, `.github/workflows/deploy-host.yml`,
  `scripts/resolve-host-config.sh`, `tests/check-dendritic-scaffold-contract.sh`,
  `tests/check-web-service-catalog.sh`.
- Affected docs: `ARCHITECTURE.md`, `STRUCTURE.md`, `docs/architecture.md` (output
  descriptions), and `docs/research/flake-output-shape.md` (the investigation this
  change implements).
- Not affected: host configuration, deployment behaviour, cache contents (the set
  of built artefacts changes only by the hidden fixture), secrets.
