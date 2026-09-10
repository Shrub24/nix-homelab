# internal-service-auth Specification

## Purpose
TBD - created by archiving change service-to-service-auth-wiring. Update Purpose after archive.

## Requirements

### Requirement: Caller-owned service-to-service auth inventory SHALL be explicit
Internal service-to-service authentication metadata SHALL be owned by the caller application module and SHALL define per-integration auth method and secret references.

#### Scenario: Homepage integration auth inventory is evaluated
- **WHEN** Homepage integrations are rendered
- **THEN** each authenticated integration declares caller-owned auth inputs and method selection in Homepage-owned module files
- **AND** caller integration auth metadata is not required to be encoded in route policy files

### Requirement: Internal auth method selection SHALL prefer least privilege by integration
For each internal integration, the system SHALL select auth in this order unless explicitly overridden: local-only no-auth exception, native API token/key, app machine credential, username/password fallback.

#### Scenario: Integration supports native token auth
- **WHEN** a target integration supports API token or key authentication
- **THEN** caller wiring uses token/key auth
- **AND** username/password is not the default selection

#### Scenario: Integration does not support token auth
- **WHEN** no native token/key or machine credential path is available
- **THEN** caller wiring may use username/password as explicit fallback

### Requirement: Service-to-service secrets SHALL remain host-scoped by default
Credentials used for caller-owned internal integrations SHALL be defined in explicit service-, application-, or host-exception-scoped secret files according to integration ownership and SHALL NOT be promoted to unrelated shared scope without explicit justification.

#### Scenario: Homepage integration credentials are declared
- **WHEN** new Homepage or related integration credentials are added
- **THEN** they are sourced from an explicit feature-owned secret scope and templated for runtime use
- **AND** they are not introduced in unrelated shared/common secret scope by default

### Requirement: Beszel agent auth SHALL use shared KEY and host-scoped TOKEN
Beszel agent SSH auth SHALL source `KEY` from shared common secret scope and source `TOKEN` from host-scoped secret scope, while remaining injected via runtime environment template.

#### Scenario: Beszel agent auth is configured on a host
- **WHEN** an origin host enables Beszel agent connectivity to the Beszel hub
- **THEN** `KEY` is sourced from `secrets/common.yaml` and `TOKEN` is sourced from `hosts/<host>/secrets.yaml`
- **AND** each host may use a distinct Beszel system token

### Requirement: Beszel agent auth wiring SHALL be reusable and host-configurable
Beszel agent auth wiring SHALL be implemented as a reusable module that hosts can enable/configure explicitly, rather than hardcoding agent wiring in one host file.

#### Scenario: New host needs Beszel agent enrollment
- **WHEN** a host chooses to enroll in Beszel agent monitoring
- **THEN** the host enables a shared Beszel agent auth module and sets host token secret source configuration
- **AND** the host does not require copy/paste of bespoke agent wiring logic from another host file

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
