# admin-module-structure Specification

## Purpose

Define the layered ownership boundaries for admin configuration, from policy data and transforms through service-owned modules, portable application composition, and host-local assembly.

## Requirements

### Requirement: Admin modules SHALL follow layered ownership boundaries
Admin configuration SHALL keep policy data under `policy/`, policy transformation logic under `lib/`, and service-owned behavior in concern-owned private implementations. Deployment composition SHALL be published by the discovered `identity-provider`, `cockpit`, and `admin-hub` contributors rather than retained under a permanent `modules/applications/admin/` evaluator-class root. Host-local assembly SHALL retain only explicit variants and machine-specific exceptions under `modules/hosts/<host>/`.

#### Scenario: Admin module tree is reviewed
- **WHEN** operators inspect admin-related repository paths
- **THEN** Kanidm server/provisioning composition is owned by the `identity-provider` concern
- **AND** independently placed Cockpit composition is owned by the `cockpit` concern
- **AND** the coupled Termix, Vaultwarden, Homepage, Gatus, Beszel hub, Webhook, and current Quantum policy are owned by the `admin-hub` concern
- **AND** private service implementations are located beside those concern owners or remain temporarily under the service migration root
- **AND** host-local admin overlays contain only genuine host variants and do not directly import implementations
- **AND** policy data and transforms are not embedded in service or host files
- **AND** no `modules/applications/admin/` compatibility wrapper remains

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
