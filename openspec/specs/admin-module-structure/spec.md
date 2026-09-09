# admin-module-structure Specification

## Purpose

Define the layered ownership boundaries for admin configuration, from policy data and transforms through service-owned modules, portable application composition, and host-local assembly.

## Requirements

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

### Requirement: Complex admin services SHALL support adjacent data files
Complex admin services with large declarative payloads SHALL support adjacent data/config files within service subdirectories to keep module logic focused and maintainable.

#### Scenario: Homepage and Gatus service modules are evaluated
- **WHEN** service module structure is reviewed
- **THEN** Homepage and Gatus support files are organized as service subdirectories with `default.nix` and adjacent data/helper files

### Requirement: Canonical endpoint values SHALL be consumed via policy projections
Admin modules SHALL consume canonical service endpoint values (including route path and origin port) through policy resolution/projection helpers rather than re-defining those values in multiple module locations.

#### Scenario: Admin consumer wiring is evaluated
- **WHEN** admin service or monitoring modules configure route/endpoint values
- **THEN** path and port values are sourced from resolved policy/projection outputs
- **AND** equivalent literals are not duplicated in unrelated module files
