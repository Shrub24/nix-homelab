## 1. Preconditions and baseline

- [ ] 1.1 Confirm `decouple-identity-admin-capabilities` is complete and the operator identifies the tested Stage 7-derived base revision; verify JJ contains no unrelated uncommitted deployment edits.
- [ ] 1.2 Capture flake output names, bootstrap nodes, deploy metadata, web host references, host aspect selections, and per-host structured observables; verify all three host derivations evaluate.

## 2. Canonical host identity and discovery

- [ ] 2.1 Add the typed canonical host-record schema and generic materializer; verify duplicate/invalid host IDs and Tailscale identities fail with named errors.
- [ ] 2.2 Convert `oci-melb-1`, `la-admin-1`, and `home-forge` into discovered host contributors one at a time, moving facter/disko/private fragments under explicit private paths; verify each existing `nixosConfigurations` and bootstrap output remains available after its batch.
- [ ] 2.3 Remove concrete host names from `modules/flake/registry.nix` and remove `hosts` from `_unconverted-nixos-dirs.nix`; verify the remaining boundary is exactly `[ "services" ]`.

## 3. Referencing concerns

- [ ] 3.1 Make deploy metadata reference canonical host IDs while retaining SSH target, user, deploy order, and remote-build facts; verify unknown references fail and deploy outputs are equivalent.
- [ ] 3.2 Make host-backed web routing references validate against canonical host IDs and derive Tailscale FQDNs from host identity; verify public URLs, origins, edge routes, and OpenTofu export are unchanged.

## 4. Internal service contracts

- [ ] 4.1 Add typed PostgreSQL and Niks3-write contracts with provider ID and port plus resolved private endpoint outputs; verify unknown providers and provider/aspect mismatches fail.
- [ ] 4.2 Migrate AudioMuse PostgreSQL wiring and all Niks3 upload clients to the contracts; verify no consumer embeds `oci-melb-1` and cache reads remain on their existing authority.
- [ ] 4.3 Add negative tests for stale placement, unknown host references, and accidental identity/ntfy duplication; verify each mutation fails with the expected contract name.

## 5. Source ownership and final validation

- [ ] 5.1 Move only settled/touched contributors into semantic host and feature-domain paths while reserving `modules/flake/` for output/materialization concerns; verify discovery and aspect names remain stable.
- [ ] 5.2 Update architecture, decisions, structure, and extension guidance; verify paths describe current source ownership rather than a flat-module requirement.
- [ ] 5.3 Run `treefmt --fail-on-change`, `just checks all`, `nix flake check --no-build path:.`, all host evaluations, and `openspec validate dendritic-stage-8-host-identity-contracts --strict`; compare LA/home-forge closures and OCI structured observables, obtain independent reviews, and leave the change undeployed/unarchived.
