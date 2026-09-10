# Delta Spec: Internal Service Auth

## ADDED Requirements

### Requirement: Beszel agent enrollment SHALL be owned by the observability-agent aspect
Beszel agent authentication and enrollment SHALL be owned by the observability-agent aspect that hosts select explicitly, sourcing `KEY` from shared common secret scope and `TOKEN` from host-scoped secret scope, and SHALL gate enrollment when the host-scoped secret is absent during bootstrap. The aspect SHALL derive the conventional host secret path `secrets/hosts/${hostName}/system.yaml` and set `services.beszel-agent-auth.secretFiles.host` to it.

#### Scenario: Host selects the observability-agent aspect
- **WHEN** a host selects the observability-agent aspect
- **THEN** Beszel agent auth wiring is provided by the aspect with `KEY` sourced from `secrets/common.yaml` and `TOKEN` sourced from the derived `secrets/hosts/<host>/system.yaml` path
- **AND** the host assembly does not repeat the Beszel agent leaf import, enablement, or `secretFiles.host` binding

#### Scenario: Host secret is absent during bootstrap
- **WHEN** a host is bootstrapped before its host-scoped Beszel `TOKEN` secret has been added
- **THEN** the observability-agent aspect gates Beszel agent enrollment on the derived conventional path without failing the base activation
- **AND** enrollment activates once the host-scoped secret exists, preserving the two-step secret bootstrap behavior