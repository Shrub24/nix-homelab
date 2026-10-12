# AI-route log mapping probe

## Question
Can the AI mixed route tag (`telemetry.route=ai`) be retained in VictoriaLogs as a resource-derived field while using a Collector-side allowlist that preserves selected log record fields and the body?

## Evidence

Pinned VictoriaLogs source `v1.53.0`, `app/vlinsert/opentelemetry/pb.go`:

- `decodeResourceLogs` calls `decodeResource`, adding resource attributes to the output field set with an empty prefix.
- It records the count of resource fields, then processes each `ScopeLogs` and each `LogRecord`; after each scope group, it truncates back to resource fields.
- `decodeInstrumentationScope` adds `scope.name`, `scope.version`, and scope attributes prefixed `scope.attributes`.
- `decodeLogRecord` adds record attributes unprefixed, decodes the OTLP body as fields, and adds `trace_id`, `span_id`, `severity_number`, and `severity_text`. The timestamp uses `time_unix_nano`, else `observed_time_unix_nano`, else current time.
- This confirms resource `telemetry.route` is projected as an ordinary searchable VictoriaLogs field. It does not guarantee resource-vs-record collision behavior; a producer can supply a record attribute with the same key, so the Collector log view should delete any record-level `telemetry.route` before setting the resource marker.

VictoriaLogs official OTLP ingestion docs state the OTLP/HTTP logs endpoint is `/insert/opentelemetry/v1/logs`. The pinned exporter supports the explicit `logs_endpoint` key (Collector core v0.155.0 `exporter/otlphttpexporter/config.go`).

## Design implication

The user-approved field allowlist must run in the Collector before the VictoriaLogs queue. For OTTL, preserve only record timestamp and observed timestamp, severity number/text, trace/span IDs (and flags if the processor's pdata API exposes them), body, and explicitly selected record identity fields if any; preserve resource `telemetry.route`, `host.name`, `service.name`, `deployment.environment.name`; drop all other log-record, resource and scope attributes. Need verify OTTL log-context field names and resource attr handling using the pinned Collector 0.155.0 implementation/tests before emitting statements. This document records mapping evidence only; not a contract substitute or runtime smoke.
