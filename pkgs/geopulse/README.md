# GeoPulse packages

GeoPulse (Quarkus backend, Vue frontend) built from one upstream pin. Three
outputs come from it:

- `geopulse` — the coupled release, both halves joined; the family's registered
  owner.
- `geopulse-backend` — Quarkus fast-jar on JDK 25, with `patches/pkce.patch`
  applied.
- `geopulse-frontend` — Vite build on Node 22.

`source.nix` holds the single release pin — `version`, `rev`, `hash` — and the
two derivations take their version from it.

## Building

```console
nix build .#geopulse-backend .#geopulse-frontend
```

The GitHub archive, the Maven repository and the npm dependency tree are all
fixed-output derivations, so the build runs without network access and is
reproducible from the pin and the dependency hashes. Builds are per-system;
`aarch64-linux` is the deployment target and needs an aarch64 builder or the
deploy host.

## Updating

`geopulse` is the family's only registered owner. The batch keys a package's
write set on the registered output name (`pkgs/<name>`), which is why the coupled
release, not a single half, is the registered package.

```console
nix run .#update-packages -- geopulse                                # move the coupled pin
nix run .#update-packages -- --check                                 # newest stable release, no edits
GEOPULSE_UPDATE_VERSION=1.39.2 nix run .#update-packages -- geopulse # recorded target
```

`update.py` moves `version`, `rev` and `hash` in `source.nix` together, checks
that `patches/pkce.patch` still applies to the new revision, verifies the source
hash by building `geopulse-backend.src`, and then regenerates the Maven and npm
dependency hashes. A revision the patch no longer applies to fails the candidate
rather than producing a build that cannot compile.

The backend's Maven fixed-output hash is one value for both Linux
architectures. brotli4j selects its native jar through OS/arch-activated
profiles, so `backend.nix` resolves both profiles into the one repository
(`mvnFetchExtraArgs.postBuild`); the hash is the union and is identical on
x86_64 and aarch64. `nix-update` regenerates it on any updater host.

## License

GeoPulse is Business Source License 1.1 — licensor Oleksandr Chalyi, Change Date
2075-01-01, Change License AGPL-3.0-only — with an Additional Use Grant of
personal use only: individual, non-profit, private and educational. Commercial
use needs a licence from the licensor. The complete upstream LICENSE is installed
by both derivations under `share/licenses/geopulse/`.

All three outputs declare `meta.license = lib.licenses.bsl11`. Because nixpkgs
marks that licence unfree, they are instantiated from a package set whose
`allowUnfreePredicate` admits only the GeoPulse names (see
`modules/flake/packages.nix`); nothing else in the fleet gains unfree access.

The owner accepted publication of these builds to the fleet's niks3 cache under
that grant. That is a deployment decision, not a licence review.
