## Context

The `la-admin-1` transition (active change `migrate-admin-host-to-la`) consolidated edge, identity, and admin roles onto one host. During that transition, ownership boundaries drifted in four reproducible ways: thin host assemblies re-register raw `sops.secrets` entries and hardcode cross-service wiring; per-host `edge.nix` and `cockpit-auth.nix` overlays re-project catalog data and duplicate service-user wiring; physical host facts (identity, order, edge designation) are literal-copied across `lib/deploy/hosts.nix`, `flake.nix`, CI workflows, and docs; and typed identities — ntfy publisher users and OIDC clients — are mirrored across host config, secret templates, tests, and the web catalog. See `proposal.md` — Why for motivation.

This change is post-transition cleanup. It is deferred: it must not land, or touch migration-owned files, while the cutover is in flight.

## Goals / Non-Goals

**Goals:**

- NORM-A: Move conventional host secret defaults and stable service interconnections into owning modules while hosts keep feature selection and explicit exceptions.
- NORM-B: Remove per-host `edge.nix`/`cockpit-auth.nix` duplication, moving pure projections into the `edge-ingress` owner and Cockpit service-user wiring into the Cockpit module.
- NORM-C: Make `lib/deploy/hosts.nix` a verified physical-topology SSOT with `nixosConfigurations`/deploy-node consistency and explicit CI mismatch checks.
- NORM-D: Introduce one typed ntfy publisher contract owned by the ntfy module; derive host config, template expectations, and tests from it.
- NORM-E: Derive OIDC client metadata and secret-file maps from `policy/identity.json` with strict scope tests.
- NORM-F: Reduce mechanical duplication in the secret-scope fixture while keeping expected reader sets explicit.
- NORM-G: Extract reusable adopted-host invariants and remove OCI-specific bootstrap defaults from the generic path, consuming any migration task 3.2e bootstrap-safety work.
- NORM-H: Delete dead modules/helpers/globals only after zero-consumer proof; restore or explicitly archive unwired OCI contract tests.
- NORM-I: Document module taxonomy/ownership after implementation.

**Non-Goals:**

- Altering or blocking the active `migrate-admin-host-to-la` cutover; touching its `generated/` policy output, `la-admin-1` policy host block, or migration runbook artifacts.
- Introducing a general role-to-host registry, auto-generating `.sops.yaml` from broad roles, or adding any speculative abstraction.
- Renaming service namespaces or creating an `adopted-host.nix` profile until evidence shows more than a test helper is needed.
- Changing any secret value, recipient set, or runtime behavior; this is an ownership refactor verified by evaluation equivalence and existing regression checks.

## Decisions

### NORM-1: Reuse existing module contract surfaces for conventional secret defaults

**Chosen:** Move conventional host-scoped secret registration into the consuming service/application module, keyed by a typed default pointing at the host's `secrets/hosts/<host>/system.yaml`, exposed through the existing `secretFiles.*` / `secretKeys.*` contract surface (`lib/secrets.nix` helpers). Hosts that need a non-conventional source pass an explicit override; hosts otherwise drop the raw `sops.secrets` block.

**Why:** The topology migration already established the contract-surface pattern (`lib/secrets.nix`, `secretHelpers.mkSecretFileOption`). Reusing it avoids a second abstraction while removing the repeated raw registrations seen in `hosts/oci-melb-1/default.nix` (tailscale, cockpit, beszel, state-backups, niks3) and `hosts/la-admin-1/default.nix`.

**Alternatives considered:** A new fleet-wide secret-defaults registry duplicates the module options that already exist. Leaving hosts as-is keeps the duplication that caused the drift.

### NORM-2: Consolidate edge and Cockpit overlays with equivalence proof

**Chosen:** Move the pure catalog projection currently in `hosts/<host>/edge.nix` into `modules/applications/edge-ingress.nix` (edge role renders routes from `config.repo.web.currentHost.services`); delete the per-host overlays. Move Cockpit service-user wiring (enablement, name, deny-ssh posture, password-hash secret source) into `modules/services/admin/cockpit.nix` with the conventional host-system default; shrink `cockpit-auth.nix` to genuine host-specific values only (OCI's `urlRoot`/`publicHost`/`denySsh` vs LA's absence thereof). Remove redundant `mkForce` overrides only after an evaluation-equivalence proof (identical `nixos-rebuild`/`nix eval` config values or derivation output before/after) lands in the same batch.

**Why:** `edge.nix` is byte-identical in shape across LA and DO and only re-projects catalog data; `cockpit-auth.nix` re-declares service-user wiring that the Cockpit module owns. The evaluation-equivalence gate makes deletion safe without a live rollout test.

**Alternatives considered:** Keeping overlays preserves per-host flexibility but perpetuates the duplication. Merging Cockpit into the base profile would force Cockpit onto hosts that do not enable it.

### NORM-3: Physical topology stays in `lib/deploy/hosts.nix` with consistency checks

**Chosen:** `lib/deploy/hosts.nix` remains the SSOT for `nodes`, `edgeHost`, and `deployOrder`. Add a flake check that every `nixosConfigurations` key appears in `nodes` or is explicitly marked non-deployable, and vice versa. CI keeps explicit physical job names (workflows cannot evaluate the flake natively) but gains an explicit mismatch check: a small script compares the workflow's host list/order against the exported topology JSON (`nix eval .#deployHosts` or a generated artifact) and fails on divergence.

**Why:** `flake.nix` already derives deploy nodes and host packages from `deployTopology`; the gap is that CI and docs duplicate the list. An explicit mismatch check preserves workflow auditability (explicit job names, dependency graph) while making drift fail loudly. This matches the migration's own MIG-3b boundary.

**Alternatives considered:** Generating CI workflow files from Nix adds tooling before a second host creates real pressure. A pure reference check in docs only catches drift when someone reads them.

### NORM-4: One typed ntfy publisher contract owned by the ntfy module

**Chosen:** Add a `services.ntfy.publishers` option: a typed attrset keyed by bare hostname of `name -> { user, tokenSecret, role }` where `tokenSecret` references a secret path/template (never a value). The ntfy module renders `auth.access` ACLs, validates `auth.users` entries, and emits the expected bare-hostname publisher identities; `secrets/.templates/services/ntfy.yaml` and the scope/contract tests derive expectations from the same pure function. Host config stops hand-listing ACL subjects, and templates stop restating the identity triples.

**Why:** The publisher identities are currently triplicated: host ACLs (`hosts/la-admin-1/default.nix`), template comments/placeholders (`secrets/.templates/services/ntfy.yaml`), and contract tests (`tests/phase-la-admin-contract.sh`). One typed contract with placeholder-only committed content keeps secrets out of the store while making add/remove a single change.

**Alternatives considered:** Generating the encrypted file from the contract would require operator-only encryption inside the build — out of scope and against the repo's ciphertext-free template rule. A test-only helper without a module option leaves hosts still hand-declaring ACLs.

### NORM-5: OIDC client metadata derives from identity policy

**Chosen:** Treat `policy/identity.json` as the registry: `lib/policy.nix` (or `modules/shared/identity-oidc.nix`) derives the client set, callback paths, route keys, and scope/claim maps; `modules/applications/admin/default.nix` derives its `oidcClients` secret-file map from the registry instead of hand-maintaining the host map (`hosts/la-admin-1/default.nix` lines 81–89). Security-relevant flags (`allowInsecureClientDisablePkce`, `enableLegacyCrypto`, `preferShortUsername`) stay explicit in the registry and are covered by strict scope tests that fail on unintended widening.

**Why:** The client set is already centralized in `identity.json`; only the consumers' mirrors drifted. Deriving maps removes the triplication without a new abstraction.

**Alternatives considered:** A separate client-registry file duplicates `identity.json`. Keeping host maps means every client add/remove requires host edits.

### NORM-6: Secret-scope fixture shares only mechanical identity data

**Chosen:** Keep `tests/fixtures/secret-scope.nix` as the explicit per-scope expected-reader table (it is the regression's oracle), but derive the host-name → age-recipient mapping from a shared small table (or the same table `tests/check-secret-scope.sh` already maps inline). No scope expectations are computed from topology; only the mechanical anchor mapping is shared.

**Why:** The fixture is deliberately explicit so accidental recipient widening fails. Automating the whole expectation set would let a topology error silently redefine expected readers.

**Alternatives considered:** Generating the fixture from `.sops.yaml` inverts the check and defeats its purpose.

### NORM-7: Reusable adopted-host invariants, OCI defaults removed

**Chosen:** Extract the adopted-host invariants proven by the LA adoption (`tests/check-ssh-host-fingerprint.sh`, host-key-to-age derivation, provider-console recovery proof, non-destructive first-generation boot, facter capture) into shared check helpers used by any adopted host. Remove OCI-specific bootstrap defaults from the generic bootstrap path so they are only imported by the OCI provider module. If migration task 3.2e already addressed bootstrap script safety, consume that work as a dependency and do not duplicate it.

**Why:** LA was the first adopted host; the next one should not rediscover these checks. OCI bootstrap defaults leaking into the generic path would mislead future non-OCI adoptions.

**Alternatives considered:** An `adopted-host.nix` profile is deferred — current evidence shows shared checks and a runbook section suffice.

### NORM-8: Zero-consumer-proof gated deletions

**Chosen:** Before deleting any module/helper/global, record zero-consumer proof (codebase-memory graph traces or exhaustive `search_code` results) in the task/change artifacts. Unwired OCI contract tests found during the audit are restored to the check set or explicitly archived with a reason.

**Why:** Silent deletion and silent test loss were both flagged by the architecture audit as drift mechanisms.

**Alternatives considered:** Deleting first and checking later risks removing something with a hidden consumer.

### NORM-9: Documentation lands in the same change window

**Chosen:** After implementation, update `docs/architecture.md`, `docs/decisions.md`, and `docs/plan.md` with the module taxonomy and ownership rules (layer → owns conventional secrets/interconnections/typed contracts/host exceptions), consistent with the repository-structure requirement.

**Why:** The repository-structure spec already requires docs to move with structure changes; taxonomy docs prevent the next transition from re-creating the drift.

## Risks / Trade-offs

- [Module-owned secret defaults widen blast radius] → Defaults point only at the host's own conventional system scope; `.sops.yaml` path rules are unchanged; secret-scope check still runs and fails on unexpected recipients.
- [Moving secret declarations changes activation order] → Equivalence-proof each batch: `nix eval` the affected host configs before/after and compare rendered values; run `just fmt-check` and contract checks.
- [Evaluation-equivalence proof is skipped for a "trivial" mkForce removal] → Require the proof artifact in the same task as the deletion; CodeReviewer verifies it before merge.
- [CI mismatch check becomes brittle] → Keep the check tiny (compare workflow host list/order to exported JSON); document that adding a host requires updating both, with the check enforcing it.
- [Ntfy contract drift during migration] → This change is deferred until after cutover; the contract derives from the final post-migration publisher set (LA sole publisher, DO decommissioned).
- [OIDC derivation changes client behavior] → Strict scope tests compare derived metadata against the explicit registry; any security-relevant override remains explicit and reviewed.
- [Hidden consumers block deletion] → Zero-consumer proof is a task deliverable; `nix flake check` plus full host evaluation run before each deletion batch.
- [Overlap with migration task 3.2e] → Task dependency is stated; bootstrap-safety work is consumed, not re-implemented.

## Migration Plan

This change is deferred. Batch sequence, each gated by equivalence/regression checks before the next:

1. **Baseline (B0):** Confirm `migrate-admin-host-to-la` cutover gate passed (or explicit operator clearance). Record current `nix flake check`, `just checks all`, and per-host eval baselines.
2. **B1 — Module-owned defaults (NORM-1):** Move conventional host secret defaults and stable interconnections into owning modules per host; equivalence-proof; run secret-scope + host contract checks.
3. **B2 — Overlay consolidation (NORM-2):** Move edge projection and Cockpit service-user wiring into owners; delete overlays and redundant mkForce with equivalence proofs in-batch.
4. **B3 — Topology SSOT (NORM-3):** Add `nixosConfigurations`/node consistency check and CI mismatch check; remove duplicated literals in workflows/docs.
5. **B4 — Typed contracts (NORM-4, NORM-5):** Ntfy publisher contract and OIDC-derived maps with strict scope tests.
6. **B5 — Test hygiene (NORM-6, NORM-7, NORM-8):** Fixture mechanical dedup, adopted-host check extraction, OCI default removal, zero-consumer-proof deletions, unwired test restoration.
7. **B6 — Docs (NORM-9):** Taxonomy/ownership documentation; final full validation; review gate.

Rollback: each batch is a refactor with no runtime behavior change; revert the batch commit and re-run equivalence checks.

## Open Questions

- Exact shape of the derived OIDC client map consumed by `modules/applications/admin/default.nix` depends on the migration's final post-cutover admin composition. This can be settled during implementation without changing the specs, approach, or task breakdown — the requirement is derivation from identity metadata, not a specific attrset shape.
