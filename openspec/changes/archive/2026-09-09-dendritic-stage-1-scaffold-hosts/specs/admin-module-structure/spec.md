## MODIFIED Requirements

### Requirement: Admin modules SHALL follow layered ownership boundaries
Admin configuration SHALL follow a layered structure where policy data remains under `policy/`, policy transformation logic remains under `lib/`, service-owned behavior is implemented directly in `modules/services/admin/`, application composition remains in the portable `modules/applications/admin/` layer, and host-local assembly remains under `modules/hosts/<host>/`. Thin forwarding wrappers that only proxy admin-owned services into generic service modules SHALL NOT be the canonical implementation boundary, and thin application composition splits that only separate tightly coupled admin glue SHALL be merged back into the portable admin composition module.

#### Scenario: Admin module tree is reviewed
- **WHEN** operators inspect admin-related repository paths
- **THEN** service-owned admin logic is located under `modules/services/admin/`
- **AND** `applications.admin` composition is located under `modules/applications/admin/`
- **AND** host-local admin overlays are located beside their host under `modules/hosts/<host>/`
- **AND** policy data and transforms are not embedded in service or host files
- **AND** admin-owned services do not rely on redundant generic wrapper modules as their primary implementation path
- **AND** trivial split composition files are not required for tightly coupled portable admin wiring
