## Context

`identity-provider` reads `applications.admin`, while `admin-hub` writes Kanidm options imported only by the provider. The provider also writes the identity-client provider URL. Synthetic aspect selection proves the provider/admin pair cannot evaluate independently. OIDC logical metadata is canonical in `policy/identity.json`, but credential source paths have security-relevant scope differences.

## Goals / Non-Goals

**Goals:**
- IDB-1: make identity-provider and admin workloads independently selectable;
- IDB-2: give Kanidm runtime, state, provisioning, and secret contracts one owner;
- IDB-3: derive provider URL independently from canonical web policy;
- IDB-4: split portable admin capabilities where current coupling is only historical;
- IDB-5: preserve every secret path, recipient set, client ID, callback, scope, and claim.

**Non-Goals:**
- changing Kanidm data or provisioning semantics;
- editing encrypted secrets or `.sops.yaml`;
- creating an LA bundle/mega-aspect;
- automatically deriving credential storage from logical client metadata.

## Decisions

### IDB-1 — Provider owns its complete contract

Move provider data root, identity/provisioning secret inputs, and the client-keyed provisioning secret-source map under the identity-provider/Kanidm namespace. The map keys are validated against enabled canonical identity clients. Paths remain explicit because they encode SOPS ownership and readership.

### IDB-2 — Web policy is the URL authority

Identity-client defaults `providerUrl` from the resolved Kanidm web catalog. Identity-provider independently consumes the same URL. Neither writes the other's namespace. This reuses an existing authority instead of adding an identity-policy aspect.

### IDB-3 — Decompose admin by portability, not service count

Termix, Vaultwarden, and Quantum become self-contained placement capabilities. Homepage/Gatus/Beszel may remain a composition only where aggregation is intrinsic and documented. Webhook follows its actual consumer. Each extracted capability owns enablement, runtime paths, and secret contracts; shared endpoint data comes from web policy.

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
3. Extract portable admin capabilities in small batches with subset-evaluation tests.
4. Update registry selections and remove `applications.admin` when no consumer remains.
5. Deploy provider first only through the normal serialized LA deployment and verify local Kanidm readiness plus remote OIDC clients.

Rollback restores the previous aspect set and option ownership; no secret ciphertext or database migration occurs.
