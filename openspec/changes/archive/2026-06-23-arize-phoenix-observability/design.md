# Arize Phoenix Observability — Design

## Behavior IDs

| ID   | Behavior                        | Risk Level |
| ---- | ------------------------------- | ---------- |
| PH-1 | Phoenix container deployment    | Low        |
| PH-2 | OTLP gRPC/HTTP trace ingestion  | Low        |
| PH-3 | Phoenix UI access (Tailscale)   | Medium     |
| PH-4 | SQLite persistence & retention  | Medium     |
| PH-5 | Bifrost gateway instrumentation | Medium     |

---

## PH-1: Phoenix Container Deployment

### Design

Deploy Arize Phoenix as a Podman container via `virtualisation.oci-containers.containers` — the same mechanism used by Bifrost gateway.

**Image:** `arizephoenix/phoenix:latest` (official image, multi-arch with `aarch64` support)

**Container config:**
- `autoStart = true`
- Ports: `6006:6006` (UI + HTTP OTLP), `4317:4317` (gRPC OTLP)
- Volumes: `/srv/data/phoenix:/var/lib/phoenix` for SQLite persistence
- Environment:
  - `PHOENIX_WORKING_DIR=/var/lib/phoenix`
  - `PHOENIX_GRPC_PORT=4317`
  - `PHOENIX_PORT=6006`
  - `PHOENIX_HOST=0.0.0.0`

**Data directory:** `/srv/data/phoenix` — consistent with other service data paths (`/srv/data/bifrost`, `/srv/data/karakeep`, etc.)

### Design Decisions

- **SQLite mode** — Phoenix's default single-file SQLite backend is chosen over PostgreSQL. The homelab generates modest trace volumes (tens to low hundreds of LLM calls/day), well within SQLite's capabilities. PostgreSQL would add migration and connection management overhead for no tangible benefit.
- **Single port mapping** — Port 6006 serves both the UI and HTTP OTLP ingestion. Port 4317 is separate for gRPC. This matches Phoenix upstream defaults.

---

## PH-2: OTLP Trace Ingestion

### Design

Phoenix natively exposes two OTLP endpoints:
- **gRPC:** `0.0.0.0:4317` — preferred for production OTel SDK exporters
- **HTTP:** `0.0.0.0:6006/v1/traces` — fallback for environments without gRPC support

The module exposes a read-only option `config.services.phoenix.endpoint` that other services can reference:

```nix
# Output shape:
endpoint = {
  grpc = "http://127.0.0.1:4317";          # From host
  grpcContainer = "http://host.containers.internal:4317";  # From other containers
  http = "http://127.0.0.1:6006";           # From host (HTTP OTLP)
};
```

### Instrumentation Targets (Phase 1)

| Source | Method | SDK |
|---|---|---|
| Bifrost Python clients | `openinference-instrumentation-openai` | Python OTel SDK → gRPC to Phoenix |
| Future: LiteLLM proxy | `PHOENIX_COLLECTOR_ENDPOINT` env var | LiteLLM built-in OTel export |

---

## PH-3: Phoenix UI Access (Tailscale)

### Design

Phoenix UI binds to `0.0.0.0:6006` inside the container, but **no firewall rule opens it to the public internet**. The port is only accessible:
1. Locally on the host via `http://127.0.0.1:6006`
2. Over Tailscale via `http://<tailscale-ip>:6006`

This matches the existing security posture of Bifrost, Karakeep, and other services — Tailscale-first, no public ingress.

### Risk: Port 6006 exposed on Podman bridge

Podman containers connect to `podman0` bridge by default. The host firewall currently allows ports 5030 and 4533 on `podman0` (from the existing config). Port 6006 for Phoenix doesn't need explicit firewall rules — Tailscale access goes through `tailscale0`, not `podman0`. However, if Bifrost or other containers on the same Podman network need to send traces, they can reach Phoenix at `host.containers.internal:4317` without any firewall rule.

**Mitigation:** No action needed. The existing `networking.firewall` rules already block inbound connections on public interfaces. Podman bridge traffic is local-only.

---

## PH-4: SQLite Persistence & Retention

### Design

Phoenix stores traces and spans in a SQLite database at `PHOENIX_WORKING_DIR/phoenix.db`. This file lives on the data mount (`/srv/data/phoenix/`).

**Growth estimation:**
- Each LLM trace: ~5-10 KB (single span with metadata)
- At ~100 calls/day, 30 days = ~15-30 MB
- Even at 1000 calls/day, 30 days = ~150-300 MB
- Phoenix's own span export + UI assets add ~50-100 MB

Expected total: well under 1 GB for the first year at homelab scale.

**Retention strategy:**
- Phoenix does not have a built-in retention policy in SQLite mode
- The module will include a systemd timer that periodically prunes old spans via Phoenix's `/v1/delete-traces` API (or uses SQLite `VACUUM` / file rotation)
- **Phase 1 default:** Simple monthly systemd timer that purges spans older than 90 days via the Phoenix HTTP API
- **Backup:** The existing `services.state-backups` module (already enabled on `oci-melb-1`) will back up the Phoenix data directory — no additional backup config needed

### Risk: Unbounded SQLite growth

If the user runs heavy batch workloads (e.g., bulk embedding generation through Bifrost) without corresponding trace rate limits, the SQLite file could grow faster than estimated.

**Mitigation:** The systemd timer is the primary safeguard. The PRUNE-1 task includes a warning in the module docs about manual cleanup.

---

## PH-5: Bifrost Gateway Instrumentation

### Design

Bifrost itself is a Go binary that emits logs but does not natively export OpenTelemetry traces. To get LLM call visibility from Bifrost-routed traffic, there are two approaches:

**Approach A (Recommended for Phase 1):** Instrument the _client_ side — any Python service that calls Bifrost's OpenAI-compatible API uses `openinference-instrumentation-openai`. This captures the call from the client's perspective: latency as perceived by the application, token counts (if returned by the provider), and error status.

```python
from openinference_instrumentation_openai import OpenAIInstrumentor
from opentelemetry.exporter.otlp.grpc.exporter import OTLPSpanExporter

OpenAIInstrumentor().instrument(
    exporter=OTLPSpanExporter(endpoint="http://phoenix:4317", insecure=True)
)

client = openai.OpenAI(base_url="http://bifrost:7411/v1", api_key="bifrost-local")
```

**Approach B (Future):** Run a sidecar OTel collector that reads Bifrost's stdout logs or metrics endpoint and exports them as traces. This is more complex and not justified at homelab scale.

### Phase 1 Scope

- Only Approach A (client-side instrumentation) will be implemented
- A test script (`scripts/test-phoenix-trace.py`) will be provided to verify end-to-end trace delivery
- Documentation for how other services (Paperless-GPT, future apps) can enable tracing

---

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Phoenix image unavailable for `aarch64` | Low | High | Phoenix upstream provides `linux/arm64` manifests. Verify on first pull. |
| SQLite corruption on unclean shutdown | Low | Medium | Phoenix is tolerant; periodic backups via `state-backups` module. |
| Trace volume exceeds retention capacity | Low | Low | Systemd timer for periodic pruning. Module docs include manual cleanup command. |
| Podman network port collision | Low | Medium | Ports 6006 and 4317 are unclaimed in current `oci-melb-1` config. Verify before deployment. |
| Phoenix version drift breaks config | Low | Low | Pin image digest in module or use a specific version tag (`:latest` acceptable for homelab). |

---

## Multi-Host Considerations

While Phoenix is deployed on `oci-melb-1` (where Bifrost runs), the design does not preclude:
- A second Phoenix instance on `do-admin-1` for local services
- A centralized Phoenix instance if Bifrost moves to another host
- Using an OTel Collector to fan traces from multiple hosts into a single Phoenix instance

For now, keep it simple: one instance, one host, colocated with the primary LLM gateway.
