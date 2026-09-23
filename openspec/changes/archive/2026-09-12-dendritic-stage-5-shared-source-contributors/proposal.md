## Why

Stage 4 separated feature-owned source contributors from deployment aspects but left two legacy evaluator-class roots on the exclusion boundary: `modules/shared/` (a mixed bag of already-private implementation leaves and direct host-imported modules) and `modules/storage/` (zero-consumer disko templates). `modules/shared/` also hides auto-discovery-ready features behind direct host imports, so the repo cannot prove D-050's source/deployment separation until those leaves become top-level contributors.

**Core Value:** Remove two obsolete evaluator-class roots cleanly while preserving deployed Stage 4 behavior and proving that several source contributors can merge into one deployment aspect.

## What Changes

- Delete zero-consumer `modules/storage/disko-root.nix` and `modules/storage/disko-single-disk.nix`; host-local layouts (`disko-single-disk-split.nix`, `disko-two-disk.nix`) remain untouched.
- Empty and remove `modules/shared/`:
  - Relocate private implementation leaves beside their current aspect owners under underscore-private concern paths and update owner imports:
    - `host-recovery.nix` -> `modules/flake/_aspects/host-recovery.nix` (base aspect owner; `_aspects/base.nix` import updated).
    - `niks3-upload-client.nix`, `niks3-post-deploy.nix` -> `modules/flake/_backups/` (backups aspect owner; `backups.nix` imports updated).
    - `nixbuild-ssh.nix` -> `modules/flake/_builder-access/nixbuild-ssh.nix` (builder-access aspect owner; `builder-access.nix` import updated).
- Convert `web-policy.nix` into auto-discovered contributor `modules/flake/web-policy.nix` publishing `flake.modules.nixos.web-policy`, an infrastructure-support NixOS module carrying the existing `repo.web` options/defaults. It is not a deployable edge capability; it is selected on all three hosts because notification defaults and host policy consume `config.repo.web`.
- Convert `identity-oidc.nix` and `kanidm-host-auth.nix` into TWO separately discovered top-level contributors (`modules/flake/identity-oidc.nix`, `modules/flake/kanidm-host-auth.nix`) whose existing NixOS option/config bodies are nested directly inside their `flake.modules.nixos.identity-client` definitions — no `_identity-client/` private leaves, no central wrapper, no cross-import. Both contributors merge into the single `flake.modules.nixos.identity-client` deployment aspect. Select `aspects.identity-client` on OCI and LA only; delete admin's direct `../../shared/identity-oidc.nix` import.
- Remove the direct `web-policy` / `kanidm-host-auth` / `identity-oidc` imports from host default files; registry records gain `aspects.web-policy` (all three) and `aspects.identity-client` (OCI, LA).
- Shrink `_unconverted-nixos-dirs.nix` exactly 6 -> 4 by removing only `shared` and `storage`; `applications`, `hosts`, `providers`, `services` remain.
- Preserve every role/domain/client/secret value and all evaluated behavior behind the same `flake.modules.nixos.<name>` contract.

### Constraints

- No edits to `.sops.yaml`, `secrets/**`, edge-ingress, host edge/cockpit/quantum overlays, admin leaf redesign, music/DJ, product/service behavior, policy contents, routes, topology, flake inputs, or deployment targets/order.
- No `_identity-client/` private leaves, no central identity wrapper, no direct identity-contributor import outside the discovery tree, no `specialArgs`, no compatibility bus, no accidental activation, no new flake input.
- Active changes retain stale refs but no code collision; their artifacts are not rewritten in this change.
- Stage 4 is the deployed comparison baseline; unexplained evaluated or runtime differences are blocking.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `repository-structure`: Generalize the temporary-boundary shrink scenario beyond the historical `core`/`profiles` roots so it covers this stage's removal of `shared` and `storage`, and affirm that relocated private implementation leaves sit in underscore-prefixed paths owned by their aspect.
- `fleet-infrastructure`: Extend the explicit-selection/classification contract for the new placement semantics: `identity-client` is a host-selected deployment aspect composed from two top-level source contributors (OCI + LA), and `web-policy` is classified as an all-host infrastructure-support module rather than a deployable edge capability.
- `feature-topology`: Inspected — no delta. The multi-contributor single-aspect merge is already required by "Feature source ownership SHALL be independent of deployment granularity"; this stage is its first production instance.

## Impact

- Primary code: delete `modules/storage/*` and `modules/shared/` entries; new `modules/flake/web-policy.nix`, `identity-oidc.nix`, `kanidm-host-auth.nix`, `_backups/*`, `_builder-access/*`, relocated `_aspects/host-recovery.nix`; owner import and registry updates in `modules/flake/backups.nix`, `builder-access.nix`, `_aspects/base.nix`, `registry.nix`; host import removal in `modules/hosts/{oci-melb-1,la-admin-1,home-forge}/default.nix`; admin import removal in `modules/applications/admin/default.nix`. The niks3 leaves move one directory deeper, so `niks3-upload-client.nix` adjusts its conventional secret read `../../secrets/hosts` -> `../../../secrets/hosts`; host-recovery and nixbuild-ssh have no relative repo reads.
- Contracts: `tests/check-dendritic-scaffold-contract.sh` (filter six -> four plus root-evacuation, relocated-leaf inventory paths and owner imports, 14-publication set, per-host selection sets, private-owner checks, and the concrete edits enumerated in design S5-7) and the three canonical capabilities named above.
- Docs: `STRUCTURE.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `openspec/config.yaml`, `docs/{architecture,decisions,plan,context-history,dendritic-transition-analysis}.md`; D-051 explicitly supersedes only D-050's deferral clause for web-policy and identity-client (music stays deferred).
- Verification: `nix build` each host top-level. The hard gate is structured observable equality against the deployed archived Stage 4 captures (web, identity, recovery, builder, niks3, packages, deploy, Tailscale, notify, backups, secrets). `nix-diff` and `nix diff-closures` evidence is reviewed against an explicit provenance-only allowlist (store/derivation-path and source-order differences caused solely by relocating or nesting expressions); any unexplained runtime delta blocks completion. Explicit probes: web (`config.repo.web` defaults on all hosts), identity (`services.identity.oidc`/`services.identity.hostAuth` on OCI + LA; `services.identity` absent on forge, checked via `(services.identity or {})`), recovery (`hostRecovery` via base aspect), builder (nixbuild SSH trust), niks3 (upload client + post-deploy via backups aspect).
- No new flake inputs, packages, runtime services, secrets, routes, or deploy targets.