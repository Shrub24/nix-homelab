## ADDED Requirements

### Requirement: Runtime relationship contributions SHALL be owned by participating capabilities

A capability that owns a runtime unit SHALL also own its additive participation in cross-cutting relationships such as service monitoring. Host configurations and infrastructure providers SHALL NOT maintain reverse indexes of remotely placed workload units.

#### Scenario: Capability moves between hosts

- **WHEN** a capability containing monitored units moves from one host selection to another
- **THEN** its monitoring contributions move with the capability
- **AND** the former host retains no monitor-generated fragments for those units
- **AND** the new host does not require a separate service-name list update
