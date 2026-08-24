## Why

The `la-admin-1` transition consolidated the fleet onto a new admin, identity, and edge host, but ownership boundaries drifted during the move. Thin host assemblies now repeat raw secret paths and cross-service wiring that owning modules should provide as typed defaults; admin/edge overlays (`edge.nix`, `cockpit-auth.nix`) are duplicated per host; physical host metadata is triplicated across flake, deploy metadata, CI, and docs; and ntfy publisher identities plus OIDC client metadata are mirrored across host config, templates, and tests. This change is post-transition cleanup: it is deferred and must not block or alter the active `migrate-admin-host-to-la` cutover.

## Core Value

Restore explicit ownership boundaries — modules own conventional secret defaults, stable interconnections, and typed contracts, while hosts keep feature selection and explicit exceptions — using deletions, typed defaults, and mismatch tests instead of new abstraction layers.

## What Changes

- Move conventional host secret defaults and stable service interconnections to owning modules. Hosts retain feature selection and explicit exceptions, expressed through existing module contract surfaces (`secretFiles.*`, `secretKeys.*`) rather than raw `sops.secrets` re-registration.
- Consolidate duplicate admin overlays: move pure catalog projection from `hosts/<host>/edge.nix` into the `edge-ingress` owner; move Cockpit service-user wiring into the Cockpit admin module. Remove redundant host `mkForce` overrides only after an evaluation-equivalence proof lands in the same batch.
- Keep `lib/deploy/hosts.nix` as the physical topology SSOT. Add `nixosConfigurations` vs deploy-node consistency so new hosts must appear in topology metadata or be explicitly marked non-deployable. CI/deploy order may consume the metadata or carry an explicit mismatch check when workflow auditability requires explicit jobs.
- Introduce one typed ntfy publisher contract owned by the ntfy module; generate host config, secret-template expectations, and test expectations from it. Bcrypt hashes and publish tokens stay in encrypted secret material (placeholder-only committed content).
- Derive OIDC client metadata and host secret-file maps from canonical identity metadata, with security-relevant overrides (PKCE relaxation, legacy crypto, short-username preference) explicit and strict scope tests enforced.
- Reduce only mechanical duplication in the secret-scope test fixture (host→recipient identity data); keep per-scope expected reader sets explicit so accidental recipient widening still fails.
- Extract reusable adopted-host invariants/checks from the LA adoption path and remove OCI-specific bootstrap defaults from the generic path. Task 3.2e of the active migration may already address bootstrap script safety — state that dependency and avoid duplicate work.
- Delete dead modules/helpers/globals only after zero-consumer proof; restore or explicitly archive unwired OCI contract tests.
- Document module taxonomy/ownership after implementation.
- **Deferred/omitted**: renaming service namespaces, and creating an `adopted-host.nix` profile — both stay out until evidence shows more than a test helper is needed. No role-to-host registry, no auto-generated `.sops.yaml` from broad roles, no speculative abstractions.

## Capabilities

### New Capabilities

None — this change normalizes ownership of existing behavior and introduces no new capability surface.

### Modified Capabilities

- `feature-topology`: Host assemblies delegate conventional secret defaults and stable service interconnections to owning modules instead of repeating raw wiring.
- `secrets-management`: Conventional host-scoped service secrets resolve through module-owned defaults; secret-scope test expectations stay explicit while sharing only mechanical topology data.
- `edge-proxy-ingress`: Edge host composition projects from the edge-ingress owner's catalog; host-local re-projection overlays are removed.
- `admin-services`: Cockpit service-user wiring is module-owned; redundant host overrides removed after equivalence proof.
- `fleet-infrastructure`: Physical topology metadata is single-sourced and consistency-checked against flake/CI consumers.
- `operations`: Deployment and CI ordering consume physical topology metadata or declare explicit mismatch checks.
- `notification-policy-defaults`: Ntfy publisher identity is one typed contract owned by the ntfy module.
- `kanidm-identity`: OIDC client defaults derive from identity policy with explicit security-relevant overrides.
- `provider-owned-oidc-uris`: OIDC client secret-file maps derive from identity metadata rather than triplicated host maps.
- `host-recovery`: Adopted-host invariants are reusable across preinstalled-NixOS hosts.
- `bootstrap-storage`: Adoption bootstrap does not inherit OCI-specific defaults.
- `repository-structure`: Dead code removal is gated by zero-consumer proof; unwired OCI contract tests are restored or archived; module taxonomy/ownership is documented after implementation.

## Impact

- Affected host and topology files: `hosts/oci-melb-1/default.nix`, `hosts/la-admin-1/default.nix`, `hosts/<host>/edge.nix`, `hosts/<host>/cockpit-auth.nix`, `hosts/do-admin-1/` (rollback host, only if still active).
- Affected modules/helpers: `modules/services/ntfy.nix`, `modules/services/notification-daemon/`, `modules/applications/edge-ingress.nix`, `modules/services/admin/cockpit.nix`, `modules/applications/admin/default.nix`, `modules/shared/identity-oidc.nix`, `lib/deploy/hosts.nix`, `lib/policy.nix`, `lib/secrets.nix`, `policy/identity.json`, `secrets/.templates/services/ntfy.yaml`.
- Affected checks/CI: `tests/check-secret-scope.sh`, `tests/fixtures/secret-scope.nix`, `tests/phase-la-admin-contract.sh`, `tests/check-ssh-host-fingerprint.sh`, `.github/workflows/ci.yml`, `.github/workflows/deploy.yml`.
- Affected docs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/runbooks/host-initialization.md`.
- Operator actions: none beyond normal review/merge; secret values are not changed, only their declaration ownership. The change is a refactor with no runtime behavior change, verified by evaluation-equivalence and existing regression checks.
- Interplay: does not touch `generated/policy/web-services.json`, the `la-admin-1` policy host block, or migration-runbook artifacts; applies only after the `migrate-admin-host-to-la` cutover gate.
