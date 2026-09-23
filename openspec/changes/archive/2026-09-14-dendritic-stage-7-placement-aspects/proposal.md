## Why

Stage 6 established the right Dendritic source model, but hosts still import application, service, and provider implementations directly. Those imports keep placement split between `modules/flake/registry.nix` and host implementation files, leave `applications` and `providers` behind the migration filter, and make adding a deployed product inconsistent with adding the already-converted `music` or `dj` aspects.

**Core Value:** Complete the public placement surface so every deployed product and platform capability is selected as a named discovered aspect, hosts stop importing workload implementations, and future aspects can be added in parallel without reopening the high-level architecture.

## What Changes

- Add discovered deployment contributors for the remaining placement boundaries:
  - `oci` for OCI platform behavior.
  - `edge` for edge/origin ingress composition.
  - `cockpit` for independently placed Cockpit on OCI and LA.
  - `push-server` for LA's ntfy server.
  - `identity-provider` for Kanidm server/provisioning.
  - `admin-hub` for the coupled LA admin remainder (Termix, Vaultwarden, Homepage, Gatus, Beszel hub, Webhook, and current Quantum policy).
  - `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, and `phoenix` for OCI workloads.
  - `omniroute` for home-forge.
- Make aspect selection provide each product's top-level enablement while leaving real host variants explicit.
- Move `admin`, `edge`, and DJ implementation files from the evaluator-class `modules/applications/` root beside their concern owners under private `modules/flake/_<aspect>/` paths; preserve service option namespaces and runtime behavior.
- Move the OCI provider implementation beside the `oci` contributor; delete the evacuated `modules/providers/` root.
- Remove all direct `modules/applications/**`, `modules/providers/**`, and workload `modules/services/**` imports from host assemblies. The registry becomes the only placement list for this stage.
- Shrink the import-tree exclusion boundary from four roots to exactly `hosts` and `services` after `applications` and `providers` are genuinely evacuated.
- Strengthen the Dendritic scaffold contract so newly added host-facing workloads must publish a discovered aspect and be placed by explicit host selection.
- Harvest only the still-relevant Cockpit, edge, conventional-secret-default, and ownership findings from the superseded `normalize-fleet-boundaries` change; do not implement its unrelated topology/CI/ntfy/OIDC redesigns here.

### Constraints

- Behavior-preserving: no service, route, secret, permission, unit, package, backup, or deployment-topology change.
- No secret encryption/decryption, ciphertext edit, `.sops.yaml` edit, or recipient change.
- No flake input/lock change, deployment, or archive of other active changes.
- Preserve public option namespaces; this is placement/source conversion, not a service API migration.
- Keep independently placeable capabilities separate; do not replace explicit host selection with transitive aspect activation.
- Keep the Stage 8 host-discovery work out of scope: `registry.nix` may still enumerate concrete hosts after this change.
- Validation must not require privileged local binfmt changes or an unavailable cross-architecture builder: `la-admin-1` and `home-forge` use realized-output closure comparison, while `oci-melb-1` uses full evaluation, derivation, and structured-observable equivalence unless an aarch64 builder is available.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `feature-topology`: Every deployed host-facing product/platform capability is placed through explicit selection of a discovered deployment aspect; hosts no longer import workload implementations directly.
- `repository-structure`: The evacuated `applications` and `providers` roots leave the temporary discovery boundary, leaving only `hosts` and `services`; private implementations move beside their aspect owners.
- `fleet-infrastructure`: Typed host records select the complete placement aspect set while preserving host identity, machine facts, and current `nixosConfigurations` outputs.
- `admin-module-structure`: Admin composition moves from the evaluator-class application root into the discovered `identity-provider`, `cockpit`, and `admin-hub` concern owners without changing service contracts.
- `edge-proxy-ingress`: Edge/origin placement becomes selection of the discovered `edge` aspect while preserving canonical policy projection and route behavior.

Related specifications inspected: `admin-services`, `kanidm-identity`, `paperless-service`, `ai-gateway`, `karakeep-service`, `sovereign-binary-cache`, and `media-services`; their product behavior is unchanged, so they require no delta.

## Impact

- New/converted contributors under `modules/flake/` and concern-owned private paths for admin, edge, DJ, OCI provider behavior, and remaining workload leaves.
- `modules/flake/registry.nix` gains explicit per-host selections and loses raw workload/provider imports.
- `modules/hosts/{oci-melb-1,la-admin-1,home-forge}/` retain machine facts and product variants but lose implementation imports and redundant top-level enables.
- `modules/applications/` and `modules/providers/` are deleted after exhaustive ownership reconciliation; `modules/services/` remains the explicit incremental-conversion backlog.
- `modules/flake/_unconverted-nixos-dirs.nix` shrinks from four entries to two.
- `tests/check-dendritic-scaffold-contract.sh` and current architecture/convention documents are updated.
- No new packages, inputs, hosts, services, routes, secrets, or deploy targets.
