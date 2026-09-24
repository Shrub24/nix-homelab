# Spec Delta

## Purpose

Define how AI-session telemetry is separated from general fleet telemetry at the collector gateway, while general and AI OTLP routes both reach their operational stores with fixed route provenance and safe log redaction.

## ADDED Requirements

### Requirement: AI observability backends SHALL receive only explicitly selected telemetry

Langfuse and Latitude SHALL receive traces through a named collector route that producers select deliberately. The general OTLP route SHALL export traces to VictoriaTraces, metrics to VictoriaMetrics, and logs to VictoriaLogs; it SHALL NOT export telemetry to any LLM-observability backend. The AI route SHALL explicitly select its trace, metric, and log destinations. Route destination selection SHALL be explicit and SHALL NOT inherit from the general route.

#### Scenario: General traffic is exported

- **WHEN** a producer emits traces, metrics, or logs to the general OTLP ingress
- **THEN** each signal reaches its operational store (VictoriaTraces, VictoriaMetrics, or VictoriaLogs)
- **AND** none is exported to Langfuse or Latitude

#### Scenario: Enrolled traffic is exported

- **WHEN** a producer sends traces, metrics, or logs to the AI route listener
- **THEN** each signal reaches only the route's explicitly selected destinations
- **AND** AI-route logs reach VictoriaLogs with resource `telemetry.route="ai"`
- **AND** the trace views preserve the existing per-destination behavior: the analysis backends receive each span's payload carriers as produced, while the trace store's copy carries none

### Requirement: The AI route SHALL be a dedicated listener with unaffected general ingress

The AI route SHALL bind its own declared listener, distinct from the general ingress socket, and SHALL NOT alter the general ingress address, ports, admission set or generated component names. Removing the route declaration SHALL remove its listener and its route-scoped exporters without changing general behaviour.

#### Scenario: Route membership changes

- **WHEN** the AI route declaration is added or removed
- **THEN** the general route's receiver, pipeline and exporter names remain unchanged
- **AND** general producers keep exporting to the same endpoint with their existing queue and WAL state intact

### Requirement: VictoriaLogs SHALL receive default-deny OTLP logs

Both OTLP routes SHALL send logs to VictoriaLogs. The Collector SHALL drop all record attributes except derived `trace_flags`, drop all scope attributes, and retain only resource host/service/environment identity plus the AI marker. It SHALL leave body, times, severity and trace/span IDs unchanged. It SHALL project native `log.flags` into `trace_flags`, which VictoriaLogs does not otherwise serialize.

#### Scenario: AI-route log fields are preserved

- **WHEN** an OTLP log with extra record/resource/scope attributes arrives on the AI listener
- **THEN** VictoriaLogs receives its body, event time as `_time`, severity, trace/span IDs and derived `trace_flags`
- **AND** arbitrary attributes are absent

#### Scenario: General-route log fields are preserved

- **WHEN** an OTLP log with extra attributes arrives on the general listener
- **THEN** VictoriaLogs receives its body, event time as `_time`, severity, trace/span IDs and derived `trace_flags`
- **AND** arbitrary attributes are absent

### Requirement: VictoriaLogs SHALL map OTLP timestamps without altering them

The Collector SHALL leave event and observed time fields unchanged. VictoriaLogs SHALL use event time as `_time`, falling back to observed time only when event time is absent; it does not persist both timestamps independently.

#### Scenario: Observed timestamp is the fallback

- **WHEN** an OTLP log has an observed timestamp but no event timestamp
- **THEN** VictoriaLogs `_time` is derived from the observed timestamp

### Requirement: The AI route marker SHALL be fixed receiver provenance

AI-route logs SHALL carry resource `telemetry.route="ai"`; producer-supplied values of this reserved key SHALL be removed before the fixed marker is set. General signal pipelines SHALL remove producer-supplied `telemetry.route` values and SHALL NOT set the AI marker. The marker means only that telemetry arrived on the AI route, not producer identity, AI classification, admission or authentication.

#### Scenario: Producer route attributes cannot override provenance

- **WHEN** a producer supplies `telemetry.route` in a record or signal attribute
- **THEN** the AI-route resource marker remains `ai` and the general pipeline has no route marker

### Requirement: Each AI-route destination SHALL receive the session shaped for it

The AI route SHALL carry one output view per destination over the same route receiver: the LLM-observability backends SHALL receive spans with their content carriers intact, and the fleet trace store SHALL receive the same spans with those carriers removed. Shaping SHALL NOT drop a span from any destination.

#### Scenario: A carrier-bearing span is exported

- **WHEN** a producer sends a span carrying prompt, completion or tool payload attributes to the AI route listener
- **THEN** the analysis backends receive that span with its carriers
- **AND** the trace store receives the same span with no message carrier and no content-bearing span event

#### Scenario: Route membership changes without the views

- **WHEN** the AI route's trace destination membership differs from the destinations the output-view composition partitions
- **THEN** evaluation fails with a named error rather than routing a destination through an accidental pipeline

### Requirement: Payload shaping SHALL NOT be presented as a producer boundary

The output views SHALL NOT be described as a producer boundary, an admission check or an authentication guarantee: every destination's pipeline consumes the same route receiver, so a producer that reaches the listener reaches all of them.

#### Scenario: The views are documented

- **WHEN** the output views are described in repository documentation or code comments
- **THEN** they are described as per-destination payload shaping over one input audience
- **AND** no span-level or producer-level filtering guarantee is claimed for them

### Requirement: Route selection SHALL NOT be presented as authenticated

The AI route SHALL provide routing separation only. Repository documentation and comments SHALL NOT describe the AI lane as authenticated, access-controlled or credential-gated while route admission is unimplemented upstream.

#### Scenario: Lane is documented

- **WHEN** the telemetry lanes are described in repository documentation
- **THEN** the AI lane is described as an explicitly selected route
- **AND** no authentication or access-control guarantee is claimed for it

### Requirement: Enrollment SHALL preserve per-destination exporter policy

Destination-scoped exporter settings — including each backend's credential binding, required headers and transport compatibility settings — SHALL apply identically to the route-scoped exporter instances, so a route never needs to restate a backend's contract.

#### Scenario: AI route exporters are configured

- **WHEN** the AI route's exporter instances are rendered
- **THEN** each carries its destination's credential, headers and transport settings
- **AND** the route declaration names destinations only
