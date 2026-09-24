# Proposal

## Why

The test suite has accumulated migration inventories and source-text checks that fail after harmless refactors while missing real behavioural regressions. The completed Kanidm upgrade still produces a routine skip because its test looks for an old 1.10 binary in the local store.

**Core Value:** a smaller suite that verifies current fleet behaviour rather than the spelling and arrangement of its implementation.

## What Changes

- Remove assertions that grep, regex-match, or manually parse implementation source to prove runtime wiring, placement, or retired names. Do not replace them with a different source-scanning tool.
- Delete duplicate aspect inventories, literal descriptions, historical namespace ratchets, and mutation cases that test only those removed predicates.
- Retain evaluated contract relationships, capability-isolation cases, named fail-closed rejection, executed script behaviour, and artifact freshness checks. Add a replacement only where removal would otherwise lose a distinct current invariant.
- Retire the completed Kanidm 1.10-to-1.11 migration branch and its recurring optional-runtime skip. Keep current restore guards and fail-closed verification cases, exercising the evaluated production helper rather than reconstructing it from Nix source.
- Retire obsolete phase scripts after moving any unique current behavioural checks to their owning suite. Remove dead runner references and update current documentation where necessary.
- Preserve grep over command output and generated artifacts where it checks an observable outcome; the target is scanning code to restate implementation.

### Constraints

- No production policy, host placement, secrets, package pins, or deployment changes.
- Preserve security, recovery, and data-loss boundaries; do not delete a unique check merely because it is inconvenient.
- Preserve all three hosts and both architectures at their existing validation boundaries.
- Do not build a generic test framework, reproduce dependency algorithms, or add migration snapshots.
- The recipient-validation and telemetry-redaction coverage defects found in the audit are separate work. This change must not expand into those fixes or claim they are resolved.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This is test/tooling refactoring; `.openspec.yaml` sets `skip_specs: true`. Existing contracts in `openspec/specs/repository-structure/spec.md` and `openspec/specs/kanidm-identity/spec.md` remain unchanged, including explicit placement and fail-closed offline restore.

## Impact

Primary targets are `tests/check-dendritic-scaffold-contract.sh`, `tests/check-identity-contract-directionality.sh`, `tests/phase-la-admin-contract.sh`, `tests/kanidm-restore-contract.sh`, and obsolete `tests/phase-*.sh` scripts. The same source-restatement rule applies to focused backup, gateway, shell, web-catalog and deploy-gate tests. `.just/checks.just` and current test documentation change only as needed to match retained entrypoints.

No remote operations or host activation are needed. The implementation report will identify retained invariants and deleted duplication, not use line-count reduction as proof of correctness.
