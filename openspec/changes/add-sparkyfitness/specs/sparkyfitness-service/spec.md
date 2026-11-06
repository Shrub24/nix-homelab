# SparkyFitness Service

## Purpose

Provide the fleet's fitness and nutrition application with one authenticated public origin, isolated database access and a recovery path for records and uploaded files.

## ADDED Requirements

### Requirement: SF-1 — The fitness application SHALL have one public application origin

The fleet SHALL serve SparkyFitness at `https://fit.shrublab.xyz` on `oci-melb-1`. Browser pages, API calls, uploaded files and supported discovery endpoints SHALL use that origin. The database and backend listener SHALL NOT be separately exposed to the public Internet.

#### Scenario: Browser and API reach the same application

- **WHEN** a user opens the fitness site and makes an authenticated application request
- **THEN** the frontend and API are reachable through the same HTTPS origin
- **AND** the request does not require a Cloudflare Access session or service token
- **AND** unauthenticated requests remain subject to the application's own authentication and authorization

#### Scenario: Application-specific routing survives fleet ingress

- **WHEN** a client requests an API path, an uploaded file or an upstream-supported discovery document through the public origin
- **THEN** the request reaches the responsible application handler rather than the frontend's HTML fallback

### Requirement: SF-2 — Sign-in SHALL use the fleet identity provider with explicit administrator authorization

Normal interactive sign-in SHALL use the fleet's Authentik OIDC client registration. An authorized new user SHALL be able to create an application account through SSO. Administrator status SHALL follow the declared administrator-group mapping rather than registration order. Local password login SHALL be disabled normally; a retained local administrator credential and an operator-controlled configuration override SHALL provide break-glass access without deleting user data.

#### Scenario: First approved user signs in

- **WHEN** a user allowed by the identity policy completes the application's OIDC sign-in
- **THEN** the callback returns to the public fitness origin and creates or resumes that user's account
- **AND** a user with the administrator claim receives application administrator access
- **AND** an approved user without that claim does not become administrator merely by signing in first

#### Scenario: Unapproved identity attempts access

- **WHEN** an identity not entitled to the fitness client attempts sign-in
- **THEN** it is denied access by the identity provider's application policy

#### Scenario: Identity provider is unavailable

- **WHEN** the operator temporarily re-enables the application's password login through its ordinary configuration and deploys
- **THEN** the retained local administrator can sign in without Authentik
- **AND** reverting that configuration disables the password path again without deleting accounts, records or uploads

### Requirement: SF-3 — Application database access SHALL preserve a migration owner and a restricted login

SparkyFitness SHALL use the fleet's native PostgreSQL substrate with separate migration-owner and application credentials. Provisioning and password rotation SHALL remain declarative. Neither credential SHALL require superuser or cluster-wide role-creation privileges, and the restricted login SHALL NOT own the database.

#### Scenario: Application starts against a fresh provisioned database

- **WHEN** database provisioning completes and SparkyFitness starts
- **THEN** migrations can create the application's schema as its database owner
- **AND** normal application operations authenticate with the separate restricted role
- **AND** neither role can authenticate to an unrelated consumer database

#### Scenario: Application password is rotated

- **WHEN** the operator updates the application's declared database credential and applies the configuration
- **THEN** PostgreSQL and the application converge on the same credential
- **AND** the application restarts successfully without acquiring role-management privileges or losing records

### Requirement: SF-4 — Records and uploaded files SHALL survive replacement and have a documented restore path

The fleet SHALL persist application-owned durable files under `/srv/data/sparkyfitness` and back them up together with the PostgreSQL substrate's logical export. Ephemeral working files SHALL NOT be presented as durable recovery inputs. Recovery SHALL retain the application encryption key and restore existing user records and uploaded files without requiring account recreation.

#### Scenario: Runtime is replaced

- **WHEN** the application containers are recreated from their declared release
- **THEN** existing fitness records and uploaded files remain available to their original user

#### Scenario: Backup is restored into an isolated instance

- **WHEN** the operator restores a recorded database export, corresponding durable files and the retained encryption key using the runbook
- **THEN** a previously recorded fitness entry and uploaded file are accessible after sign-in
- **AND** the runbook identifies the snapshot, application release and backup consistency limits used for that acceptance

### Requirement: SF-5 — Deployment inputs and failure reporting SHALL belong to the fleet

The application SHALL use pinned upstream release artifacts compatible with the fleet's ARM64 and AMD64 targets, service-scoped encrypted credentials and the fleet notification path for failed runtime units. Adding a deployment host SHALL NOT implicitly grant that host decryption access.

#### Scenario: Runtime fails

- **WHEN** an application unit reports failure
- **THEN** the fleet's registered failure-notification path receives that outcome

#### Scenario: New host is added to the fleet

- **WHEN** another host is declared without an explicit fitness-secret recipient change
- **THEN** it does not gain access to fitness database credentials, encryption keys or local administrator credentials

