# Make the OIDC contract intrinsic and name the host-auth capability honestly

## Why

`identity-client` is one deployment aspect built from two contributors that are not the same kind of thing:

- `modules/identity/identity-oidc.nix` derives a **projection** — per-client OIDC endpoint URIs from `policy/identity.json` plus the canonical web-policy Kanidm route. It deploys nothing.
- `modules/identity/kanidm-host-auth.nix` deploys a **runtime capability** — the Kanidm client package, `services.kanidm.client`, `services.kanidm.unix`, PAM groups and SSH key integration.

Bundling them costs four concrete defects:

1. **The provider host must select a client capability to read a derived value.** `modules/identity/kanidm-runtime.nix:332` asserts `config.services.identity.oidc.providerUrl == cfg.appUrl`, and `:389-393` mirrors `clientPathPrefix`/`tokenUrl`/`clients` into `services.identity.kanidm.oidc.*`. The projection is declared by `identity-client`, so `identity-provider` cannot evaluate unless the host also selects `identity-client`. That is a performance of placement with no runtime meaning: the provider needs a *value*, not a Kanidm Unix client. Verified: nothing in `modules/` or `tests/` reads `services.identity.kanidm.oidc.*`, so the mirror at `:389-393` is dead in addition to being the coupling.

2. **Consumers fail with a missing option instead of a named assertion, which a canonical requirement already forbids.** With the aspect deselected, a consumer reading `services.identity.oidc.clients.<name>` dies with `The option 'services.identity.oidc' does not exist`. `openspec/specs/admin-module-structure/spec.md` already requires that "a missing required identity contract fails through a named assertion rather than a missing option namespace". `tests/check-dendritic-scaffold-contract.sh` check `7l-6` currently pins the opposite behaviour as intended — it asserts the failure text `services.identity.oidc' does not exist` for a host without `identity-client`. The implementation contradicts a live requirement and a test enforces the contradiction.

3. **The Kanidm release family is pinned by convention in three places.** `modules/identity/kanidm-host-auth.nix:32` (`pkgs.kanidm_1_11`, host-overridable), `modules/identity/kanidm-runtime.nix:396` (`pkgs.kanidmWithSecretProvisioning_1_11`) and `:444` (`pkgs.kanidm_1_11` in `environment.systemPackages`). Nothing keeps the server variant and the client tooling on the same line except review.

4. **The canonical single-derivation helper is dead code.** `lib/policy.nix:24` defines `mkOidcEndpoints` and `openspec/specs/provider-owned-oidc-uris/spec.md` requires it to be the one derivation with "identical logic across all call sites"; it has **zero call sites** in `lib/`, `modules/`, or `tests/`, while the projection re-derives the same URIs locally in `mkClientOidcEndpoints`.

The naming follows from the same confusion: `identity-client` is used for the projection, for the Unix/PAM/SSH capability, and informally for OAuth applications that are neither. Applications are OAuth clients of the provider; they do not use a Kanidm client at all.

## What Changes

1. **The OIDC projection becomes an intrinsic contract, not an aspect.** `identity-oidc.nix` keeps its option declarations and derivation but no longer publishes `flake.modules.nixos.identity-client`. It is imported by the modules that read it, so the contract exists wherever something needs it and no host expresses a placement decision to obtain option declarations.
2. **The remaining capability is published as `kanidm-host-auth`.** `identity-client` is retired with no compatibility alias; `la-admin-1` and `oci-melb-1` select `kanidm-host-auth` instead. Both hosts keep their current `services.identity.hostAuth` bindings unchanged.
3. **The provider leaf consumes the contract intrinsically.** `kanidm-runtime.nix` imports the projection, keeps its alignment assertion, and loses the dead `services.identity.kanidm.oidc.*` mirror. The provider no longer requires any client capability to be selected.
4. **Consumers own their OIDC wiring.** `paperless` and `karakeep` move `clientId`/`wellknownUrl` out of the `oci-melb-1` host fragment into their own leaves, importing the projection and keeping a named assertion for a missing client entry; hosts keep only the credential binding (`secretFiles.oidc`). `termix` already does this and only changes terminology.
5. **One Kanidm release-family value.** A private helper supplies the server wrapper and the client tooling from a single release binding, consumed by the provider leaf and the host-auth capability.
6. **One OIDC URI derivation.** `mkOidcEndpoints` from `lib/policy.nix` becomes the derivation the projection uses, and the local duplicate is removed.
7. **Tests state the new contract.** Scaffold check `7l-6` is inverted (a host without any identity aspect must still resolve the projection when a consumer imports it, and a host with a consumer but no provider must not fail on a missing namespace); the directionality test gains ratchets for provider-without-host-auth and projection-without-any-identity-selection, and its terminology follows the rename.

Unchanged: `policy/identity.json` remains the registration and provisioning authority (applications do not self-register — separate host evaluations cannot contribute to each other); provider-side and application-side credential bindings stay explicit, because they are two separate readership decisions even when they name the same encrypted file; `services.identity.hostAuth` behaviour, secrets, and SOPS readership are untouched.

## Impact

- Affected specs: `provider-owned-oidc-uris` (contract ownership and consumer terminology), `admin-module-structure` (admin OIDC directionality), `kanidm-identity` (version line, provider/client URL relationship, provisioning examples), `fleet-infrastructure` (aspect enumerations using `identity-client`), `host-unix-auth` (the host-auth capability becomes independently selectable).
- Affected code: `modules/identity/{identity-oidc,kanidm-host-auth,kanidm-runtime,identity-provider}.nix`, `modules/admin/termix.nix`, `modules/flake/paperless/core.nix`, `modules/flake/karakeep.nix`, `modules/hosts/{la-admin-1,oci-melb-1}/default.nix` and `oci-melb-1/_nixos.nix`, `lib/policy.nix` usage, a new private package helper, `tests/check-dendritic-scaffold-contract.sh`, `tests/check-identity-contract-directionality.sh`, `tests/phase-02-03-host-contract.sh` if its terminology changes.
- Non-goals: splitting the Kanidm provider (already independent), introducing any Kanidm consumer registry, moving to per-client encrypted credential files, restructuring `tests/check-identity-contract-directionality.sh` (tracked separately as TD-11), and touching secrets or `.sops.yaml`.
- Deployment: both hosts change one selection line; no runtime behaviour, port, unit, secret path, or endpoint changes.
