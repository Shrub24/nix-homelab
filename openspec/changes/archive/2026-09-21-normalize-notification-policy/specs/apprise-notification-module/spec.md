## ADDED Requirements

### Requirement: Generic notification mechanics SHALL consume explicit policy contracts

The notification daemon, CLI, and systemd integration SHALL implement generic dispatch and hook mechanics while consuming fleet-specific routing, destination, and authorization values through typed configuration.

#### Scenario: Notification implementation is inspected

- **WHEN** package and module sources are reviewed
- **THEN** no active fleet host list is embedded in the generic implementation
- **AND** ntfy publisher membership is supplied by homelab policy
- **AND** secret values remain runtime-only inputs
