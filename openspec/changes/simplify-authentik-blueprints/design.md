# Design

## Context

See proposal.md for motivation. `modules/identity/authentik/_blueprint.nix` combines policy projection, static flow definitions, a custom YAML emitter and defensive checks. `blueprints.nix` installs the result beside upstream defaults. The worker reconciles it asynchronously. The focused identity suite mixes owned email-proof behaviour with literal configuration assertions.

The live OpenAPI document reports 2026.8.5 and no blueprint validate operation. The pinned `authentik/blueprints/api.py` exposes available/apply/import; import validates and then applies. `Importer.validate()` in `blueprints/v1/importer.py` performs model operations inside an always-rolled-back database transaction. The packaged `staticWorkdirDeps/blueprints/schema.json` describes resolved serializer values: tagged foreign keys need a narrow static-validation exemption.

## Goals / Non-Goals

Goals: preserve the accepted login and object identities; make source readable and validation release-coherent; fail deployment when the new blueprint cannot be applied. Non-goals: authentication UX changes, provider upgrades, a general blueprint framework, Kanidm removal, new credentials, API-based validation on a release that lacks it, or automatic production deployment.

## Decisions

### BD-1: Real YAML and one assembled document

Move `_enrollment.nix`, `_recovery.nix`, `_email-verification.nix`, `_passkeys.nix` and `_wording.nix` static entries into cohesive YAML files under an underscore-private asset directory. Put fixed claim expressions in YAML as well. Use block scalars for Python expressions and editor schema/tag configuration. Keep client/provider/application generation, groups/parent ordering, seed users, entitlements, route projection, brand values/CSS and credential associations in Nix. Supply background and enrollment settings through blueprint context where appropriate.

Build one `homelab-identity.yaml` using ruamel.yaml's tag-preserving node representation, explicit fragment order and the generated data. Retain IDs, identifiers, desired states and entry dependencies. Replace handwritten scalar/emit/block handling with library serialization; a small structured representation for generated tags is acceptable, not another encoder. Independent blueprints were rejected because shared stage references would introduce reconciliation ordering. No evaluation-time fetching or secret resolution.

### BD-2: Release schema with a minimal expression boundary

Use python-jsonschema and the schema in the selected Authentik package. Retain tagged nodes in the parsed data; defer validation only at expression nodes for tags used by the assembled document (initially KeyOf, Find, Context and Env as needed). Require known tags with appropriate argument shape; do not resolve them. Literal siblings, structural requirements and model discriminators must still be checked. Do not turn entire entries into unconstrained values or substitute dummy integer IDs. Unknown tags fail.

Prove the adapter against the existing document before conversion, particularly oneOf branch behaviour. Invalid literal enums and foreign keys must still fail alongside a valid tagged reference. Use explicit format checking where the schema declares it. Yamale would require another schema; Go/Rust parsers would still need the same semantic adapter. Editor tag recognition is not a guarantee of correct inferred result types.

### BD-3: Bounded systemd deployment gate using the pinned importer

Add a provider-owned oneshot to the activation-started systemd graph, using the selected Authentik management executable, its service configuration and runtime environment file. It must run after database provisioning/migrations and necessary Authentik startup, without a dependency cycle with the worker. Trigger it on document or relevant runtime changes, including secret-environment changes where they affect validation. Bound the entire unit with a start timeout; internal retries must also have a deadline.

Run `Importer.validate()` with the shipped content and context; a false result or exception exits nonzero. Do not call the import endpoint, which commits changes. Then use the existing blueprint mechanism to request/reconcile the shipped document and require both successful status and its applied hash matching the current bytes. Do not accept a successful status belonging to an earlier document. Check status for failure promptly rather than waiting out the timeout. On first boot, wait boundedly for required upstream default objects before declaring references invalid. Prevent concurrent reconciliation from making the dry-run/apply-status check ambiguous; use upstream facilities where available rather than adding a second provisioning owner.

The parent must verify with a negative activation test that NixOS/deploy-rs actually observes the nonzero unit result; a merely enabled unit or notification is insufficient. Importer validation can invoke model hooks despite DB rollback, so it is not described as universally side-effect-free. Emit a bounded, redacted failure summary, not imported attributes, environment values, or full serializer logs containing secrets. No API token and no public-edge readiness dependency.

### BD-4: Delete duplicated validation, retain owned behaviour

Drop the custom emitter's folding guard and schema/enum checks. Remove custom KeyOf ordering and duplicate-binding checks only once importer coverage is exercised. Delete assertions echoing stage counts/orders, configured username/passkey fields, theme/layout/CSS literals and similar assignments from `tests/check-identity-contract-directionality.sh`. Preserve independent client-contract isolation and Cloudflare federation agreement. Keep email-proof behavioural tests, adapting their input to real YAML; preserve narrow generator security contracts for seed ownership, undeclared groups, admission and privilege boundaries. Do not replace source-substring assertions with equivalent YAML snapshots.

## Risks / Trade-offs

- Tagged values bypass static field constraints -> the importer must reject missing references and bad resolved values before acceptance; test the exemption cannot hide invalid siblings.
- Conversion changes expression whitespace or identifiers -> compare parsed old/new documents with tags preserved as a one-time migration experiment, not a permanent snapshot suite.
- Asynchronous application races or missing defaults -> explicit reconciliation observation, current-document hash and bounded startup ordering.
- Deployment rollback does not undo already committed blueprint DB changes -> preserve behaviour and IDs; invalid documents must fail dry-run first; document the limit rather than promising database rollback with system rollback.
- New helper runs on two architectures -> use pinned nixpkgs Python dependencies, no separate package ecosystem or lockfile.

## Migration Plan

Implement and prove the static adapter; convert and compare documents; add and negatively exercise the deployment gate in an isolated environment; prune checks and update `docs/identity.md` plus operator-only validation/recovery steps. Parent runs expensive final gates and a bounded independent review. Production deployment needs separate approval. Preserve the existing secret/bootstrap gate: no runtime validation unit on a host where the provider is not provisioned. Reverting the source restores the old document and delivery mechanism, but any committed DB changes require their normal identity recovery procedure.
