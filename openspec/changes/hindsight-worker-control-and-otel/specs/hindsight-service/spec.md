## Purpose

Define the Hindsight service's background-worker operating mode and its integration with the fleet's OpenTelemetry trace pipeline, while keeping API availability and trace-data handling explicit.

## ADDED Requirements

### Requirement: Hindsight background work can be disabled independently of the API

The Hindsight service SHALL support an explicitly disabled background worker while keeping its API and control plane available. In this mode, the worker SHALL NOT claim or execute queued asynchronous operations.

#### Scenario: Home-forge runs Hindsight with background processing disabled

- **WHEN** the Hindsight service starts with background processing disabled
- **THEN** its API and control-plane endpoints remain available
- **AND** its worker does not claim or execute pending operations
- **AND** the worker state is visible in the rendered container configuration

### Requirement: Hindsight traces use the fleet OTLP pipeline

When trace export is enabled, Hindsight SHALL export API trace spans over OTLP/HTTP to the fleet telemetry collector using a stable service identity. The selected collector endpoint SHALL be reachable over the private fleet network and SHALL deliver traces to the destinations selected by that collector's policy.

#### Scenario: Hindsight API emits a trace

- **WHEN** an API operation runs with trace export enabled
- **THEN** a span with the Hindsight service identity is accepted by the selected fleet collector
- **AND** the trace is observable in each destination configured for that collector
- **AND** trace payload handling is explicit because upstream spans may contain LLM prompt and completion content

### Requirement: Hindsight queue cleanup is status-scoped

A one-time cleanup of Hindsight asynchronous operations SHALL affect only rows in the pending and failed states after background processing is disabled. Completed and cancelled operations, memory records, and other service data SHALL remain untouched.

#### Scenario: Operator clears stale pending and failed operations

- **WHEN** the worker-off state has been verified and the queue cleanup is performed
- **THEN** pending and failed asynchronous-operation rows are removed
- **AND** completed and cancelled operation rows and Hindsight memory data remain unchanged
- **AND** the resulting pending and failed counts are zero
