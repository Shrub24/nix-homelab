# Delta Spec: Admin Services

## ADDED Requirements

### Requirement: Cockpit service-user wiring SHALL be module-owned
Cockpit service-user wiring (service-user enablement, name, deny-ssh posture, and password-hash secret source) SHALL be owned by the Cockpit admin service module with a conventional host-scoped default, so per-host `cockpit-auth.nix` overlays contain only genuine host-specific values.

#### Scenario: Host enables Cockpit with the conventional service user
- **WHEN** a host enables Cockpit
- **THEN** the service-user contract resolves from the Cockpit module's default with the host's conventional password-hash secret source
- **AND** the host overlay does not repeat service-user wiring

#### Scenario: Redundant host override is removed after equivalence proof
- **WHEN** a host overlay sets a value identical to the module default
- **THEN** the override may be removed only after evaluation equivalence is proven
- **AND** removal lands in the same change batch as the proof
