## Context

See `proposal.md` for motivation. The deployed Stage 4 baseline (parent change `rvrvopyv`, commit `6a824851`) leaves two legacy evaluator-class roots on the exclusion boundary: `modules/shared/` (seven plain leaves — four private implementation leaves imported by their aspect owners, and three directly imported modules: `web-policy` on all hosts, `kanidm-host-auth` on OCI/LA, `identity-oidc` on OCI and the admin application) and `modules/storage/` (two zero-consumer disko templates). The six-entry import-tree filter cannot shrink until both roots empty, and D-050's "several source modules may contribute to one coherent aspect" claim still has no production instance.

The design must preserve deployed Stage 4 behavior exactly while emptying both roots, proving the multi-contributor single-aspect merge, and shrinking the filter to its four genuine unconverted roots.

## Goals / Non-Goals

**Goals:**

- Delete both zero-consumer storage templates; keep only host-local disko layouts.
- Empty and remove `modules/shared/` with no default or wrapper contributor.
- Relocate private implementation leaves beside their aspect owners under underscore-private paths.
- Convert `web-policy.nix` into a discovered infrastructure-support contributor selected by all three hosts.
- Prove the collector pattern: two separately discovered contributors merge into one `identity-client` deployment aspect.
- Shrink the import-tree filter from six to exactly four entries (`applications`, `hosts`, `providers`, `services`).
- Update the scaffold contract semantically: publication sets, per-host selections, private owners, contributor merge, and negative mutations.
- Reconcile canonical docs and record D-051.

**Non-Goals:**

- Convert the `applications`, `hosts`, `providers`, or `services` roots.
- Publish new aspects for the relocated private leaves.
- Redesign identity, admin, edge-ingress, host overlays, music/DJ, or product behavior.
- Change secrets, `.sops.yaml`, policy contents, routes, topology, flake inputs, or deployment targets/order.
- Rewrite active changes' stale OpenSpec references or touch archived artifacts.

## Decisions

### S5-1 — Baseline is the deployed archived Stage 4 change

The comparison baseline is the deployed, archived Stage 4 change at parent `rvrvopyv` / commit `6a824851`. Capture it reproducibly before any edit: build each host toplevel from the baseline commit, record the deployed generation per host, and capture the structured observable snapshot for every explicit probe. The hard gate is structured observable equality against those captures. `nix-diff` and `nix diff-closures` output is additionally captured as review evidence and compared against an explicit provenance-only allowlist: differences attributable solely to relocating or nesting source expressions (derivation/store-path renames, and comment or source-order changes) are permissible; any difference in runtime services/units, enabled options, secret paths, secret readership, endpoints, packages, users, filesystems, timers, activation scripts, topology, or recovery behavior blocks completion until explained by provenance.

### S5-2 — Delete the zero-consumer storage templates

`modules/storage/disko-root.nix` and `modules/storage/disko-single-disk.nix` have no consumers. Delete both; host-local layouts remain untouched: `modules/hosts/oci-melb-1/disko-single-disk-split.nix` and `modules/hosts/home-forge/disko-two-disk.nix` (LA is a preinstalled-NixOS adoption with no disko layout). The empty `modules/storage/` directory is removed.

### S5-3 — Empty `modules/shared/` with no default or wrapper

No default or wrapper contributor is created for the relocated private leaves. Each moves beside its current aspect owner under an underscore-private path (import-tree underscore semantics keep them out of discovery, matching the existing `_aspects/` pattern). Content, semantics, and merge priorities are preserved except for the relative-read adjustment each move actually requires:

- `host-recovery.nix` → `modules/flake/_aspects/host-recovery.nix` (base aspect owner; `_aspects/base.nix` import updated `../../shared/host-recovery.nix` → `./host-recovery.nix`). The leaf lands beside the existing `_aspects/` source leaves and has no relative repo reads, so no path adjustment is required.
- `niks3-upload-client.nix`, `niks3-post-deploy.nix` → `modules/flake/_backups/` (backups aspect owner; `backups.nix` imports updated `../shared/...` → `./_backups/...`). This move is one directory level deeper, so `niks3-upload-client.nix`'s conventional secret read is adjusted `../../secrets/hosts` → `../../../secrets/hosts`; `niks3-post-deploy.nix` has no relative repo read, so no other body change.
- `nixbuild-ssh.nix` → `modules/flake/_builder-access/nixbuild-ssh.nix` (builder-access aspect owner; `builder-access.nix` import updated `../shared/nixbuild-ssh.nix` → `./_builder-access/nixbuild-ssh.nix`). The leaf has no relative repo reads, so no path adjustment is required.

No new `flake.modules.nixos.<name>` publication is introduced for any of them. The choice of `_aspects` (foundation), `_backups`, and `_builder-access` is the recorded private-path convention (S5-9) and must not be normalized or reorganized later without a new decision.

### S5-4 — `web-policy.nix` becomes a discovered support contributor

`modules/flake/web-policy.nix` becomes a normal top-level discovered contributor publishing `flake.modules.nixos.web-policy`, classified as an infrastructure support module alongside `provenance`, `oci-images`, and `fleet-packages` — not a deployable edge capability. The existing `repo.web` options and resolved policy data are preserved exactly; only the publication shell is added (`modules/shared/web-policy.nix` → `modules/flake/web-policy.nix` keeps the same directory depth, so its `../../lib/policy.nix` and `../../policy/web-services.nix` reads are unchanged).

All three registry host records select `aspects.web-policy` because the notification-daemon on home-forge reads `repo.web`: `services.notification-daemon.ntfy.serverUrl` defaults to `config.repo.web.catalog."ntfy-admin".publicUrl`, and forge sets no override. The direct `../../../modules/shared/web-policy.nix` imports are deleted from all three host default files.

### S5-5 — Identity is the collector proof

Two separately discovered top-level files each contribute to the SAME `flake.modules.nixos.identity-client` deployment aspect — the first production instance of D-050's multi-contributor single-aspect merge. Each file is the discovered contributor itself, and its existing NixOS option/config body is nested directly inside its `flake.modules.nixos.identity-client` definition. There are no `_identity-client/` private leaves, no central `identity-client.nix` wrapper, and no cross-contributor import:

- `modules/flake/identity-oidc.nix` publishes `flake.modules.nixos.identity-client` and nests the OIDC options/config body. Its `../../policy/identity.json` read is unchanged (same directory depth).
- `modules/flake/kanidm-host-auth.nix` publishes `flake.modules.nixos.identity-client` and nests the host-auth options/config body. It has no relative repo read.

Content, semantics, and merge priorities of both bodies are preserved. The host-auth body reads `config.services.identity.oidc.providerUrl` through config (optional integration within the merged aspect), never through an import. flake-parts merges both contributors into the single selected aspect; deleting either contributor removes its own OIDC or host-auth/Kanidm options and config from that merge.

Registry: `oci-melb-1` and `la-admin-1` select `aspects.identity-client`; `home-forge` does not. Delete admin's direct `../../shared/identity-oidc.nix` import (`modules/applications/admin/default.nix`) and the host direct imports of `../../../modules/shared/{identity-oidc,kanidm-host-auth}.nix`. Host-owned values are preserved exactly: OCI's `identity.oidc.providerUrl` from `config.repo.web.catalog."kanidm-admin".publicUrl` and LA's providerUrl via the admin application's `policyServices` both resolve to the same policy-derived `https://id.shrublab.xyz`, and both hosts' `identity.hostAuth` blocks and all client/secret wiring are unchanged.

### S5-6 — Shrink the filter to exactly four entries

`modules/flake/_unconverted-nixos-dirs.nix` removes `shared` and `storage`, leaving exactly `applications`, `hosts`, `providers`, `services`. Both directories must be deleted (root evacuation), not merely unlisted — a fake shrink that removes an entry while the directory still exists must fail. The scaffold test's `discovered_contributors` exclusions for `*/shared/*` and `*/storage/*` are removed with them.

### S5-7 — Update the scaffold contract semantically

The contract moves from 12 to 14 publications: the support quartet (`provenance`, `oci-images`, `fleet-packages`, `web-policy`) plus ten deployment aspects (`base`, `shell`, `networking`, `tailscale`, `notify`, `backups`, `builder-access`, `observability-agent`, `dj`, `identity-client`). Per-host selections are exact sets: OCI and LA select the support quartet + eight foundation/operational aspects + `identity-client`; home-forge selects the support quartet + eight + `dj` and never `identity-client`.

Private-owner checks cover `_aspects/host-recovery.nix`, `_backups/*`, and `_builder-access/*`: underscore-private, not discovered, no publications. Identity is no longer a private path; its two contributors are discovered and publish the shared aspect. The contributor merge is proven by deleting either identity contributor and detecting the missing OIDC or host-auth/Kanidm observable/eval — not by a missing publication, because the sibling contributor still defines the `identity-client` publication. Discovery-without-selection is proven inert by forge evaluating with `services.identity` absent (probed via `(services.identity or {})`); the filter fake shrink is rejected by the root-evacuation check. Filename/order overfit is avoided except for the paths needed to enforce root evacuation (`modules/shared` and `modules/storage` must not exist).

The concrete scaffold-contract edits are enumerated so the contract update is auditable:

- check 1: the six-entry filter literal becomes exactly `["applications","hosts","providers","services"]`; the per-root existence loop drops `shared`/`storage`; add `test ! -e modules/shared` and `test ! -e modules/storage` root-evacuation assertions.
- `discovered_contributors`: remove the `*/shared/*` and `*/storage/*` exclusions.
- 7a publication set: 12 → 14 (add `web-policy` and `identity-client`); update the "support trio" wording and extend the private-owner non-publication scan to `_backups`/`_builder-access`.
- 7b selections: support trio → support quartet (`+ aspects.web-policy`); regular set (`OCI`/`LA`) adds `aspects.identity-client`; forge set stays support quartet + eight + `dj`.
- 7g relocated leaf inventory: replace `modules/shared/{niks3-upload-client,niks3-post-deploy,nixbuild-ssh}.nix` with `modules/flake/_backups/...` and `modules/flake/_builder-access/nixbuild-ssh.nix`; update the owner-import greps to `./_backups/...` and `./_builder-access/...`.
- 7g `filterPackage`/`type = lib.types.package`/`config.repo.packages` greps: retarget `modules/shared/niks3-post-deploy.nix` to `modules/flake/_backups/niks3-post-deploy.nix`.
- 7g upstream import check: narrow `grep -Rn 'niks3-auto-upload' modules/flake` to the exact `inputs.niks3.nixosModules.niks3-auto-upload` import so the relocated post-deploy leaf's `config.services.niks3-auto-upload` option mention does not false-positive.
- `host_leaf_imports_of`: retarget the pattern to `modules/services/{state-backups,beszel-agent-auth}.nix` and `modules/flake/{_backups/{niks3-upload-client,niks3-post-deploy},_builder-access/nixbuild-ssh}.nix` so the check is non-vacuous against the new private paths.
- 7j re-import mutation: anchor the inserted import on a host import line that survives this change (not the deleted `modules/shared/web-policy.nix` line) and insert a new private leaf path so `host_leaf_imports_of` is exercised.

### S5-8 — Explicit observables

- `config.repo.web` JSON (`hosts`, `catalog`, `currentHost`) evaluates on all three hosts.
- `services.notification-daemon.ntfy.serverUrl` resolves on all hosts: the `repo.web`-derived default on OCI and forge, LA's explicit `http://127.0.0.1:2586` preserved.
- Identity on OCI and LA: `services.identity.oidc.providerUrl` pinned to the policy-derived `kanidm-admin` public URL (`https://id.shrublab.xyz`, from `config.repo.web.catalog."kanidm-admin".publicUrl` on OCI and the admin application's `policyServices` on LA), the policy-derived `clients` set, `services.identity.hostAuth.enable = true`, and `services.kanidm.client.settings.uri` equal to providerUrl. On forge: `services.identity` absent — probed through `(c.services.identity or {})` so the evaluation succeeds; no oidc, no hostAuth, no kanidm client.
- Recovery: `systemd.services.host-recovery-reboot` and `systemd.timers.host-recovery-reboot` present on all hosts via the base aspect.
- Builder: `programs.ssh.knownHosts.nixbuild.hostNames = ["eu.nixbuild.net"]` and the `extraConfig` trust block on all hosts.
- niks3: `services.niks3-auto-upload` enable/serverUrl (OCI loopback `http://127.0.0.1:5751`, others `http://oci-melb-1:5751`), `services.niks3-post-deploy.enable` with `filterPackage` = the injected `nix-path-filter` package, `services.niks3.enable` only on OCI.
- Package/deploy/Tailscale/notify/backups/secrets probes unchanged: package output keys, deploy nodes/`edgeHost`/`deployOrder`, Tailscale MTU/auth-key, notify daemon/notify packages, backups bucket/secret path, sops secrets.
- All three host toplevels build and match the Stage 4 structured observable snapshot. `nix-diff` / `nix diff-closures` output is reviewed against the provenance-only allowlist; any unexplained runtime/observable delta blocks completion.

### S5-9 — Reconcile docs and record D-051

Record D-051 in `docs/decisions.md` and reconcile `STRUCTURE.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `openspec/config.yaml`, `docs/architecture.md`, `docs/plan.md`, `docs/context-history.md`, and `docs/dendritic-transition-analysis.md` with the exact post-change structure: `modules/shared/` and `modules/storage/` removed, the filter at four entries, `web-policy` classified as infrastructure support, `identity-client` as the first multi-contributor single-aspect merge (two discovered contributors with inline nested NixOS bodies and no `_identity-client/` private leaves), and private leaves relocated beside their aspect owners. D-051 explicitly supersedes only D-050's deferral clause for `web-policy` and `identity-client` (`music` remains deferred) and records the private-path convention (`_aspects` foundation, `_backups`, `_builder-access`) so it is not normalized away later. Zero files under `openspec/changes/archive/` change. Active changes that reference the old `modules/shared/` paths (`normalize-fleet-boundaries`, `open-webui`) retain their stale references; their artifacts are not rewritten in this change.

### S5-10 — Scope exclusions

No edits to edge-ingress, host edge/cockpit/quantum overlays, admin leaf redesign, music/DJ, product/service behavior, policy contents, routes, topology, flake inputs, or deployment targets/order. No new flake input, no `specialArgs`, no compatibility bus, no accidental activation.

## Risks / Trade-offs

- **Move-relative paths break silently** → Relocation changes directory depth: `host-recovery` and `nixbuild-ssh` have no relative repo reads and move unchanged, while `niks3-upload-client` moves one level deeper and must change `../../secrets/hosts` to `../../../secrets/hosts`. Update each owner import (and that one read) in the same change as its leaf move and gate on the full host evals.
- **Accidental web-policy omission on forge** → If `aspects.web-policy` is dropped on forge, the ntfy `serverUrl` default cannot resolve. The all-host web-policy selection and the ntfy server URL are explicit contract probes.
- **Direct identity import on LA via admin** → The old `../../shared/identity-oidc.nix` path hard-fails after deletion, so it cannot silently survive; but a re-pointed import to the new contribution file, or any direct import of a future identity leaf, could silently merge OIDC options into LA a second time. The contract therefore forbids ANY direct `identity-oidc`/`kanidm-host-auth` import outside the two owning top-level contributors, independent of any merge-failure assumption.
- **Import-tree discovery of a leaked leaf** → A plain leaf left in the four remaining roots fails evaluation loudly; underscore semantics keep private leaves out of discovery.
- **Active changes hold stale paths** → `normalize-fleet-boundaries` and `open-webui` reference `modules/shared/` paths; they are not rewritten and cannot collide with this change's new files.
- **Archive history references deleted paths** → Historical archives name `modules/shared/` and `modules/storage/`; they are historical records and remain byte-identical.

## Migration Plan

1. Capture the deployed Stage 4 baseline (parent `rvrvopyv` / `6a824851`): build each host toplevel, record deployed generations and the structured observable snapshots, and save `nix-diff` / `nix diff-closures` evidence for provenance review.
2. Delete the two storage templates; remove `modules/storage/`.
3. Relocate the three private leaves to `_aspects/`, `_backups/`, `_builder-access/`; update owner imports in `_aspects/base.nix`, `backups.nix`, `builder-access.nix`; adjust the niks3-upload-client secret read to `../../../secrets/hosts`.
4. Convert `web-policy.nix` and the two identity contributors; nest the identity option/config bodies directly inside the two top-level contributors (no `_identity-client/` leaves); update the registry selections; delete host and admin direct imports.
5. Shrink the filter to four entries; update the scaffold contract (publications, selections, private owners, negative mutations, root evacuation).
6. Reconcile canonical docs and record D-051; leave archives and active stale refs untouched.
7. Run formatting, focused/full checks, all host evaluations, structured comparison, and `nix diff-closures`.
8. Obtain independent architecture review and strict OpenSpec validation.

Rollback is the parent Stage 4 JJ change (`rvrvopyv`). No deployment is part of this change; deployment follows the established per-stage operator gate.