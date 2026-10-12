# Spec Delta

## Purpose

Define what host-level telemetry producers this fleet runs, what identity their series and log records carry, and how an adopted upstream contract is held by effective value rather than by the presence of a flag.

## ADDED Requirements

### Requirement: Host telemetry SHALL join to the canonical host ID

Every host SHALL emit host-associated telemetry under an identity derived from `networking.hostName`, so that an OTLP record, a scraped series and a shipped journal record all resolve to the canonical host ID used by the fleet inventory, deploy metadata and web policy. The fleet SHALL NOT declare a second host-naming authority for telemetry, and SHALL leave the environment label unset while the fleet has no environment concept.

#### Scenario: A metric series is attributed

- **WHEN** a host's metrics are scraped or exported
- **THEN** the series carry the host's canonical ID as the host identity label

#### Scenario: A journal record is attributed

- **WHEN** a host ships a journal record through the logs lane
- **THEN** the record's host label resolves to the same canonical ID

### Requirement: The node exporter SHALL report unit state

Hosts running the node exporter SHALL collect systemd unit state, so that unit health is observable in the fleet's metrics store rather than only in the journal, and the exporter SHALL keep running on its ordinary static account with the address-family allowance the public system DBus API requires.

#### Scenario: Unit state is collected

- **WHEN** the node exporter runs on a host
- **THEN** the rendered unit invokes the systemd collector and the service allows `AF_UNIX`
- **AND** the collector reports success and unit-state series are available

### Requirement: The Tailscale daemon's metrics SHALL be scraped where metrics are shipped

A host that ships metrics SHALL scrape the Tailscale daemon's own endpoint on the tailnet-local address, so tailnet health is visible in the fleet's metrics store without a node-local exporter or a newly granted privilege.

#### Scenario: The scrape job is realized

- **WHEN** a host selects the metrics lane
- **THEN** the scrape configuration carries a tailscale job targeting the tailnet-local metrics address

#### Scenario: The scrape reports real daemon metrics

- **WHEN** the tailscale scrape is verified on a host
- **THEN** a daemon-specific metric series is present
- **AND** a bare successful HTTP status is not accepted as proof, because the client fallback can answer with a page instead of metrics

### Requirement: A consumer's own collector selection SHALL extend, not replace, the contributed collector

The node exporter collector set SHALL compose additively: a host that states its own collector list SHALL still receive the collector the shared contract contributes. Deliberate removal SHALL use the native disabled-collector option, and full replacement SHALL require an explicit forced override.

#### Scenario: A host states its own collectors

- **WHEN** a host declares its own enabled-collector list
- **THEN** the effective set contains both the host's entries and the contributed collector
- **AND** the rendered unit keeps the systemd collector invocation

### Requirement: Journal shipping SHALL correlate records with traces

A host shipping journal records SHALL normalize exact trace and span identifiers from the record's own fields, preserving messages and metadata, so a journal record can be joined to the trace it belongs to. Normalization SHALL apply only to well-formed identifiers and SHALL be disableable by configuration.

#### Scenario: A correlated record is shipped

- **WHEN** a journal record carries a well-formed trace or span identifier
- **THEN** the shipped record exposes that identifier in normalized form and its message is unchanged

#### Scenario: An uncorrelated record is shipped

- **WHEN** a journal record carries no identifier, or a malformed one
- **THEN** the record is shipped unchanged and normalization adds nothing

### Requirement: An adopted host-observability contract SHALL be pinned by effective value

Adoption of an upstream host-observability contract SHALL be verified on the effective configuration — the collector set, the rendered exporter unit, the realized scrape job and its labels, the identity values and the journal default — and not by the presence of a flag or a declaration. The verification SHALL include a composition case in which a consumer states its own collector list.

#### Scenario: The contribution form regresses

- **WHEN** the contributed collector is defined so that a consumer's list replaces it
- **THEN** the effective-value check fails, including the composition case

#### Scenario: The contract is adopted

- **WHEN** the pin move is verified
- **THEN** every host's effective values match the pinned expectations
- **AND** the verification is repeated for a host that states its own collector list
