# Delta Spec: Feature Topology

## ADDED Requirements

### Requirement: Host assemblies SHALL delegate conventional secret defaults and stable interconnections to owning modules
Thin host assemblies SHALL own feature selection and explicit exceptions only. Conventional host-scoped secret sources (for example the host `system.yaml` scope for host-scoped service secrets) and stable service-to-service interconnections SHALL be supplied by the owning service or application module as typed defaults, and hosts SHALL override them only through the owning module's explicit contract surface.

#### Scenario: Host enables a service with a conventional host-scoped secret source
- **WHEN** a host enables a service whose secrets conventionally live in that host's system secret scope
- **THEN** the owning module supplies the conventional secret source as a typed default
- **AND** the host file does not repeat the raw secret registration or path literal

#### Scenario: Host declares an explicit secret exception
- **WHEN** a host needs a non-conventional secret source or interconnection for an enabled feature
- **THEN** the host overrides through the owning module's explicit contract input
- **AND** the exception remains visible in the host assembly rather than being silently merged

### Requirement: Stable service interconnections SHALL be owned by the providing module
Stable cross-service runtime wiring (such as a notification dispatcher pointing at the canonical ntfy origin, or a cache consumer pointing at the cache host) SHALL be owned by the providing service or application module and SHALL resolve from canonical policy or catalog metadata rather than being repeated per host.

#### Scenario: Notification dispatch is wired to the canonical ntfy origin
- **WHEN** a host enables notification dispatch to ntfy
- **THEN** the ntfy origin resolves from the providing module's canonical default
- **AND** host files do not duplicate the server URL or origin literal

#### Scenario: Host changes a stable interconnection
- **WHEN** a host must point a stable interconnection at an alternative target
- **THEN** the change is expressed as an explicit host-level override of the providing module's contract
- **AND** the override is visible and documented rather than a silent per-host copy
