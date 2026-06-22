# Arize Phoenix — LLM Observability

[Arize Phoenix](https://github.com/Arize-AI/phoenix) is a lightweight,
single-container LLM observability platform deployed on `oci-melb-1`. It
ingests OpenTelemetry traces via OTLP (gRPC or HTTP) and provides a web UI
for inspecting LLM call latency, token usage, and error rates.

## Access

Phoenix is **not exposed to the public internet**. Access it over Tailscale:

```
http://<phoenix-tailscale-ip>:6006
```

To find the Tailscale IP of the Phoenix host:

```bash
tailscale status | grep oci-melb-1
```

Or use MagicDNS if enabled:

```
http://oci-melb-1:6006
```

## Architecture

```
┌──────────────┐     OTLP gRPC (4317)     ┌──────────────┐
│  Bifrost GW  │ ────────────────────────▶ │   Phoenix    │
│  (Podman)    │   (via instrumented SDK)   │  (Podman)    │
└──────────────┘                            │              │
                                            │  SQLite DB   │
┌──────────────┐     OTLP gRPC (4317)     │  /srv/data/  │
│  LiteLLM     │ ────────────────────────▶ │  phoenix/    │
│  (future)    │                            └──────────────┘
└──────────────┘
```

| Port | Protocol | Purpose |
|------|----------|---------|
| 6006 | HTTP | Web UI + HTTP OTLP ingestion |
| 4317 | gRPC | OTLP trace ingestion (preferred) |

## Data Lifecycle

- **Storage:** SQLite database at `/srv/data/phoenix/phoenix.db`
- **Retention:** Traces older than 90 days are pruned monthly via a systemd timer
- **Size limit:** If the DB exceeds 500 MB, it is rotated automatically
- **Backup:** The Phoenix data directory is included in the host's nightly restic backup

### Manual Cleanup

If you need to purge all traces and start fresh:

```bash
sudo systemctl stop podman-phoenix
sudo mv /srv/data/phoenix/phoenix.db{,.bak}
sudo systemctl start podman-phoenix
```

## Instrumenting a Python Service

### 1. Install the instrumentation package

```bash
pip install openinference-instrumentation-openai \
    opentelemetry-api \
    opentelemetry-sdk \
    opentelemetry-exporter-otlp-proto-grpc
```

### 2. Instrument your OpenAI client

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from openinference_instrumentation_openai import OpenAIInstrumentor

# Configure OTLP exporter pointing at Phoenix
exporter = OTLPSpanExporter(
    endpoint="http://127.0.0.1:4317",  # From host
    insecure=True,
)

provider = TracerProvider()
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)

# Auto-instrument the openai SDK
OpenAIInstrumentor().instrument()

# Your normal OpenAI calls are now traced
from openai import OpenAI
client = OpenAI(base_url="http://127.0.0.1:7411/v1", api_key="bifrost-local")
```

For containers on the same host, use `host.containers.internal:4317` instead of `127.0.0.1:4317`.

## Test Script

A standalone test script is available at `scripts/test-phoenix-trace.py`:

```bash
# Run from the repo root (installs deps via pip if needed)
python3 scripts/test-phoenix-trace.py
```

This script:
1. Installs required Python packages at runtime
2. Configures OpenTelemetry with OTLP gRPC exporter
3. Sends a test chat completion through Bifrost
4. Verifies the trace was delivered

**Prerequisites:** Phoenix and Bifrost must be running on the same host.

## Module Reference

### `services.phoenix`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Arize Phoenix |
| `image` | string | `ociImages.phoenix` | OCI image reference (pinned in `policy/oci-images.nix`) |
| `dataDir` | string | `/srv/data/phoenix` | Host path for Phoenix working directory |
| `port` | port | `6006` | HTTP port (UI + OTLP HTTP) |
| `grpcPort` | port | `4317` | gRPC OTLP port |
| `retentionDays` | int | `90` | Days to retain traces before pruning |
| `pruneMaxDbSizeMb` | int | `500` | Max SQLite DB size before rotation |
| `extraEnv` | attrs | `{}` | Extra env vars for the container |

### Read-only endpoint options

| Option | Example value | Use from... |
|--------|---------------|-------------|
| `services.phoenix.endpoint.grpc` | `http://127.0.0.1:4317` | Host services |
| `services.phoenix.endpoint.grpcContainer` | `http://host.containers.internal:4317` | Other Podman containers |
| `services.phoenix.endpoint.http` | `http://127.0.0.1:6006` | Host services (HTTP OTLP) |
