## 1. Prerequisites and equivalence baseline

- [ ] 1.1 Confirm the `migrate-admin-host-to-la` cutover gate before starting any implementation.
  - refs: `openspec/changes/migrate-admin-host-to-la/tasks.md`, `openspec/changes/migrate-admin-host-to-la/design.md`
  - criteria: The active migration's cutover and backup gates have passed or the operator has explicitly cleared this deferred change to start; no work begins while the migration is in flight.
  - delegate: CodeScout
  - verify: Operator confirmation recorded; active change status verified via `openspec list`.

- [ ] 1.2 Capture repository validation and per-host evaluation baselines.
  - refs: `treefmt.toml`, `.just/checks.just`, `flake.nix`, `lib/deploy/hosts.nix`
  - criteria: Record `nix flake check`, `just checks all`, `just fmt-check`, and per-host `nixosConfigurations.*` evaluation as the pre-change baseline; note any pre-existing failures so they are not attributed to this change.
  - delegate: BuildAgent
  - verify: Baseline output saved in the change artifacts; all subsequent batches compare against it.

## 2. Module-owned conventional secret defaults and stable interconnections

- [ ] 2.1 Move conventional host-scoped secret registration into owning modules for `oci-melb-1`.
  - refs: `hosts/oci-melb-1/default.nix`, `modules/services/tailscale.nix`, `modules/services/admin/cockpit.nix`, `modules/services/beszel-agent-auth.nix`, `modules/services/state-backups.nix`, `modules/services/niks3.nix`, `lib/secrets.nix`
  - criteria: Host-owned raw `sops.secrets` entries for conventional host-system-scoped inputs (tailscale auth key, cockpit service-user password hash, beszel token, backup credentials, niks3 API token) resolve through module contract defaults keyed at `secrets/hosts/oci-melb-1/system.yaml`; the host keeps only explicit exceptions and feature selection.
  - delegate: CoderAgent
  - verify: `nix eval .#nixosConfigurations.oci-melb-1.config.sops.secrets` matches the pre-change set; `./tests/check-secret-scope.sh` passes.

- [ ] 2.2 Move conventional host-scoped secret registration into owning modules for `la-admin-1` (post-cutover state).
  - refs: `hosts/la-admin-1/default.nix`, `modules/services/tailscale.nix`, `modules/services/admin/cockpit.nix`, `modules/services/beszel-agent-auth.nix`, `modules/services/state-backups.nix`, `modules/services/niks3.nix`, `lib/secrets.nix`
  - criteria: Same contract-default pattern as 2.1 applied to LA; no behavior change to secret paths, keys, or modes; host retains only explicit exceptions.
  - delegate: CoderAgent
  - verify: LA `sops.secrets` eval equivalence before/after; `./tests/phase-la-admin-contract.sh` passes.

- [ ] 2.3 Move stable service interconnections into providing modules.
  - refs: `hosts/oci-melb-1/default.nix`, `hosts/la-admin-1/default.nix`, `modules/services/notification-daemon/default.nix`, `modules/services/niks3.nix`, `modules/shared/niks3-post-deploy.nix`, `lib/policy.nix`
  - criteria: Stable cross-service wiring (notification daemon → ntfy origin, niks3 auto-upload → cache host origin, cache consumer → niks3 endpoint) resolves from providing-module defaults or canonical policy metadata; host files stop repeating origin/server URL literals.
  - delegate: CoderAgent
  - verify: Rendered host configs (e.g. `/etc/notification-daemon/config.json`, niks3 upload unit env) are byte-identical before/after; `just checks all` passes.

## 3. Edge and Cockpit overlay consolidation

- [ ] 3.1 Move the pure edge catalog projection from host overlays into the `edge-ingress` owner.
  - refs: `hosts/la-admin-1/edge.nix`, `hosts/do-admin-1/edge.nix`, `modules/applications/edge-ingress.nix`, `modules/services/edge-proxy-ingress.nix`, `policy/web-services.nix`
  - criteria: `applications.edge-ingress` with `role = "edge"` renders routes, primary domain, ACME email, and AOP posture from `config.repo.web.currentHost.services`; per-host `edge.nix` files are deleted; no host-specific edge values are lost.
  - delegate: CoderAgent
  - verify: Evaluation-equivalence proof for `nixosConfigurations.la-admin-1` before/after; `./tests/check-web-services-policy.sh la-admin-1` and `./tests/check-web-service-catalog.sh` pass.

- [ ] 3.2 Move Cockpit service-user wiring into the Cockpit admin module.
  - refs: `hosts/la-admin-1/cockpit-auth.nix`, `hosts/oci-melb-1/cockpit-auth.nix`, `hosts/do-admin-1/cockpit-auth.nix`, `modules/services/admin/cockpit.nix`
  - criteria: Cockpit module owns service-user enablement, name, deny-ssh posture, and the conventional password-hash secret source; `cockpit-auth.nix` overlays shrink to genuine host-specific values only (OCI `urlRoot`/`publicHost`, LA absence thereof).
  - delegate: CoderAgent
  - verify: Per-host Cockpit service config eval-equivalent before/after; redundant `mkForce` removals carry their equivalence proof in the same commit.

- [ ] 3.3 Review the overlay consolidation diff for behavior drift.
  - refs: `design.md` (NORM-2), `specs/edge-proxy-ingress/spec.md`, `specs/admin-services/spec.md`
  - criteria: No route, access, AOP, or Cockpit transport behavior changed; each deletion has an in-batch equivalence proof.
  - delegate: CodeReviewer
  - verify: Review report confirms no unresolved high/medium finding; all deletion batches gated.

## 4. Physical topology SSOT and consistency checks

- [ ] 4.1 Add `nixosConfigurations` vs deploy-node consistency check.
  - refs: `flake.nix`, `lib/deploy/hosts.nix`, `lib/deploy/default.nix`, `flake.nix` checks wiring
  - criteria: A flake check fails when a `nixosConfigurations` key is absent from `deployTopology.nodes` unless explicitly marked non-deployable, and when a deploy node lacks a `nixosConfiguration`; the check names the missing side.
  - delegate: CoderAgent
  - verify: `nix flake check` passes with current topology and fails when a host is deliberately removed from one side (negative test recorded).

- [ ] 4.2 Add the CI deploy-order mismatch check and remove duplicated host literals.
  - refs: `.github/workflows/deploy.yml`, `.github/workflows/ci.yml`, `lib/deploy/hosts.nix`, `docs/architecture.md`
  - criteria: The deploy workflow gains an explicit check comparing its job list/order to exported topology metadata (`nix eval .#deployHosts` JSON or generated artifact) and fails on divergence; duplicated host lists in workflow comments/docs are removed or tied to the canonical source.
  - delegate: CoderAgent
  - verify: Mismatch check fails on an intentionally wrong host list (recorded negative test); `just checks all` passes with the correct list.

## 5. Ntfy typed publisher contract

- [ ] 5.1 Introduce the typed ntfy publisher contract owned by the ntfy module.
  - refs: `modules/services/ntfy.nix`, `hosts/la-admin-1/default.nix`, `secrets/.templates/services/ntfy.yaml`, `tests/phase-la-admin-contract.sh`
  - criteria: A `services.ntfy.publishers` typed option (user, token secret reference, role) exists; the module derives `auth.access` ACL subjects and validates `auth.users` placeholders from it; host config stops hand-listing bare-hostname ACL subjects; secret values remain placeholder-only in committed content; the post-cutover publisher set (LA sole publisher after DO decommission) is the contract source.
  - delegate: CoderAgent
  - verify: `nix eval` of LA ntfy auth access matches the contract-derived set; `./tests/phase-la-admin-contract.sh` passes; no bcrypt hash or token appears in committed files.

- [ ] 5.2 Align secret template and scope/contract tests with the typed contract.
  - refs: `secrets/.templates/services/ntfy.yaml`, `tests/phase-la-admin-contract.sh`, `tests/fixtures/secret-scope.nix`, `modules/services/ntfy.nix`
  - criteria: Template placeholders and test expectations derive from the same pure contract function; adding/removing a publisher requires one contract change; a regression check verifies config, template, and test consistency.
  - delegate: TestEngineer
  - verify: Regression check fails when a publisher is present in only one of host config/template/test (recorded negative test); `./tests/check-secret-scope.sh` passes.

## 6. OIDC client metadata derivation

- [ ] 6.1 Derive OIDC client defaults and host secret-file maps from identity metadata.
  - refs: `policy/identity.json`, `lib/policy.nix`, `modules/shared/identity-oidc.nix`, `modules/applications/admin/default.nix`, `hosts/la-admin-1/default.nix`, `hosts/oci-melb-1/default.nix`
  - criteria: Client callback paths, route keys, display names, and scope/claim maps resolve from `policy/identity.json`; `applications.admin`'s `oidcClients` secret-file map is derived from the registry instead of the hand-maintained host map; security-relevant flags remain explicit overrides.
  - delegate: CoderAgent
  - verify: Rendered admin OIDC wiring is eval-equivalent before/after; `nix flake check` and admin host contract tests pass.

- [ ] 6.2 Add strict OIDC scope/derivation tests.
  - refs: `tests/phase-la-admin-contract.sh`, `tests/check-web-services-policy.sh`, `policy/identity.json`
  - criteria: Tests compare derived client metadata against the explicit registry; accidental scope/claim widening or a missing client in derived maps fails checks.
  - delegate: TestEngineer
  - verify: Negative tests (scope widening, client removal orphan) fail as designed; full `just checks all` passes.

## 7. Secret-scope fixture mechanical deduplication

- [ ] 7.1 Share only mechanical host identity data in the secret-scope fixture.
  - refs: `tests/fixtures/secret-scope.nix`, `tests/check-secret-scope.sh`, `lib/deploy/hosts.nix`
  - criteria: The host-name → age-recipient mapping is derived from one shared mechanical source (or a single shared table) while every scope's expected reader set remains explicitly declared in the fixture; no expectation is computed from topology.
  - delegate: CoderAgent
  - verify: `./tests/check-secret-scope.sh` and `./tests/check-secret-scope-extra-reader.sh` pass; accidental-recipient-widening negative test still fails.

## 8. Adopted-host invariants and OCI-default removal

- [ ] 8.1 Extract reusable adopted-host checks from the LA adoption path.
  - refs: `tests/check-ssh-host-fingerprint.sh`, `tests/phase-la-admin-contract.sh`, `docs/runbooks/host-initialization.md`, `modules/shared/host-recovery.nix`
  - criteria: Adopted-host invariants (verified host-key-to-age derivation, provider-console recovery proof, non-destructive first-generation boot, facter capture) are extracted into shared check helpers reused by any adopted host; LA-specific values stay in LA files.
  - delegate: CoderAgent
  - verify: Shared helper run against LA and a synthetic adopted-host fixture passes; `just checks all` passes.

- [ ] 8.2 Remove OCI-specific bootstrap defaults from the generic path without duplicating migration task 3.2e.
  - refs: `modules/providers/oci/default.nix`, `hosts/oci-melb-1/bootstrap-config.nix`, `hosts/la-admin-1/default.nix`, `openspec/changes/migrate-admin-host-to-la/tasks.md` (task 3.2e)
  - criteria: Generic bootstrap path contains no OCI-branded disk/network defaults; OCI-specific defaults are reachable only through the OCI provider module; any bootstrap script safety already addressed by migration task 3.2e is consumed as a dependency, not re-implemented.
  - delegate: CoderAgent
  - verify: `nix eval` of `la-admin-1` bootstrap inputs contains no OCI defaults; dependency on task 3.2e stated in the task notes; `nix flake check` passes.

## 9. Dead code removal and unwired test restoration

- [ ] 9.1 Prove zero consumers before deleting any dead module/helper/global.
  - refs: `modules/`, `lib/`, `policy/globals.nix`, `codebase-memory-mcp` graph, `tests/`
  - criteria: For each candidate (modules, helpers, globals identified by the architecture audit), record zero-consumer proof via graph traces or exhaustive reference search in the change artifacts; no deletion lands without the proof and a passing `nix flake check`.
  - delegate: CodeScout
  - verify: Proof recorded per candidate; deletion commits are separate and each passes `nix flake check` + `just checks all`.

- [ ] 9.2 Restore or explicitly archive unwired OCI contract tests.
  - refs: `tests/`, `.github/workflows/ci.yml`, `.just/checks.just`
  - criteria: OCI-specific contract tests found unwired from CI or the local check set are restored to the check set or moved to an explicit archive with a documented reason; coverage does not silently shrink.
  - delegate: CoderAgent
  - verify: Check-set inventory shows every test file either wired or archived with a reason; `just checks all` passes.

## 10. Module taxonomy and ownership documentation

- [ ] 10.1 Document module taxonomy and ownership after implementation.
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/plan.md`, `docs/runbooks/host-initialization.md`, `specs/repository-structure/spec.md`
  - criteria: Docs define which layer owns conventional secrets, stable interconnections, typed contracts, and host exceptions, and match the implemented structure; module path examples are accurate.
  - delegate: DocWriter
  - verify: `git diff --check` passes; doc review confirms taxonomy matches the implemented modules; `docs/` links resolve.

## 11. Final validation and review gate

- [ ] 11.1 Run full validation and record apply-ready status.
  - refs: `treefmt.toml`, `.just/checks.just`, `flake.nix`, `openspec/`
  - criteria: `just fmt-check`, `nix flake check`, `just checks all`, per-host evaluations, and `openspec validate normalize-fleet-boundaries --strict` all pass; no secret ciphertext was created, decrypted, or edited.
  - delegate: BuildAgent
  - verify: Final validation report saved; strict OpenSpec validation passes; change declared apply-ready.

- [ ] 11.2 Review the complete change for boundary, security, and rollback defects.
  - refs: `proposal.md`, `design.md`, `specs/`, `tasks.md`
  - criteria: The change introduces no role-to-host registry, no auto-generated `.sops.yaml`, no service namespace renames, no `adopted-host.nix` profile, and no speculative abstractions; every batch is revertible with equivalence checks.
  - delegate: CodeReviewer
  - verify: Follow-up review reports no unresolved high- or medium-severity finding; apply gate confirmed.
