## ADDED Requirements

### Requirement: Phoenix container runs with SQLite persistence

The Arize Phoenix container SHALL start automatically and persist its SQLite database to a stable host path.

#### Scenario: Container starts on boot
- **WHEN** the `oci-melb-1` host boots or the Phoenix service is started
- **THEN** the Phoenix container starts within 60 seconds
- **AND** the SQLite database at `/srv/data/phoenix/phoenix.db` is created/available

#### Scenario: Persistent data survives container restart
- **WHEN** the Phoenix container is restarted
- **THEN** previously collected traces and spans are still present in the UI

---

### Requirement: OTLP trace ingestion via gRPC and HTTP

Phoenix SHALL accept OpenTelemetry traces via both gRPC (port 4317) and HTTP/protobuf (port 6006).

#### Scenario: Python SDK exports trace via gRPC
- **WHEN** a Python application configures an `OTLPSpanExporter` with endpoint `http://phoenix:4317` and `insecure=True`
- **THEN** the trace appears in the Phoenix UI within 5 seconds

#### Scenario: HTTP OTLP fallback works
- **WHEN** an exporter cannot use gRPC and sends via HTTP/protobuf to `http://phoenix:6006/v1/traces`
- **THEN** the trace is ingested successfully and visible in the UI

---

### Requirement: Tailscale-only UI access

The Phoenix web UI SHALL NOT be reachable from the public internet.

#### Scenario: UI accessible over Tailscale
- **WHEN** a Tailscale-connected device navigates to `http://<phoenix-tailscale-ip>:6006`
- **THEN** the Phoenix UI loads successfully

#### Scenario: UI blocked from public internet
- **WHEN** a request arrives at port 6006 from a non-Tailscale, non-localhost interface
- **THEN** the connection is refused or dropped by the host firewall

---

### Requirement: Trace data bounded by retention

Trace data SHALL NOT grow unbounded on the host's 28G data disk.

#### Scenario: Retention timer prunes old traces
- **WHEN** the monthly retention timer fires
- **THEN** spans older than 90 days are deleted from the SQLite database
- **AND** the database is vacuumed to reclaim space

#### Scenario: Manual pruning command available
- **WHEN** the user runs the documented manual cleanup command
- **THEN** all traces are deleted and the database file is compacted

---

### Requirement: Module exposes read-only endpoint options

Other NixOS modules SHALL be able to reference the Phoenix OTLP endpoint via a read-only config option.

#### Scenario: Container service references Phoenix endpoint
- **WHEN** a service sets `otelExporterOtlpEndpoint = config.services.phoenix.endpoint.grpcContainer`
- **THEN** the value resolves to `http://host.containers.internal:4317`
- **AND** the option is marked `readOnly = true`

---

### Requirement: Bifrost client instrumentation test

A test SHALL verify that Bifrost-routed LLM calls can be traced end-to-end.

#### Scenario: Test script sends traced LLM completion
- **WHEN** a Python test script runs with `openinference-instrumentation-openai` configured
- **AND** the script sends a chat completion to `http://bifrost:7411/v1`
- **THEN** the resulting trace appears in the Phoenix UI with the correct model name, token counts, and latency

---

### Requirement: Module is valid and passes flake check

The new module and any related changes SHALL NOT break the project's Nix evaluation.

#### Scenario: Host evaluation succeeds
- **WHEN** `nix flake check` is run from the repo root
- **THEN** evaluation completes without errors
- **AND** no new warnings are introduced by the Phoenix module

#### Scenario: Module can be disabled safely
- **WHEN** `services.phoenix.enable = false` is set on a host
- **THEN** evaluation succeeds
- **AND** no Phoenix-related containers or files are created on the target system
