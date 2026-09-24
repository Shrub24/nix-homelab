# Design

## Context

See `proposal.md` for motivation and `specs/hindsight-service/spec.md` for observable behavior. Hindsight runs as one host-networked container on home-forge; API, control plane, and the optional background worker share that deployment. In the pinned image, the worker defaults to enabled and is independently controlled by `HINDSIGHT_API_WORKER_ENABLED`.

The pinned Hindsight tracing implementation has two relevant properties: its OTLP/HTTP exporter appends `/v1/traces` when absent, and its inference-detail span event carries serialized GenAI input messages, output messages, and system instructions. Home-forge's local collector sends traces to VictoriaTraces; the Langfuse and Latitude exporters are deliberately enabled only on OCI, where their secret files and services are colocated. Reaching all three therefore requires the fleet's private telemetry-ingest endpoint, not a loopback URL on home-forge.

## Goals / Non-Goals

**Goals:**
- Stop Hindsight's embedded worker without disabling its API or control plane.
- Route Hindsight traces through the fleet collector using canonical service-inventory data.
- Remove only pending and failed asynchronous operations after worker shutdown is verified.

**Non-Goals:**
- Disable Hindsight's API, control plane, memory database, or PostgreSQL consumer.
- Delete completed/cancelled operations, memory records, or any other database state.
- Start trace export before the operator has chosen whether content-bearing inference events may be retained or must be redacted.

## Decisions

- **Worker control:** set `HINDSIGHT_API_WORKER_ENABLED = "false"` in the container's NixOS environment. Keep `HINDSIGHT_ENABLE_API` and `HINDSIGHT_ENABLE_CP` enabled. The running unit is `podman-hindsight`; changing this direct container environment changes its unit and recreates it.
- **Trace route:** use the pinned nix-fleet telemetry-ingest resolver to target the OCI collector over the private network, so the collector applies its existing destination fan-out. Do not hard-code the gateway hostname or send to home-forge loopback when the intended sinks include the OCI-only Langfuse/Latitude legs. The exact resolver expression must be confirmed against the pinned contract before editing.
- **Trace content:** hold `HINDSIGHT_API_OTEL_TRACES_ENABLED` off until the operator confirms either (a) removal of prompt/completion/system-instruction event attributes before export, or (b) authorization to export those full contents to all configured sinks. Hindsight's pinned exporter has no documented content-redaction option; Bifrost's own `disable_content_logging` setting does not apply to Hindsight.
- **Queue cleanup:** after the worker-off deployment is verified, use one transaction scoped to `async_operations.status IN ('pending', 'failed')`. Report counts only; never select or print operation payloads. Verify preserved statuses and memory data after commit.

## Risks / Trade-offs

- **Worker disabled while API remains writable** → new API calls may enqueue work that cannot be processed; verify the queue after deployment and keep cleanup last in the requested sequence.
- **Trace spans contain memory/LLM content** → do not enable export until content handling is explicitly chosen; if redaction is chosen, verify the collector removes event fields before every exporter.
- **Home-forge local collector lacks the LLM-backend fan-out** → use the canonical OCI ingest endpoint and verify traces in each intended backend rather than infer fan-out from local config.
- **Queue deletion is irreversible** → scope by status in a transaction, record pre/post counts, and leave all other Hindsight data untouched.

## Migration Plan

1. Set the worker environment to false, run focused evaluation and the repository gates, deploy home-forge, then verify the container environment, API/control-plane health, and absence of worker claims.
2. Resolve the trace-content choice with the operator. Implement the canonical private collector route and the chosen content policy, validate the rendered configuration, deploy, and verify a fresh Hindsight trace at each configured destination.
3. With the worker still disabled, transactionally delete pending and failed `async_operations`; verify those counts are zero and the completed/cancelled counts and memory data remain unchanged.

Rollback of worker mode is a Nix change back to `true`, followed by a deployment; it is not part of this change unless requested. Deleted queue rows are not recoverable by this procedure.

## Open Questions

None. Trace-content handling is an explicit task gate: obtain the operator's choice before enabling export.
