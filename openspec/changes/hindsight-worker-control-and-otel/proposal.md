# Proposal

## Why

Hindsight's embedded worker is enabled by default and has accumulated a large pending/failed operation queue. The API should remain available while background execution is disabled, Hindsight should become an observable trace producer, and only the stale pending/failed operations should be removed after the worker is confirmed off.

## What Changes

- Make the Hindsight worker's disabled state explicit in the deployed environment without disabling the API or control plane.
- Enable Hindsight's native OTEL trace producer and route it through the fleet collector. Confirm the trace payload and destination policy before enabling export: the pinned Hindsight implementation records LLM prompts and completions, and the local forge collector does not carry the OCI-only Langfuse/Latitude fan-out.
- As a one-time post-deploy operation, delete only pending and failed rows from Hindsight's async-operation queue; retain completed/cancelled rows and all memory data.

## Capabilities

### New Capabilities
- `hindsight-service`: operational worker control and trace-export behavior for the Hindsight service.

### Modified Capabilities
- None. Existing `feature-topology` governs the concern-owned deployment aspect; `operations` covers operator workflows. Neither has a Hindsight-specific behavior requirement to amend.

## Impact

- Code: `modules/knowledge/hindsight.nix`; focused Hindsight contract assertions in `tests/check-dendritic-scaffold-contract.sh`.
- Runtime: home-forge Hindsight container and its PostgreSQL `async_operations` table. No secret values are read or changed. Queue deletion is intentionally limited to `pending` and `failed` rows after the worker-off deployment is verified.
- Privacy/routing gate: Hindsight's OTEL spans include prompt/completion message content. The operator must choose whether to redact those attributes before fan-out or explicitly permit full-content export. Routing to home-forge's local collector reaches VictoriaTraces only; the OCI gateway is required for the Langfuse/Latitude fan-out.
