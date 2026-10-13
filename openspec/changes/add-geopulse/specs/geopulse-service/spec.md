# Spec Delta

## Purpose

Provide recoverable personal location history on OCI through a reproducible native service, authenticated browser access and separately authenticated device ingestion.

## ADDED Requirements

### Requirement: Native service placement
GeoPulse SHALL run as a native backend with a static frontend on OCI ARM64. Its route and listeners SHALL agree with canonical web policy; internal listeners SHALL remain loopback-only. Other hosts SHALL NOT acquire the workload by importing its contracts.

#### Scenario: OCI deployment is realized
- **WHEN** OCI selects the GeoPulse aspect
- **THEN** its frontend and backend run from pinned package outputs behind the declared route
- **AND** no container image or public backend socket is required

### Requirement: Browser login retains PKCE enforcement
Browser login SHALL use Kanidm authorization-code authentication with S256 PKCE, state and nonce validation. Identity scopes SHALL be limited to `openid profile email` for the `users` group. PKCE enforcement SHALL NOT be disabled to accommodate the application.

#### Scenario: Owner signs in
- **WHEN** an authorized owner completes login
- **THEN** the callback exchanges the code using the verifier belonging to that login attempt
- **AND** the session is mapped by provider and subject

#### Scenario: Invalid callback is rejected
- **WHEN** a callback has missing, expired or reused state, or the token exchange has the wrong verifier
- **THEN** no application session is issued

### Requirement: Public exposure follows private bootstrap
The initial administrator and OIDC provider SHALL be configured while GeoPulse remains private. Public activation SHALL require verified owner access and closed password and OIDC registration. Device API access SHALL NOT depend on an interactive Cloudflare Access session.

#### Scenario: Initial installation
- **WHEN** the database has no administrator
- **THEN** public routing remains disabled while the operator creates the owner account and configures identity

#### Scenario: Bootstrap is accepted
- **WHEN** the owner has verified login and database-owned registration restrictions
- **THEN** the operator can explicitly enable the public route without opening registration to strangers

### Requirement: Device sources are authenticated independently
Each enabled device source SHALL authenticate with its own application credential and attribute accepted locations to the owner. Unauthenticated and invalid-credential submissions SHALL be rejected. First deployment SHALL be single-user; opaque-bearer sources SHALL remain unaccepted until verified on the real HTTP path.

#### Scenario: Basic-authenticated source submits a location
- **WHEN** the configured owner source submits a valid location with its correct credentials
- **THEN** the location is stored for that owner
- **AND** changing or omitting the credentials prevents ingestion

### Requirement: Database and encryption state are recoverable
GeoPulse SHALL use a dedicated non-superuser database role with required spatial extensions provisioned separately. Signing and encryption keys SHALL remain outside package outputs. Recovery SHALL preserve location history and the key needed to decrypt database-held identity credentials; upgrades SHALL require a pre-migration database export.

#### Scenario: Restore after service loss
- **WHEN** the operator restores the database and the original encryption key
- **THEN** the owner history and encrypted provider credentials remain usable

#### Scenario: Upgrade changes the schema
- **WHEN** a new backend starts automatic migrations
- **THEN** a pre-upgrade export exists before activation
- **AND** recovery documentation does not claim a Nix generation rollback reverses schema migration

### Requirement: Unneeded public surfaces remain closed
The public deployment SHALL block operational metrics, unnecessary diagnostic, geocoding, sharing and MCP endpoints unless separately approved. AI and MQTT SHALL remain disabled or inaccessible in the first deployment.

#### Scenario: Public client requests an operational endpoint
- **WHEN** a public request targets blocked metrics or diagnostic routes
- **THEN** the edge refuses the request rather than exposing backend data
