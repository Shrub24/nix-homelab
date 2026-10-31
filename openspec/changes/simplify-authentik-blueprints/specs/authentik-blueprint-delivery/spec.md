# Spec Delta

## Purpose

Deliver repository-owned Authentik blueprints reproducibly and make invalid or unapplied changes fail deployment without changing accepted authentication behaviour. This complements AI-5 in the pending authentik-identity capability.

## ADDED Requirements

### Requirement: Blueprint authoring SHALL preserve identity behaviour and runtime secret boundaries

BD-1: Static identity definitions and fleet-derived registrations SHALL produce one deterministic blueprint. Refactoring source representation SHALL preserve object identity, credentials ownership, public issuer/callback URLs and accepted login behaviour. Secret expressions SHALL remain unresolved outside the runtime environment.

#### Scenario: Source representation changes

- **WHEN** static flows are moved from generated data to native YAML
- **THEN** the resulting entries preserve their identifiers, desired states, expressions and reference relationships
- **AND** no plaintext runtime credential enters the built document

### Requirement: Structural validation SHALL use the selected release contract

BD-2: Build validation SHALL use the blueprint schema supplied by the selected Authentik release. Supported tagged expressions MAY be deferred without resolution, but that exemption SHALL NOT suppress validation of literal siblings or surrounding structure. Unknown tags SHALL fail explicitly.

#### Scenario: Tagged foreign key with invalid neighbouring literal

- **WHEN** an entry contains a supported unresolved reference and a literal value that violates the release schema
- **THEN** validation rejects the literal value
- **AND** it does not reject the reference merely for lacking its runtime database type

#### Scenario: Unknown expression tag

- **WHEN** a blueprint contains an unsupported custom tag
- **THEN** structural validation fails rather than treating it as an unconstrained value

### Requirement: Blueprint provisioning failure SHALL fail deployment within a bounded time

BD-3: A deployment changing the provisioned blueprint SHALL run the selected release's database-backed validation and SHALL require successful application of the current document. Validation failure, application failure and deadline expiry SHALL produce a nonzero result observed by activation. A status for earlier content SHALL NOT satisfy the gate. Validation SHALL NOT depend on the public edge or expose credential values in diagnostics.

#### Scenario: Reference cannot resolve

- **WHEN** the shipped blueprint references an object unavailable after prerequisite provisioning
- **THEN** database-backed validation fails and deployment reports failure within its deadline
- **AND** the validation step does not commit its database trial changes

#### Scenario: Worker reports success for previous content

- **WHEN** the recorded blueprint is successful but its applied content hash differs from the shipped document
- **THEN** deployment does not report provisioning success
- **AND** it fails if current content is not successfully applied before the deadline

#### Scenario: Provider not provisioned

- **WHEN** a host does not realize a provisioned Authentik runtime
- **THEN** the blueprint gate does not start or require provider credentials on that host

#### Scenario: Valid document is applied

- **WHEN** validation succeeds and the current document is successfully applied
- **THEN** the deployment gate exits successfully without contacting the public identity hostname

### Requirement: Deployment acceptance SHALL remain bounded to provisioning

BD-4: The gate SHALL have a finite total runtime and SHALL NOT perform schema upgrades, provider cutovers or secret creation. System-generation rollback SHALL NOT be represented as reversing committed identity database changes. Browser authentication acceptance SHALL remain distinct from blueprint application acceptance.

#### Scenario: Deployment reports provisioning success

- **WHEN** the current document passes the deployment gate
- **THEN** that result establishes blueprint application only
- **AND** browser login acceptance and database recovery retain their separate procedures
