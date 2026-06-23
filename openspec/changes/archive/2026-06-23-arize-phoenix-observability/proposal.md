# Arize Phoenix Observability

## Core Value

Add lightweight LLM observability to the homelab fleet by deploying **Arize Phoenix** as a sidecar tracing collector. This gives visibility into LLM call latency, token usage, error rates, and invocation traces for Bifrost gateway, LiteLLM (when added), and any OpenAI-compatible service without introducing the operational overhead of a multi-service observability stack.

## Current State

Bifrost gateway (`oci-melb-1`) exposes an OpenAI-compatible API at port 7411 and routes LLM calls through Gemini, DeepSeek, OpenRouter, and CrofAI providers. There is no LLM-specific observability — debugging a slow or failing call requires digging through journald logs. The `client.enable_logging: true` flag in Bifrost config logs to stdout inside the container, but there is no structured trace collection or visualization.

## Proposed Change

### What

Add a new NixOS module `modules/services/phoenix.nix` that deploys Arize Phoenix as a Podman container on `oci-melb-1`, exposing:
- Port **6006** — Phoenix UI and HTTP OTLP ingestion
- Port **4317** — gRPC OTLP ingestion (preferred for production instrumentation)

The module exposes a `config.services.phoenix.endpoint` read-only option for other services to reference when configuring OTel exporters.

### How It Integrates

| Source | Instrumentation Path |
|---|---|
| **Bifrost gateway** (Python SDK usage) | `openinference-instrumentation-openai` with `base_url=http://bifrost:7411` |
| **LiteLLM proxy** (future) | Set `PHOENIX_COLLECTOR_ENDPOINT=http://phoenix:4317` |
| **Local Python apps** | Direct `OpenTelemetry` SDK export to `phoenix:4317` |

### Constraints

- **Single-container only** — Must not require ClickHouse, Postgres, Redis, or any external stateful store. Phoenix's SQLite mode is sufficient for homelab scale.
- **Tailscale-first access** — The Phoenix UI (port 6006) must not be exposed publicly. Access is via Tailscale IP/MagicDNS.
- **Storage bounded** — Data directory should have an explicit retention period or size cap to prevent unbounded growth on the 28G data disk.
- **Resource-light** — Must not meaningfully compete with Bifrost, Karakeep, Paperless, or Postgres for RAM (target < 512 MB idle, < 2 GB under moderate load).

## Alternatives Considered

**Langfuse** — Rejected for this phase. It requires Postgres + ClickHouse + Redis + S3, increasing operational surface by 4 stateful stores and consuming disproportionate RAM on the OCI Ampere A1 free tier (24 GB shared across all services). It would be reassessed if multi-team prompt management or A/B experiment dashboards become a concrete need.

## Success Criteria

1. Phoenix container runs on `oci-melb-1` with SQLite persistence
2. Phoenix UI accessible over Tailscale at `phoenix.oci-melb-1.tailnet-name.ts.net:6006` or via local Tailscale IP
3. A Python-based test script can emit a traced LLM call (simulated) and it appears in the Phoenix UI
4. The module passes `nix flake check`
5. Total disk usage stays under 5 GB after 30 days of moderate use
