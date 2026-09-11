## Context

See `proposal.md` for motivation. The deployed Stage 3 baseline uses one central `modules/flake/aspects.nix` to publish three infrastructure support modules, five foundation aspects, and three operational aspects. `modules/flake/dj.nix` is already independently discovered, but its host still repeats `applications.dj.enable = true`. Six legacy roots remain behind one enumerated import-tree filter.

The design must preserve Stage 1–3 behavior while correcting the target model before web, identity, music, or admin conversion continues.

## Goals / Non-Goals

**Goals:**

- Make source-feature ownership independent of deployment-aspect granularity.
- Prove distributed, auto-discovered publication without changing public aspect names or host placement.
- Restore selection-is-enablement for DJ.
- Replace an over-broad composition prohibition with relationship-specific rules.
- Make semantic contracts—not current scaffolding filenames or order—the durable test surface.

**Non-Goals:**

- Convert remaining legacy service/application/shared roots.
- Split `_aspects/base.nix` or redesign `fleet.foundation` facts.
- Split the D-049 `backups` deployment capability.
- Remove support projections still used by unconverted lower-level modules.
- Change registry schema, import-tree filtering, secrets, routes, bootstrap, deployment, or runtime behavior.

## Decisions

### S4-1 — Treat source modules and deployment aspects as independent axes

An import-tree-discovered file is a top-level flake-parts contributor. A deployment aspect is a deferred NixOS module explicitly selected by a host. Multiple source modules may contribute to one aspect, and discovery registers contributions without deploying them.

**Alternative rejected:** one public aspect per source file. It confuses ownership with placement and creates selection noise.

**Alternative rejected:** retain most first-party feature files permanently as plain lower-level modules. That preserves the old evaluator-class taxonomy and makes the temporary filter permanent in substance.

### S4-2 — Decompose only the central publication file in this stage

Replace `modules/flake/aspects.nix` with independently discovered files named for the concern they own:

- support: `provenance.nix`, `oci-images.nix`, `fleet-packages.nix`;
- foundation: `base.nix`, `shell.nix`, `networking.nix`, `tailscale.nix`, `notify.nix`;
- operational: `backups.nix`, `builder-access.nix`, `observability-agent.nix`;
- existing feature contributor: `dj.nix`.

Every definition keeps the same `flake.modules.nixos.<name>` attribute and body. Private implementation imports and `withSystem` allowlists remain unchanged.

**Alternative rejected:** split every remaining leaf now. That would mix endpoint correction with product migrations and make equivalence failures hard to localize.

### S4-3 — Classify support modules without pretending they are deployment capabilities

`provenance`, `oci-images`, and `fleet-packages` remain NixOS deferred modules because live lower-level consumers need their typed values. Registry comments and tests classify them as infrastructure support, not operator-selected capabilities.

They are compatibility projections with retirement criteria:

- provenance may later become intrinsic registry/base composition;
- OCI image policy should move to feature-owned lexical capture as each consumer converts;
- fleet package projection should disappear as owning feature contributors inject only their packages.

Stage 4 introduces no replacement bus.

### S4-4 — Make DJ selection its enablement

`flake.modules.nixos.dj` sets `applications.dj.enable = true`. Home-forge removes only that redundant assignment and retains Engine enablement, paths, share configuration, and secret input. DJ does not select music; current co-location remains explicit fleet policy.

### S4-5 — Model aspect relationships by semantics

Use three modes:

1. **Intrinsic composition:** the owner directly imports a required implementation or aspect that has no meaningful independent placement.
2. **Policy co-selection:** independently useful capabilities are selected together by host policy and may use a named assertion. Existing `backups` → `notify` remains in this category.
3. **Optional integration:** integration activates only when both contracts are present; neither selects the other.

Direct aspect imports are not globally forbidden, but require intrinsic-composition justification. This stage adds none.

### S4-6 — Keep private lower-level modules as exceptions, not the endpoint default

Existing `_aspects/*`, generated/hardware fragments, upstream modules, and current unconverted leaves remain untouched. Future conversions decide ownership file by file. The six-directory filter remains the explicit migration boundary and must shrink as converted roots empty; underscore-renaming whole roots solely to hide unchanged code is not completion.

### S4-7 — Preserve deployed mechanics and behavior

The following remain fixed: `mkFlake`, import-tree and its one filter, typed host registry, `lib.nixosSystem`, no `specialArgs`, systems, bootstrap projection, `deployHosts.edgeHost` and `deployOrder`, public module names, foundation/operational selections, package output keys and support allowlists, Tailscale MTU/auth-key behavior, notify package resolution and monitor behavior, secret behavior, backup gates/assertions, and service behavior.

Only source/store provenance caused by moving expressions is permissible in comparison output. Any runtime, secret, endpoint, topology, recovery, or service delta blocks completion.

### S4-8 — Test semantics rather than a central layout snapshot

Update the existing scaffold test to:

- discover publications across source modules;
- inventory support modules separately from deployment aspects;
- include DJ in the deployment inventory;
- verify explicit per-host deployment selection without pinning meaningless import order;
- prove DJ selection enables DJ and discovery alone does not;
- retain Stage 1–3 evaluated probes and relevant negative mutations;
- stop requiring `aspects.nix`, an exact private filename list, or a universal no-aspect-import rule.

The exact six-entry migration filter remains temporarily checked because accidental discovery is still unsafe, but the test must describe it as a shrinking migration boundary.

## Risks / Trade-offs

- **[Definition omitted during extraction]** → Build an exact ownership map first; delete the central file only after publication inventory and host evals pass.
- **[Import-tree discovery accidentally activates workloads]** → Negative-test unselected DJ and retain explicit host import checks.
- **[Distributed definitions become hard to inventory]** → Search all discovered contributors and validate public names semantically rather than centralizing them for test convenience.
- **[Support modules become permanent ambient buses]** → Document explicit retirement criteria; do not expand either support attrset in this stage.
- **[Source movement changes store paths]** → Compare structured evaluated values and `nix-diff`; permit only content-identical provenance movement.
- **[Realignment scope grows into product redesign]** → Defer base split, backup/cache split, support removal, and remaining leaf conversion to focused stages.

## Migration Plan

1. Capture the deployed Stage 3 baseline and exact central-definition ownership map.
2. Extract support, foundation, and operational contributors without semantic edits.
3. Make DJ selection enable DJ and remove its duplicate host assignment.
4. Update the existing contract around distributed publication and activation semantics.
5. Reconcile canonical docs and record the corrected target decision.
6. Run formatting, focused/full checks, all host evaluations, structured comparison, and `nix-diff`.
7. Obtain independent architecture review and strict OpenSpec validation.

Rollback is the parent Stage 3 JJ change. No deployment is part of this change; deployment follows the established per-stage operator gate.
