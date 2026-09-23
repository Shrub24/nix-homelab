## Context

`identity-provider` reads `applications.admin`, while `admin-hub` writes Kanidm options imported only by the provider. The provider also writes the identity-client provider URL. Synthetic aspect selection proves the provider/admin pair cannot evaluate independently. OIDC logical metadata is canonical in `policy/identity.json`, but credential source paths have security-relevant scope differences. Termix extraction is mostly complete with its self-contained aspect and LA selection in place, Vaultwarden is the other enabled portable admin workload, and Quantum is already removed from the active module graph on `la-admin-1` and deferred.

## Goals / Non-Goals

**Goals:**

- IDB-1: make identity-provider and admin workloads independently selectable;
- IDB-2: give Kanidm runtime, state, provisioning, and secret contracts one owner;
- IDB-3: derive provider URL independently from canonical web policy;
- IDB-4: complete Termix and extract Vaultwarden as the enabled portable admin workloads where current coupling is only historical;
- IDB-5: preserve every secret path, recipient set, client ID, callback, scope, and claim.

**Non-Goals:**

- changing Kanidm data or provisioning semantics;
- editing encrypted secrets or `.sops.yaml`;
- creating an LA bundle/mega-aspect;
- automatically deriving credential storage from logical client metadata;
- deleting or re-scoping the in-progress Termix extraction, or re-enabling Quantum — Quantum stays disabled/deferred and is not a completion gate.

## Decisions

### IDB-1 — Provider owns its complete contract

Move provider data root, identity/provisioning secret inputs, and the client-keyed provisioning secret-source map under the identity-provider/Kanidm namespace. The map keys are validated against enabled canonical identity clients. Paths remain explicit because they encode SOPS ownership and readership.

### IDB-2 — Web policy is the URL authority

Identity-client defaults `providerUrl` from the resolved Kanidm web catalog. Identity-provider independently consumes the same URL. Neither writes the other's namespace. This reuses an existing authority instead of adding an identity-policy aspect.

### IDB-3 — Decompose the enabled workloads; record the disabled one

Termix and Vaultwarden become self-contained placement capabilities with their own runtime, secret, and selection contracts. Homepage, Gatus, and Beszel hub also become independent aspects: their links and monitoring relationships are catalog data, not intrinsic composition. Webhook remains available for external/manual use as a trivial standalone aspect because no in-repo caller owns it. Quantum is disabled/deferred and explicitly out of scope: it is removed from the active module graph (its service and host modules are deleted) and is not a completion gate. Each extracted capability owns enablement, runtime paths, and secret contracts; shared endpoint data comes from web policy. Any future Quantum re-enable SHALL land as a self-contained concern/aspect that consumes canonical identity contracts and SHALL NOT restore admin-hub coupling. Once the workloads are extracted, the residual broad `/srv/data` operator ACL/reconcile unit and Quantum SSH secret registrations move to explicit `la-admin-1` host-local configuration before `applications.admin` is deleted.

### IDB-4 — Explicit co-selection only

LA's host policy selects the desired provider and admin capabilities. No convenience aspect imports sibling public aspects. Tests evaluate meaningful subsets to prove independence and fail with named contract assertions rather than missing-option errors.

## Risks / Trade-offs

- **Large blast radius in identity provisioning** → freeze rendered provisioning, OIDC endpoints, SOPS registrations, and Kanidm unit observables before editing.
- **Secret source movement could widen access** → option ownership changes only; paths and `.sops.yaml` remain byte-identical.
- **Over-fragmenting admin composition** → keep only aggregation with demonstrated shared behavior; do not force one aspect per implementation file.
- **Current deployment changes during audit** → base implementation on the operator-confirmed tested Stage 7 revision.

## Migration Plan

1. Capture LA and OCI identity/admin observables and secret registrations.
2. Move provider-owned options and URL defaults without decomposing admin services; prove equivalence.
3. Finish Termix and extract Vaultwarden, Gatus, Beszel hub, Homepage, and Webhook as explicit portable admin capabilities, with focused subset-evaluation checkpoints; keep Quantum disabled/deferred and do not gate this change on its extraction.
4. Move the residual operator ACL/reconcile unit and Quantum SSH secret registrations to explicit LA host-local configuration, migrate Cockpit leaves to canonical web policy, update registry selections, and remove `applications.admin` when no consumer remains.
5. Deploy provider first only through the normal serialized LA deployment and verify local Kanidm readiness plus remote OIDC clients.
6. Record decision D-054 in `docs/decisions.md` (revised capability-boundary criterion; supersedes D-053's admin-hub/applications.admin/count/co-selection clauses; narrows D-050's co-selection interpretation) and sync the live architecture docs (`ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `docs/architecture.md`, `docs/plan.md`, `docs/dendritic-transition-analysis.md`); historical decision bodies and `docs/context-history.md` entries stay append-only.

Rollback restores the previous aspect set and option ownership; no secret ciphertext or database migration occurs.
