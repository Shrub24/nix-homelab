#!/usr/bin/env bash
set -euo pipefail

# Contract: the AI telemetry route reads differently per destination
# (openspec change telemetry-ai-route-isolation task 3.4).
#
# One route is one input audience, so the route declaration decides who can be
# reached and the output views decide what each of them receives: the analysis
# backends take the session as produced, the operational store takes the same
# spans with their content carriers removed. A native pipeline override means
# the declaration alone proves nothing, so this reads the *effective* settings
# and runs nix-fleet's own composition guard (`lib.telemetryOutputViews`) over
# them, then proves the guard is not vacuous by mutating one pipeline the way a
# forgotten override would.
#
# Two evaluations, deliberately: `real` reads the merged configuration, and
# `mutant` feeds the guard a settings copy that assigns one destination to two
# output pipelines. Both come from one flake instance, so the two playthroughs
# cannot diverge on source-copy churn.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
HOST="${1:-home-forge}"
PROBE="$(mktemp /tmp/telemetry-view-composition.XXXXXX.nix)"
trap 'rm -f "$PROBE"' EXIT

fail() {
  echo "check-telemetry-view-composition: $*" >&2
  exit 1
}

cat >"$PROBE" <<EOF
let
  f = builtins.getFlake "path:$ROOT";
  lib = f.inputs.nixpkgs.lib;
  validator =
    if builtins.getEnv "NIX_FLEET_OUTPUT_VIEW_CHECKS" != "" then
      (import (builtins.getEnv "NIX_FLEET_OUTPUT_VIEW_CHECKS") {
        inherit lib;
        config = { };
        inputs = { };
      }).flake.lib.telemetryOutputViews
    else
      f.inputs.nix-fleet.lib.telemetryOutputViews;
  host = f.nixosConfigurations.$HOST.config;
  settings = host.services.opentelemetry-collector.settings;
  inspection = {
    inherit settings;
    instances = host.services.otel-collector.exporterInstances;
    destinations = host.services.telemetry.destinations;
    views = host.fleet.telemetry.outputViews;
    route = "ai";
    resolvedRoutes = host.services.telemetry.resolvedRoutePipelines;
    resolvedPipelines = host.services.telemetry.resolvedPipelines;
    sops = {
      secrets = host.sops.secrets;
      env = host.sops.templates."otel-collector.env".content;
    };
  };
  mutant = inspection // {
    settings = lib.recursiveUpdate settings {
      service.pipelines."traces/route-ai".exporters =
        settings.service.pipelines."traces/route-ai".exporters
        ++ settings.service.pipelines."traces/route-ai-lean".exporters;
    };
  };
in
{
  pipelines = settings.service.pipelines;
  processors = settings.processors;
  exporters = settings.exporters;
  route = host.services.telemetry.routes.ai;
  views = inspection.views;
  failures = validator.compositionFailures inspection;
  mutantFailures = validator.compositionFailures mutant;
}
EOF

json="$(nix eval --impure --json --no-write-lock-file --file "$PROBE")" ||
  fail "$HOST: evaluation failed (see the nix error above)"

python3 - "$HOST" "$json" <<'PYEOF' || fail "$HOST: AI-route output views drifted (see message above)"
import json, sys

host, payload = sys.argv[1], json.loads(sys.argv[2])
problems = []

# Every reported composition failure is fatal: the helper checks effective
# route membership and materialized outputs independently for each signal.
views = payload.get("views") or {}
if not views:
    problems.append("the host publishes no expected output views; the composition is not declared")

for failure in payload.get("failures") or []:
    problems.append(f"composition guard: {failure}")

# Non-vacuity: the regression this composition exists to prevent is a
# destination left in the generated pipeline while a view also exports it.
mutant = payload.get("mutantFailures") or []
if not mutant:
    problems.append("the composition guard accepted one destination exported by two pipelines")
elif not any("effective output pipelines" in failure for failure in mutant):
    problems.append(f"the mutated composition failed for an unrelated reason: {mutant}")

pipelines = payload.get("pipelines") or {}
processors = payload.get("processors") or {}

exporters_of = {name: pipeline.get("exporters") or [] for name, pipeline in pipelines.items()}
expected = {
    "logs": ["otlphttp/victorialogs"],
    "logs/ingress": ["otlphttp/victorialogs"],
    "logs/route-ai": ["otlphttp/route-ai-victorialogs"],
    "metrics": ["prometheusremotewrite/victoriametrics"],
    "metrics/ingress": ["prometheusremotewrite/victoriametrics"],
    "traces/route-ai": ["otlphttp/route-ai-langfuse"],
    "traces/route-ai-lean": ["otlphttp/route-ai-victoriatraces"],
    "traces/route-ai-latitude": ["otlphttp/route-ai-latitude"],
    "metrics/route-ai": ["prometheusremotewrite/route-ai-victoriametrics"],
}
for name, want in expected.items():
    got = exporters_of.get(name)
    if got != want:
        problems.append(f"pipeline {name} exports {got} instead of {want}")


def statements(processor):
    return [
        statement
        for block in processor.get("trace_statements") or []
        for statement in block.get("statements") or []
    ]


# The lean view has to strip the carriers the analysis backends parse, and the
# numbered families have to be covered by pattern rather than by enumeration.
lean = statements(processors.get("transform/output-view-lean", {}))
for carrier in (
    "gen_ai.input.messages",
    "gen_ai.output.messages",
    "gen_ai.system_instructions",
    "gen_ai.tool.call.arguments",
    "gen_ai.tool.call.result",
):
    if not any(
        statement == f'delete_key(span.attributes, "{carrier}")' for statement in lean
    ):
        problems.append(f"the lean view does not strip the carrier {carrier}")
if not any(statement.startswith("delete_matching_keys(span.attributes,") for statement in lean):
    problems.append("the lean view does not strip the numbered carrier families")

# Content-bearing span events go too, so the store keeps the error signal
# without the provider payload the exception event carries.
events = processors.get("filter/output-view-lean-events", {}).get("trace_conditions") or []
if not any("spanevent.name" in condition and "exception" in condition for condition in events):
    problems.append("the lean view keeps content-bearing span events")

# Latitude's documented GenAI shape uses canonical span attributes. The
# destination view must not rewrite or delete those fields.
latitude = processors.get("transform/output-view-latitude", {})
span_bridge = [
    statement
    for block in latitude.get("trace_statements") or []
    if block.get("context") == "span"
    for statement in block.get("statements") or []
]
event_bridge = [
    statement
    for block in latitude.get("trace_statements") or []
    if block.get("context") == "spanevent"
    for statement in block.get("statements") or []
]

for canonical in ("gen_ai.input.messages", "gen_ai.output.messages", "gen_ai.system_instructions"):
    if any(f'delete_key(span.attributes, "{canonical}")' in statement for statement in span_bridge):
        problems.append(f"the Latitude view deletes canonical field {canonical}")


def find_statement(statements, prefix):
    return next((statement for statement in statements if statement.startswith(prefix)), None)

# The 1.36 event-carrier path remains as a fallback when spans have no message
# attributes; system instructions remain the same canonical field.
for legacy, canonical in (("gen_ai.prompt", "gen_ai.input.messages"), ("gen_ai.completion", "gen_ai.output.messages")):
    fallback = find_statement(event_bridge, f'set(span.attributes["{legacy}"]')
    if fallback is None or f'span.attributes["{canonical}"] == nil' not in fallback:
        problems.append(f"the Latitude event fallback does not guard {legacy} against canonical messages")
instructions = find_statement(event_bridge, 'set(span.attributes["gen_ai.system_instructions"]')
if instructions is None or 'span.attributes["gen_ai.system_instructions"] == nil' not in instructions:
    problems.append("the Latitude event fallback does not preserve existing system instructions")

# The AI route is one explicit three-signal audience. General lanes and
# producer identity remain separate; each AI signal carries the fixed resource
# marker through its selected output pipeline.
route = payload.get("route") or {}
if sorted(route.get("signals") or []) != ["logs", "metrics", "traces"]:
    problems.append(f"AI route signals are {route.get('signals')}, expected logs/metrics/traces")
for signal, destinations in {
    "logs": ["victorialogs"],
    "metrics": ["victoriametrics"],
}.items():
    if route.get("pipelines", {}).get(signal) != destinations:
        problems.append(f"AI route {signal} destinations are {route.get('pipelines', {}).get(signal)}, expected {destinations}")

marker = processors.get("transform/route-ai-marker", {})
expected_marker_statements = {
    "trace_statements": ['delete_key(span.attributes, "telemetry.route")', 'set(resource.attributes["telemetry.route"], "ai")'],
    "metric_statements": ['delete_key(datapoint.attributes, "telemetry.route")', 'set(resource.attributes["telemetry.route"], "ai")'],
    "log_statements": ['delete_key(log.attributes, "telemetry.route")', 'set(resource.attributes["telemetry.route"], "ai")'],
}
for field, expected_statements in expected_marker_statements.items():
    blocks = marker.get(field) or []
    flat = [s for b in blocks for s in b.get("statements", [])]
    if flat != expected_statements:
        problems.append(f"AI route marker {field} is {flat}")
for name in ("traces/route-ai", "traces/route-ai-lean", "traces/route-ai-latitude", "metrics/route-ai", "logs/route-ai"):
    chain = pipelines.get(name, {}).get("processors", [])
    if chain.count("transform/route-ai-marker") != 1:
        problems.append(f"{name} must apply the marker exactly once, got {chain}")

logs = processors.get("transform/output-view-logs", {}).get("log_statements") or []
log_statements = [s for block in logs for s in block.get("statements", [])]
for name in ("logs", "logs/ingress", "logs/route-ai"):
    chain = pipelines.get(name, {}).get("processors", [])
    if chain.count("transform/output-view-logs") != 1:
        problems.append(f"{name} must apply default-deny log redaction exactly once, got {chain}")
for name in ("traces", "traces/ingress", "metrics", "metrics/ingress", "logs", "logs/ingress"):
    chain = pipelines.get(name, {}).get("processors", [])
    if chain.count("transform/drop-general-route-marker") != 1:
        problems.append(f"{name} must remove producer-supplied telemetry.route, got {chain}")
if any("transform/route-ai-marker" in pipelines.get(name, {}).get("processors", []) for name in ("traces", "metrics", "logs")):
    problems.append("general signal pipelines must not carry the AI route marker")
general_marker = processors.get("transform/drop-general-route-marker", {})
for signal, context in (("trace_statements", "span"), ("metric_statements", "datapoint"), ("log_statements", "resource")):
    blocks = general_marker.get(signal) or []
    statements = [s for block in blocks for s in block.get("statements", [])]
    if 'delete_key(resource.attributes, "telemetry.route")' not in statements:
        problems.append(f"general {signal} must drop producer-supplied resource telemetry.route")
    if context != "resource" and f'delete_key({context}.attributes, "telemetry.route")' not in statements:
        problems.append(f"general {signal} must drop producer-supplied signal telemetry.route")
for required in (
    'set(log.attributes["trace_flags"], log.flags)',
    'keep_keys(log.attributes, ["trace_flags"])',
    'keep_keys(resource.attributes, ["telemetry.route", "host.name", "service.name", "deployment.environment.name"])',
    'keep_keys(scope.attributes, [])',
):
    if required not in log_statements:
        problems.append(f"VictoriaLogs output is not default-deny; missing {required}")
logs_exporter = (payload.get("exporters") or {}).get("otlphttp/route-ai-victorialogs", {})
expected_logs_url = "http://127.0.0.1:9428/insert/opentelemetry/v1/logs"
if logs_exporter.get("logs_endpoint") != expected_logs_url:
    problems.append(f"VictoriaLogs route endpoint is {logs_exporter.get('logs_endpoint')}, expected {expected_logs_url}")

if problems:
    for problem in problems:
        print(f"  - {problem}", file=sys.stderr)
    sys.exit(1)

print(
    f"check-telemetry-view-composition: PASS (home-forge: {len(views)} views, "
    f"{len(expected)} route pipelines, guard non-vacuous)"
)
PYEOF
