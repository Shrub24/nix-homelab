## 1. Baseline and coupling evidence

- [x] 1.1 Capture the coupling with raw evidence: the three host toplevel `drvPath`s; the scaffold `7l-6` failure text that pins the missing-namespace behaviour; `grep -rn 'identity\.kanidm\.oidc' modules/ tests/` showing the provider mirror has zero readers; the three Kanidm package pins (`kanidm-host-auth.nix:32`, `kanidm-runtime.nix:396`, `:444`); `grep -rn 'mkOidcEndpoints' lib/ modules/ tests/` showing one definition and no call site.
- [x] 1.2 Record the identity observables for `la-admin-1` and `oci-melb-1` as the equivalence baseline: selected aspects, `services.identity.oidc.providerUrl`, the resolved `clients` key set and per-client endpoints, `services.identity.hostAuth` values, `services.kanidm.*` package drv paths, and the OIDC values reaching paperless/karakeep/termix.

## 2. The projection becomes an intrinsic contract

- [x] 2.1 Remove the `flake.modules.nixos.identity-client` publication from `modules/identity/identity-oidc.nix`, keeping the `services.identity.oidc` declarations, the web-policy default, and the derivation; rewrite the file header to describe an intrinsic contract that consumers import.
- [x] 2.2 Delete the dead Pocket-ID-era helper: remove `mkOidcEndpoints` from `lib/policy.nix` and remove the canonical requirement that mandates it (delta spec `## REMOVED Requirements`, reason and migration recorded). Kanidm's authorization and token endpoints are provider-level while discovery and userinfo are client-level, so a single-issuer-base signature cannot express the live shape; the contract file is the single derivation site.
- [x] 2.3 Consume the contract intrinsically in the provider leaf: `modules/identity/kanidm-runtime.nix` imports `./_oidc.nix`; delete the `services.identity.kanidm.oidc.*` mirror (`:389-393`, zero readers); keep the `providerUrl == appUrl` alignment assertion and its message; update `modules/identity/identity-provider.nix`'s header and failure prose to describe intrinsic consumption instead of a required `identity-client` selection.
- [x] 2.4 Prove the provider no longer depends on a client capability: in a scratch copy outside the repo, remove both `aspects.kanidm-host-auth` and the host's own `identity.hostAuth` assignment (the capability declares that namespace, so the assignment cannot survive its removal), then evaluate — the provider must succeed with a non-null `providerUrl`, `services.identity.oidc` present, `services.identity.hostAuth` absent, and no Kanidm unixd/client integration enabled.

## 3. The host-auth capability is renamed

- [x] 3.1 `modules/identity/kanidm-host-auth.nix` publishes `flake.modules.nixos.kanidm-host-auth` and imports the projection fragment; options, defaults, `services.kanidm.*` wiring, and both assertions are unchanged.
- [x] 3.2 Swap the selection in the host records: `la-admin-1` and `oci-melb-1` select `aspects.kanidm-host-auth`; both keep their existing `services.identity.hostAuth` bindings untouched.
- [x] 3.3 Prove no `identity-client` reference survives outside history: no occurrence in `modules/`, `tests/`, `policy/`, `lib/`, `scripts/`, `justfile`, or live documentation (archived changes and `docs/decisions.md` history are exempt and annotated separately).

## 4. Consumers own their OIDC wiring

- [x] 4.1 `modules/flake/paperless/core.nix`: import the projection fragment, derive `clientId`/`wellknownUrl` from `services.identity.oidc.clients.paperless`, and fail with a named assertion (not an empty value) when that client entry is absent.
- [x] 4.2 `modules/flake/karakeep.nix`: same, for `clients.karakeep`, preserving its existing `oidc.enable` guard and secret-file contract.
- [x] 4.3 `modules/admin/termix.nix`: keep its named missing-contract throw; update the prose from `identity-client contract` to the OIDC contract. No structural change.
- [x] 4.4 `modules/hosts/oci-melb-1/_nixos.nix`: drop the four projection reads (`:96-97`, `:135-136`), keep the `secretFiles.oidc` bindings, and confirm the rendered OIDC env values are unchanged.
- [x] 4.5 Prove a consumer-only host resolves endpoints: a composition with paperless (or karakeep) enabled and neither the provider nor the host-auth capability selected evaluates and resolves the same endpoints as the baseline.

## 5. One Kanidm release family

- [x] 5.1 Add the private value helper `modules/identity/_kanidm-packages.nix` exposing the server wrapper and the client tooling from one release binding, with a one-line comment stating that both move together and that the upgrade gate still applies.
- [x] 5.2 Consume it in the provider leaf (`services.kanidm.package`, `environment.systemPackages`) and in the host-auth capability (`services.kanidm.package = lib.mkDefault …`, override retained).
- [x] 5.3 Prove the resolved packages are unchanged from the baseline (`nix eval` the two `services.kanidm.package` paths and the system-package entry).

## 6. Tests state the new contract

- [x] 6.1 Invert scaffold check `7l-6`: a composition whose only identity participant is a consumer importing the projection must evaluate and resolve `clients.<name>`; a consumer leaf whose client entry is absent must fail through its named assertion, not a missing option. Extend the `host_leaf_imports_of` guard so a host re-importing `modules/identity/identity-oidc.nix` directly still trips it.
- [x] 6.2 `tests/check-identity-contract-directionality.sh`: add the provider-only subset leg (provider selected, `kanidm-host-auth` absent → evaluates, `providerUrl` non-null, `hostAuth.enable == false`).
- [x] 6.3 Same suite: add a projection-only probe importing the fragment alone (no aspect) that resolves `clients.<name>` and its five endpoints — the identity analogue of the backups `7i-5` probe.
- [x] 6.4 Same suite: add a terminology ratchet failing on any remaining `identity-client` reference in the touched surfaces, and keep the existing ratchets (`identity-provider` must not write `services.identity.oidc.*`, kanidm-admin catalog alignment).
- [x] 6.5 Correct the stale placement enumerations inside the `fleet-infrastructure` scenarios this change edits (the LA enumeration still names `admin-hub`, removed by D-054, and does not reflect the demoted `cockpit`) so the canonical spec stops asserting placements the host records contradict.

## 7. Documentation and decision record

- [x] 7.1 Record the decision (D-059): the boundary rule — deployment capabilities are aspects, shared contracts are intrinsic fragments or fleet policy, and secret readership stays an explicit per-deployment binding — plus this change's specifics (projection intrinsic, aspect rename, release-family helper, `mkOidcEndpoints` made real, dead mirror removed).
- [x] 7.2 Update live documentation: `ARCHITECTURE.md`, `STRUCTURE.md`, `docs/architecture.md`, `CONVENTIONS.md` (the boundary rule and the `_`-helper form), and the `AGENTS.md` architecture block if it names the retired aspect. Annotate `docs/decisions.md` history only.
- [x] 7.3 Ledger: record the per-client identity credential-file layout as a future, operator-owned item (relocation ergonomics; not coupled to this change), and note that the retired `identity-client` bundle is superseded rather than deprecated.

## 8. Validation

- [ ] 8.1 Equivalence: three host evaluations; aspect sets differ only by the rename; `providerUrl`, `clients`, `hostAuth`, rendered OIDC env values, and secret paths are identical to the baseline; no new `sops.secrets` or SOPS readership. Toplevel `drvPath`s WILL differ and are not evidence — `environment.etc."nixos-source"` publishes the tracked tree, so every tracked edit moves `/etc`, `activate`, and the toplevel (D-057). Equivalence is judged on structured observables, never on derivation equality.
- [ ] 8.2 Full battery: `treefmt --fail-on-change`, `just checks all`, `nix flake check --no-build .#`, and strict `openspec validate`.
- [ ] 8.3 Independent reviews: architecture (ownership, directionality, no residual co-selection, no dead namespace left behind) and security (no secret readership change, no new decryption surface, credential bindings still explicit on both sides).
- [ ] 8.4 At sync time, hand-edit the canonical Purpose paragraph of `openspec/specs/provider-owned-oidc-uris/spec.md`, which still names `identity-client`: deltas cannot edit a Purpose and the terminology ratchet scopes to `modules/` and `tests/`.
