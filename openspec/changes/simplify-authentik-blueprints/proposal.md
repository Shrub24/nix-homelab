# Proposal

## Why

Authentik flows are currently Nix data rendered by a handwritten YAML emitter, and custom checks duplicate parts of upstream validation while rejected blueprints can leave activation looking successful. Core Value: keep the working identity behaviour reproducible while making blueprint authoring simpler and provisioning failures visible to deployment.

## What Changes

- Author static flows, stages, prompts, bindings and expression policies as real YAML; retain fleet-derived registrations and context in Nix.
- Assemble one document with ruamel.yaml, removing the handwritten YAML emitter.
- Validate literal values with python-jsonschema against the schema shipped by the pinned Authentik package. A minimal adapter defers explicitly supported tagged expressions without resolving them.
- Add bounded deployment-time importer validation and confirmation that the shipped blueprint was successfully applied.
- Remove schema reimplementations and configuration-echo assertions; retain owned policy behaviour and independent integration contracts.
- Preserve object identity, login behaviour, route placement, secret delivery and database ownership. Kanidm retirement is outside this change.

## Capabilities

### New Capabilities

- `authentik-blueprint-delivery`: reproducible blueprint assembly, release-matched structural validation and fail-visible deployment acceptance.

### Modified Capabilities

None. This complements the pending `authentik-identity` capability in `migrate-identity-to-authentik`, particularly AI-5, without replacing its authentication or authorization requirements. The existing `provider-owned-oidc-uris` capability is unaffected.

## Impact

`modules/identity/authentik/`, the focused identity checks, flake check registration, and `docs/identity.md`. Build helpers use pinned nixpkgs Python packages; runtime validation uses the selected Authentik management environment. Supports both fleet architectures and is realized only where Authentik is selected and provisioned. No encrypted secret edits, API tokens, public-edge dependency, live deployment or database migration is included in implementation approval.
