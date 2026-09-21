# Design: make-oidc-contract-intrinsic

## Context

`identity-client` is a placement aspect assembled from two contributors of different kinds: a derived projection (`identity-oidc.nix`, read-only OIDC endpoint data from `policy/identity.json` + the canonical web-policy route) and a runtime capability (`kanidm-host-auth.nix`, Kanidm client package + `services.kanidm.client`/`services.kanidm.unix` + PAM/SSH integration). The bundle forces the provider host to select a client capability to evaluate a derived value, makes consumer failures missing-option errors that a canonical requirement already forbids, and pins the Kanidm release family by convention in three places.

The fleet-level boundary rule this change applies (same rule that restructured backups and postgres): **same-host aggregation uses a declaration-only fragment imported by mechanism and participants; cross-host relationships are fleet-level policy consumed independently; runtime functionality is a placement aspect; projections, helpers, and package-family invariants are support machinery.** OIDC registration is cross-host: provider and application run in separate `nixosConfigurations` evaluations, so registration stays in `policy/identity.json` and is consumed from both sides — never a consumer registry.

## Goals / Non-Goals

- Goals:
  - The provider evaluates from its own selection plus policy, with no client capability selected.
  - A consumer host without the provider still resolves the projection; a consumer without any identity selection fails with a named assertion, not a missing option.
  - The remaining aspect is named for what it deploys: `kanidm-host-auth`.
  - One Kanidm release-family value; one OIDC URI derivation (`lib/policy.nix#mkOidcEndpoints`).
  - Applications own their OIDC wiring; hosts keep only credential bindings.
- Non-Goals:
  - No Kanidm consumer registry (cross-host composition is impossible at NixOS level; the flake-parts alternative couples provisioning to source presence).
  - No change to `policy/identity.json` structure, SOPS layout, or `.sops.yaml`.
  - No split of `tests/check-identity-contract-directionality.sh` (TD-11, separate follow-up).
  - No behavioural change to `services.identity.hostAuth` (PAM groups, SSH integration, assertions unchanged).

## Decisions

### D1. The projection is a fragment imported by its consumers (not a support aspect)

**Choice**: `modules/identity/identity-oidc.nix` stops publishing `flake.modules.nixos.identity-client` and becomes an intrinsic fragment: `options.services.identity.oidc` declarations plus the derivation, imported by `kanidm-runtime.nix`, `kanidm-host-auth.nix`, `paperless/core.nix`, `karakeep.nix`, `termix.nix` — the same shape as `modules/database/postgres/_consumer.nix` and `modules/backups/state-backups/_consumer.nix`.

**Alternative considered — a support-style contributor like `web-policy`**: rejected because `web-policy` is selected on every host by the fleet baseline, so its options exist everywhere by construction. The OIDC projection is needed only by identity participants; making it all-host would widen the surface for no reader, and the fragment form is already the repo's established pattern for exactly this need.

**Naming**: the fragment stays `modules/identity/identity-oidc.nix` (renaming the file adds churn with no information; the *aspect* name is what disappears). File path and option path stay aligned on `identity`.

### D2. `kanidm-host-auth` is the aspect name; `identity-client` is retired with no alias

**Choice**: `kanidm-host-auth.nix` publishes `flake.modules.nixos.kanidm-host-auth`; the two host records swap one selection line. No compatibility alias: the aspect surface is internal to this repository, both consumers are edited in the same change, and a silent alias would preserve the misleading name.

**Consequence**: the projection is no longer reachable through aspect selection at all. That is the point — but it makes D3's named failure the only failure mode for a consumer that forgets its import.

### D3. Consumers keep a named assertion; the missing-namespace failure is retired

With the fragment imported, `services.identity.oidc` always exists, so a missing client entry is now detectable: `clients.<name>` is absent when `providerUrl` is null (no provider configured) or the client is not enabled in policy. Consumers assert presence by name, e.g. `termix: required OIDC contract 'services.identity.oidc.clients.termix' is missing for host '…'` — the message `termix.nix` already throws, now guarding a real empty-case instead of an absent namespace.

**Placement of assertions**: in each consuming leaf (termix, paperless, karakeep), not in the projection. The projection cannot know which client a consumer needs; the consumer does.

### D4. The provider consumes the projection intrinsically; the dead mirror goes

`kanidm-runtime.nix` imports the fragment; the alignment assertion (`providerUrl == appUrl`) stays — it is a real cross-check between two independent resolutions of the same policy. The `services.identity.kanidm.oidc.*` mirror (`:389-393`) is deleted: zero readers in `modules/` or `tests/`, verified, and it exists only as a symptom of the old bundling.

`identity-provider.nix`'s header comment and the `identity-client` reference in its failure prose are updated; its selection requirement disappears because the fragment arrives with the leaf.

### D5. One Kanidm release-family value

`modules/identity/_kanidm-packages.nix` (value-imported helper, the `homepage/_data.nix` precedent):

```nix
# Kanidm release family: server wrapper and client tooling move together.
{
  server = pkgs.kanidmWithSecretProvisioning_1_11;
  client = pkgs.kanidm_1_11;
}
```

- The provider leaf sets `services.kanidm.package = family.server` and `environment.systemPackages = [ family.client ]`.
- The host-auth capability sets `services.kanidm.package = lib.mkDefault family.client` — `mkDefault` retained so a host can still override, per the existing leaf-default convention.
- Not an option, not an aspect: it is an implementation invariant. `_`-prefixed and value-imported, so discovery never sees it.
- The upgrade-gate requirement in `kanidm-identity` (`kanidmd domain upgrade-check` before bumping) is unchanged; the helper makes the bump one edit instead of three.

### D6. One URI derivation: `mkOidcEndpoints` becomes real

`lib/policy.nix:24` already defines `mkOidcEndpoints` (five canonical URIs from an issuer base) and `provider-owned-oidc-uris` requires it to be the single derivation. The projection's local `mkClientOidcEndpoints` is deleted; `mkClientOidcEndpoints clientId = mkOidcEndpoints "${clientPathPrefix}/${clientId}"` — the issuer base for client `id` is `…/oauth2/openid/<id>`, which is exactly the helper's input contract. Call-site logic becomes identical by construction, satisfying the spec instead of merely resembling it.

### D7. Application leaves own their OIDC wiring

`paperless/core.nix` and `karakeep.nix` gain `imports = [ ../../identity/identity-oidc.nix ]` (path depth per file) and take `clientId`/`wellknownUrl` from `config.services.identity.oidc.clients.<name>` in their own `let`. `modules/hosts/oci-melb-1/_nixos.nix` drops the four assignment lines (96-97, 135-136) and keeps `secretFiles.oidc` bindings only. `termix.nix` changes only its failure prose (`identity-client contract` → `OIDC contract`).

This is the direction `admin-module-structure` already requires; the change completes it for the two consumers still wired host-side.

### D8. Tests state the inverted contract

- Scaffold `7l-6` (currently asserts the missing-namespace failure) becomes: a host composition whose only identity participant is a consumer importing the projection evaluates successfully and resolves `clients.<name>`; a consumer leaf's named assertion fires when the client is absent from policy. The `host_leaf_imports_of` regex in the scaffold test is extended to include the projection import so a host re-importing it directly still trips the re-import guard.
- Directionality test additions (no restructure — TD-11 stays separate):
  - provider-only subset: `identity-provider` selected, `kanidm-host-auth` not, evaluates with `providerUrl` non-null and `services.identity.hostAuth.enable == false`.
  - projection-only probe: the fragment imported alone with a policy stub resolves client endpoints with no aspect selected (mirrors the backups `7i-5` fragment probe).
  - terminology: assertions and failure prose reference `kanidm-host-auth`, never `identity-client`.
- Existing ratchets (`identity-provider must not write services.identity.oidc.*`, the kanidm-admin catalog alignment) are preserved as-is.

## Risks / Trade-offs

- **[Aspect-name churn in specs/docs]** `identity-client` appears in four canonical specs and several docs → mitigated by updating them in this change (they are live descriptions of the surface); historical decision entries are annotated, not rewritten.
- **[Consumers must remember the import]** A new OIDC consumer that forgets the fragment import gets a missing-option error again → mitigated by the pattern now having three in-repo precedents (postgres, state-backups, identity) and by the scaffold re-import guard covering the projection.
- **[`mkDefault` package override retained]** A host could override the client package off the release family → accepted; it is the existing leaf-default convention and the family helper makes the default correct rather than forcing it.
- **[Both hosts edit selection in the same change]** `la-admin-1` and `oci-melb-1` swap `identity-client` → `kanidm-host-auth` atomically with the rename; a partial application fails evaluation loudly (unknown aspect), which is the desired failure mode.

## Migration Plan

1. Land the fragment conversion + rename + provider decoupling in one commit-set; host records swap selections in the same change.
2. Evidence: three host evals with aspect-count deltas exactly `{identity-client → kanidm-host-auth}`; provider-only and projection-only subset evals; scaffold + directionality + internal-contracts suites; `just checks all`, `nix flake check`.
3. Rollback: revert the change set; no secrets, policy data, or runtime state are touched, so rollback is purely evaluation-level.

## Open Questions

- None. Sequencing, scope, and the TD-11 boundary were decided with the operator; secret-layout migration is explicitly out of scope.
