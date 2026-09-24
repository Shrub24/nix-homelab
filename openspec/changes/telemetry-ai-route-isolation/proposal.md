# Proposal

## Why

The telemetry gateway on `home-forge` currently derives its trace fan-out from destination presence: every trace received on the general OTLP ingress is exported to VictoriaTraces **and** to Langfuse and Latitude. That makes the LLM-observability backends an implicit sink for the whole fleet's telemetry — infrastructure, node, Bifrost and diagnostic-probe spans arrive alongside agent sessions. Latitude has already reported sessions with no LLM call in range, which is the visible symptom of that mixing.

There is also no way to keep an AI-only lane distinct: a producer cannot select "AI sessions" as a stream, because the only ingress is the general one.

**Core Value:** AI-session telemetry reaches the LLM-observability backends as an explicitly selected stream, while general fleet telemetry keeps reaching the general store and nothing else.

**Constraints:**

- nix-fleet published the named-route contract (`services.telemetry.routes.<route>`, main `fb5ac7e3`); this repository must consume the published contract rather than implement a parallel mechanism.
- Route listeners carry **no authentication** — authenticated admission is a separate, unimplemented upstream change. This change delivers routing separation only and must not be described as access-controlled.
- The general route and its generated component names stay unchanged, so un-migrated producers and existing queue/WAL state keep working.
- Producer-side rebinding (Pi's workstation relay and future producers) and the canonical endpoint record belong to other repositories; this change wires the gateway side and requests the inventory record.

## What Changes

- `home-forge` declares `services.telemetry.routes.ai` — traces, metrics and logs admitted on its own tailnet listener (`100.126.123.74:4319`, HTTP only), with per-signal destinations explicitly selected (routes inherit nothing).
- Consuming the published revision also requires the upstream capability split: the bare `telemetry` aspect is now vocabulary plus our fleet policy, and each host ships a signal by composing that signal's lane (`telemetry-metrics`, `telemetry-logs`, and on the gateway `telemetry-otlp`). Collector-scoped policy moves into the OTLP lane, because `services.otel-collector` only exists where a collector realization is composed.
- Two unrelated upstream moves land in the same revision and are absorbed here: the retired `services.nix-gc` fleet namespace (our override is dropped in favour of the new upstream defaults) and the contract's requirement that journald shipping state its unit allowlist or deliberately license the whole journal.
- The fleet telemetry policy keeps general traces, metrics and logs on their operational stores (VictoriaTraces, VictoriaMetrics, VictoriaLogs); Langfuse and Latitude are reachable only from the AI route.
- Bifrost (the fleet AI gateway) enrolls on the AI lane so its LLM-gateway spans keep reaching Langfuse and Latitude. Its export target resolves from nix-fleet's canonical service inventory rather than a literal gateway address, so enrollment follows the `otel-collector.endpoints.ai-otlp.tailnet` record this change requests upstream.
- The destination-level exporter policy that already exists (Langfuse ingestion-version header, Latitude project header and `compression = "none"`) continues to apply, because it is keyed by destination rather than by route.
- Documentation distinguishes the two lanes and records that the AI lane is routing-only.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `llm-observability`: AI-session traces reach Langfuse and Latitude only through the explicitly selected route; per-signal AI/general routing and default-deny OTLP log redaction are defined.

## Impact

- `modules/flake/telemetry.nix` (general-route narrowing, AI-lane destination policy).
- `modules/hosts/home-forge/_nixos.nix` (AI route listener and destination selection).
- `modules/ai/bifrost/service.nix` (gateway export target moves to the AI lane).
- `ARCHITECTURE.md`, `docs/architecture.md`, `docs/decisions.md` (lane documentation and decision record).
- `tests/check-dendritic-scaffold-contract.sh` (collector wiring pins).
- Cross-repository: nix-fleet adds `otel-collector.endpoints.ai-otlp.tailnet`; nix-dotfiles rebinds producers to the resolved endpoint.
