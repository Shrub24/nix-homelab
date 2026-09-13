## Context

See `proposal.md` for motivation and the five delta specs for behavior contracts. After Stage 6, the repository has a sound flake-parts/deferred-module core and eleven host-selected deployment aspects, but placement is still split:

- `modules/flake/registry.nix` selects foundation, operational, identity, DJ, and music aspects.
- Host modules directly import or enable the remaining applications, provider behavior, and product services.
- `modules/applications/`, `modules/providers/`, `modules/hosts/`, and `modules/services/` remain excluded from discovery.

This stage closes the public placement surface without attempting the separate host-discovery conversion or the wholesale service-leaf conversion.

## Goals / Non-Goals

**Goals:**

- Make one explicit aspect selection the placement statement for every deployed product/platform capability.
- Remove direct application/provider/workload-service imports from hosts.
- Evacuate and delete `modules/applications/` and `modules/providers/`.
- Preserve all evaluated behavior and public option namespaces.
- Leave a clear, enforced ratchet for parallel addition of future aspects.

**Non-Goals:**

- Do not make host files discovered contributors; that is Stage 8.
- Do not eliminate the `services` or `hosts` discovery exclusions.
- Do not redesign product behavior, service APIs, topology, CI, ntfy publisher policy, OIDC metadata, Postgres roles, or secret readership.
- Do not split `admin-hub` further without a real placement difference.
- Do not adopt Den, flake-file, or a cross-repository fleet library.

## Decisions

### S7-1 — Exact baseline and behavior-equivalence gate

Capture a clean baseline at the completed Stage 6 JJ change before any implementation edit. Evaluate all three host toplevels from that exact tree. Realize `la-admin-1` and `home-forge` for literal closure comparison. `oci-melb-1` is `aarch64-linux`, while the available local and home-forge builders are `x86_64-linux` without aarch64 emulation; therefore its required gate is full drvPath/derivation and structured-observable equivalence. If a working aarch64 builder becomes available during validation, additionally realize OCI and run the literal closure comparison, but do not require sudo/binfmt mutation or deployment to create one. Structured observables cover imports/selections, services/units, routes, secrets/templates, users/groups, tmpfiles, firewall, packages, backups, boot/provider behavior, and all feature options moved by this stage.

The hard gate is value equality. Allowed realized-closure differences are limited to source provenance and derivation/store-path renames caused solely by relocating expressions. No product/runtime difference is accepted. For OCI, any unexplained derivation or structured-observable delta blocks completion just as an unexplained closure delta would.

**Why:** Stage 7 moves many owners but is intentionally behavior-free. The Stage 6 baseline method already proves this reliably.

**Alternative:** Rely only on `nix flake check`. Rejected because it proves evaluation, not equivalence.

### S7-2 — Aspect surface follows current independent placement

Publish these discovered aspects:

| Aspect | Current placement | Intrinsic implementation |
|---|---|---|
| `oci` | OCI only | OCI serial console and provider boot defaults |
| `edge` | OCI origin + LA edge | edge application and proxy leaf; role stays host-set |
| `cockpit` | OCI + LA | Cockpit leaf and common service-user secret registration; host-specific URL/transport variants remain explicit |
| `push-server` | LA only | ntfy server |
| `identity-provider` | LA only | Kanidm server, OIDC provisioning, identity secrets |
| `admin-hub` | LA only | Termix, Vaultwarden, Homepage, Gatus, Beszel hub, Webhook, Quantum policy, shared admin-root wiring |
| `paperless` | OCI only | Paperless plus GPT/docling composition |
| `postgres` | OCI only | shared PostgreSQL provider and current role enables |
| `ai-gateway` | OCI only | Bifrost gateway |
| `karakeep` | OCI only | Karakeep |
| `niks3-cache` | OCI only | niks3 server (distinct from fleet-wide cache consumer/backups behavior) |
| `phoenix` | OCI only | Phoenix service |
| `omniroute` | home-forge only | OmniRoute service |

Selection supplies the existing top-level enable. Genuine variants remain host-set. Capabilities remain separate when they already differ in placement (`cockpit` versus `admin-hub`, `identity-provider` versus `identity-client`, `niks3-cache` versus `backups`).

**Why:** These boundaries are observable in the current three-host placement matrix. They avoid both one-aspect-per-file ritual and a single host-role mega-aspect.

**Alternative:** `oci-workloads` and `la-admin` mega-aspects. Rejected because they obscure meaningful independent placement already demonstrated by Cockpit, edge roles, identity clients, and future workload moves.

### S7-3 — Concern owners may have multiple discovered contributors

Each normal feature source file becomes a discovered flake-parts contributor. Several files may merge into one `flake.modules.nixos.<aspect>` value where they share placement, following `identity-client`. A central `admin-hub.nix` may own shared composition while separate normal contributors can add their service-owned portion to `admin-hub`; no central source-file registry is introduced.

Private implementation files and non-Nix assets live beside the concern under underscore paths, for example:

```text
modules/flake/edge.nix
modules/flake/_edge/...
modules/flake/admin-hub.nix
modules/flake/_admin-hub/...
modules/flake/dj.nix
modules/flake/_dj/...
modules/flake/oci.nix
modules/flake/_oci/...
```

Exact filenames may follow ownership discovered during inventory, but the public aspect names and placement matrix are fixed.

**Why:** This applies the established D-050 source/granularity split and makes parallel contributors merge safely.

**Alternative:** One giant file per aspect. Rejected for admin and other multi-service concerns because it erases source ownership.

### S7-4 — Applications root is fully evacuated

- Move `modules/applications/admin/default.nix` into the `identity-provider`/`cockpit`/`admin-hub` concern ownership split. Shared `/srv/data` ACL/reconcile and admin SSH identity wiring belong to `admin-hub` unless inventory proves a narrower owner.
- Move `modules/applications/edge-ingress.nix` beside `edge` and preserve its public `applications.edge-ingress.*` namespace.
- Move `modules/applications/dj/{default.nix,engine-dj.nix}` beside `dj`; preserve the Stage 6 music contract and frozen worker behavior.
- Delete `modules/applications/` only after every line and asset has one owner and host evaluations match.

**Why:** Keeping a class-oriented application root after every application has a discovered concern owner would preserve the transitional taxonomy as an endpoint.

### S7-5 — Provider root becomes the `oci` concern

Convert `modules/providers/oci/default.nix` into the discovered `oci` contributor or a private leaf owned by it, selected only on OCI. Preserve serial console, GRUB device, and all provider-specific behavior. Delete `modules/providers/` once empty.

**Why:** Provider behavior is a host-selected capability just like other aspects; it need not retain a separate evaluator-class discovery root.

### S7-6 — Hosts retain facts and variants, not implementation imports

Registry records gain the aspect selections. Host modules retain:

- hostname, hardware/facter and disk facts;
- `fleet.foundation` / `fleet.networking` facts;
- role or feature variants such as edge role, data roots, model aliases, Postgres consumer enables, and explicit secret-source overrides not yet derivable safely;
- host-local implementation fragments (disko and genuine overlays) imported from within the host directory.

They must not import `modules/applications/**`, `modules/providers/**`, or workload `modules/services/**`. Host-local overlays that merely enable or project an aspect are folded into the owner; overlays containing genuine host data remain host-private.

**Why:** Stage 8 can then convert hosts mechanically without first untangling placement again.

### S7-7 — Conventional defaults are harvested narrowly

Where a host repeats a value that the selected aspect can derive without ambiguity—especially the conventional `secrets/hosts/<networking.hostName>/system.yaml`, `secrets/common.yaml`, or stable catalog projection—move that default into the owner and preserve an explicit override option. Do not alter `.sops.yaml` or any ciphertext.

Harvest only the edge/Cockpit/default-ownership items needed to remove direct imports. Defer `normalize-fleet-boundaries` topology, CI generation, ntfy publisher, OIDC registry, adopted-host, and broad test-hygiene work.

**Why:** This avoids carrying obvious host wiring into Stage 8 while preventing Stage 7 from becoming the superseded cross-cutting cleanup.

### S7-8 — Filter shrinks from four roots to two

After `applications` and `providers` are absent, update `_unconverted-nixos-dirs.nix` to exactly:

```nix
[
  "hosts"
  "services"
]
```

`hosts` stays excluded until Stage 8. `services` stays as the incremental migration backlog. Do not replace removed roots with underscore-renamed equivalents.

### S7-9 — Scaffold contract becomes the architectural ratchet

Extend `tests/check-dendritic-scaffold-contract.sh` to prove:

- the exact public aspect set and exact per-host selections;
- every deployed product/platform capability is selected by an aspect;
- hosts contain no direct application/provider/workload-service imports;
- only the owning concern imports each private implementation;
- discovery alone is inert on non-selected hosts;
- the filter is exactly `hosts` + `services` and both removed roots are absent;
- negative mutations detect a direct host leaf import, missing aspect selection, accidental aspect activation, private-leaf publication, and reintroduced compatibility root.

Every semantic mutation evaluates the full host toplevel.

### S7-10 — Stage boundary and completion criterion

Stage 7 completes when `applications` and `providers` are gone, all current deployed products have named placement aspects, and hosts import no workload implementations. It does not declare the full Dendritic transition complete: Stage 8 still makes hosts discovered contributors and removes `hosts` from the filter.

After Stage 8, leaving only `services` filtered is an accepted stopping point; service leaves convert opportunistically when changed or independently placed.

### S7-11 — Overlap and strict scope

Active changes overlap Paperless, OmniRoute, and the playlist/Traktor area. Re-pin current protected bodies before implementation. Stage 7 may move those bodies without changing them, but must not absorb behavior from `open-webui`, `omniroute-home-forge`, `navidrome-m3u-itunes-worker`, or `traktor-m3u-sync-worker`. If an overlapping change lands first, rebase and recapture the Stage 7 baseline rather than resolving by dropping its behavior.

No deployment or OpenSpec archive occurs during apply.

## Risks / Trade-offs

- **[Large placement matrix causes merge conflicts]** → Convert in independently evaluable groups; one writer per shared tree; rebase before touching active-overlap files.
- **[Selection-owned enablement changes option availability]** → Defensive contract reads and non-selected-host full-toplevel mutations; preserve safe defaults where cross-aspect reads exist.
- **[Admin split creates hidden dependencies]** → Keep policy co-selection explicit and add named assertions only for real required contracts; do not import sibling public aspects.
- **[Relocation changes relative paths/store provenance]** → Recompute paths mechanically, compare structured values, and classify every closure delta.
- **[Secret defaults widen access or break two-step bootstrap]** → Path derivation only; no ciphertext/readership edits; retain path-existence gates and explicit overrides.
- **[Aspect explosion]** → One aspect per real placement boundary, not per module file; keep coupled admin remainder as `admin-hub`.
- **[Stopping with `services` filtered is seen as incomplete]** → Document it as the explicit incremental backlog and enforce no new direct host imports.

## Migration Plan

1. Rebase after Stage 6 and overlapping worker changes as required; capture the exact clean Stage 6 baseline.
2. Inventory all host imports, enables, option overrides, application/provider bodies, and direct service placement.
3. Convert platform/edge/Cockpit/push-server first and evaluate OCI/LA.
4. Split admin into identity-provider/admin-hub contributors and preserve current composition.
5. Convert OCI product aspects and home-forge OmniRoute.
6. Relocate DJ private implementation; remove remaining direct host imports.
7. Delete evacuated roots and shrink the filter to `hosts` + `services`.
8. Update scaffold mutations and D-053/current docs.
9. Evaluate all hosts; build and run literal closure diffs for LA and home-forge; run OCI derivation plus structured-observable equivalence (and a literal closure diff only if an aarch64 builder is available); then run strict OpenSpec validation and independent review.

Rollback is the clean Stage 6 JJ change. No secret or deployed state changes, so reverting the Stage 7 change restores the prior source composition.
