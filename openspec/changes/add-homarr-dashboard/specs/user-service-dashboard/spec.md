# Spec Delta

## Purpose
Provide a user-facing Homarr dashboard for discovering and entering fleet services. Homarr authenticates individual people through Kanidm OIDC and owns its editable users, boards, permissions, and presentation state independently of the operator Homepage.

## ADDED Requirements

### Requirement: Homarr SHALL provide an individual OIDC-authenticated user dashboard
The user-facing Homarr service SHALL authenticate users through the canonical Kanidm OIDC client and SHALL retain separate Homarr identities for separate OIDC users. Browser access SHALL not be anonymous and SHALL not depend on a shared account. A bootstrap procedure SHALL establish the first administrator without leaving an unintended permanent local-authentication bypass.

#### Scenario: An authorized user signs in
- **WHEN** a user with an enabled Kanidm identity visits the Homarr service and completes OIDC authentication
- **THEN** Homarr establishes that person's own account and session
- **AND** the account is not shared with another user

#### Scenario: User-specific access and boards are managed
- **WHEN** the Homarr administrator or a user changes permitted board access or the user's home board
- **THEN** the change applies to the intended Homarr user or explicitly selected group
- **AND** another user's private board access and personal home-board selection remain independent

#### Scenario: Unauthenticated service access is attempted
- **WHEN** a browser requests Homarr without a valid Homarr session
- **THEN** Homarr requires authentication before displaying user dashboard content

#### Scenario: The temporary credentials bootstrap is disabled by default
- **WHEN** Homarr runs in steady state
- **THEN** only the Kanidm OIDC provider is enabled
- **AND** dangerous automatic credential linking is disabled

### Requirement: Homarr SHALL keep first-administrator setup private until OIDC is verified
The public route SHALL remain withheld while the operator creates the initial administrator and verifies Kanidm OIDC through the provider's private Tailscale Serve endpoint. The temporary credentials provider SHALL not remain enabled when the public route is released.

#### Scenario: The initial administrator is bootstrapped privately
- **WHEN** the operator performs first-user setup
- **THEN** the public route is withheld
- **AND** temporary credentials authentication is available only through the private Tailscale endpoint

#### Scenario: Public release follows private OIDC acceptance
- **WHEN** the Kanidm-backed administrator and per-user access have been verified
- **THEN** the temporary credentials provider is disabled before or with public route release

### Requirement: Homarr SHALL serve as a user-facing service catalogue without becoming endpoint policy
The Homarr instance SHALL present a user-oriented landing board and catalogue for services selected by its operator. Its app entries, layout, groups, and per-user boards MAY be edited in Homarr and SHALL persist across service restarts. They SHALL NOT become a second source of canonical service origins, placement, or ingress policy.

#### Scenario: A user opens a service from a board
- **WHEN** an authorized user follows a configured service entry
- **THEN** the browser is sent to the user-facing URL configured for that entry
- **AND** canonical routing and access controls remain owned by the fleet's existing service policy

#### Scenario: Imperative dashboard configuration survives restart
- **WHEN** Homarr is restarted or its container is recreated with the same persistent data
- **THEN** Homarr retains its users, boards, permissions, catalogue entries, and per-user home-board choices

### Requirement: Homarr SHALL remain distinct from the operator Homepage
The user-facing Homarr service SHALL be separately placed and independently configured from the existing operator Homepage service. It SHALL NOT replace, merge with, or require changes to the operator Homepage.

#### Scenario: Both dashboards are active
- **WHEN** Homarr is enabled for users on `oci-melb-1`
- **THEN** the existing `admin-homepage` service remains independently available on `la-admin-1`
- **AND** either dashboard may be changed or restarted without changing the other's configuration or state

### Requirement: Homarr state SHALL be recoverable without granting host-control access
The persistent Homarr state, including user accounts, boards, integration configuration, and encryption-dependent data, SHALL be included in the service's recovery contract. Homarr SHALL NOT require the host container-runtime socket merely to present its user-facing service catalogue.

#### Scenario: Homarr state is captured for recovery
- **WHEN** the fleet captures mutable service state
- **THEN** Homarr's persistent application data is included in its declared recovery scope
- **AND** a restore retains the matching `SECRET_ENCRYPTION_KEY` needed to read encrypted Homarr values
- **AND** it retains the matching `AUTH_SECRET` so existing Auth.js sessions remain valid across container replacement

#### Scenario: Homarr container permissions are reviewed
- **WHEN** the Homarr runtime is evaluated
- **THEN** it has no Docker or Podman socket mount unless a later, explicitly approved feature requires runtime discovery
