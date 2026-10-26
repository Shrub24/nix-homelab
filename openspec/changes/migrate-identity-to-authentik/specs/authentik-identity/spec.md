# Spec Delta

## Purpose

Provide reproducible Authentik application identity with explicit client authorization policy, native blueprint workflows, UI-owned user lifecycle, and a recoverable transition from Kanidm.

## ADDED Requirements

### Requirement: Authentik runtime SHALL be selected explicitly and version coherent

AI-1: Selecting the Authentik provider SHALL realize its server, worker and declared database dependency from a pinned compatible implementation. Discovering its source or importing an OIDC client contract SHALL NOT activate that runtime. Version-sensitive blueprint generation and client projections SHALL be maintained with the selected provider implementation. Startup and blueprint application SHALL NOT depend on the public edge being available.

#### Scenario: Remote client evaluates without the server

- **WHEN** a consumer host imports the intrinsic OIDC contract for an approved Authentik client
- **THEN** its OIDC configuration resolves without Authentik server or worker units on that host
- **AND** no other host's evaluated NixOS configuration is required

#### Scenario: Identity host starts before route cutover

- **WHEN** the selected provider starts with its required runtime secrets and database while public routing still serves Kanidm
- **THEN** local readiness and provisioning can complete without contacting the canonical public edge
- **AND** blueprint application failure is observable separately from HTTP readiness

### Requirement: Authentik provisioning SHALL consume explicit registration policy independently of clients

AI-2: Approved registration policy SHALL be the authority for server applications, OAuth/OIDC providers, allowed callbacks, access groups and required claim mappings. Client-side realization SHALL consume the same policy independently. A registration MAY exist for a deselected application or an externally managed client. Consumer-host imports SHALL NOT create registration authority.

#### Scenario: Approved external client has no managed consumer module

- **WHEN** policy approves a Cloudflare Access client without a local relying-application module
- **THEN** the provider renders its registration and callback restrictions
- **AND** provisioning does not depend on a consumer host selecting an application aspect

#### Scenario: Unapproved application requests identity

- **WHEN** an enabled application requires a client absent from approved policy
- **THEN** evaluation fails with a named client-policy error
- **AND** no implicit server registration is created

### Requirement: Access permission and claim release SHALL remain distinct

AI-3: Application access SHALL enforce the policy's authorized groups independently of requested scopes and released claims. Generated group mappings SHALL preserve the required claim shape without releasing unrelated memberships by default. Unsupported policy semantics SHALL fail explicitly rather than being silently broadened or dropped.

#### Scenario: User lacks the allowed application group

- **WHEN** an authenticated user requests an application whose allowed groups exclude that user
- **THEN** Authentik denies application authorization even if the client requests valid profile or group scopes

#### Scenario: Approved group claim reaches an application

- **WHEN** an authorized user authenticates to an application requiring group names
- **THEN** the token or userinfo response contains the agreed group-name claim and value shape
- **AND** application role mapping is accepted against that shape

### Requirement: Declarative configuration SHALL preserve UI-owned user state

AI-4: Repository policy SHALL own group definitions, application access rules, client registration and explicitly managed flow configuration. Authentik's database and UI SHALL own people, invitations, credentials, recovery state and memberships. Blueprint reconciliation SHALL NOT replay Kanidm's authoritative person/membership overlay or overwrite fields assigned to UI ownership.

#### Scenario: Membership changes survive reapplication

- **WHEN** an administrator changes a user's membership in Authentik and the repository blueprints are reapplied
- **THEN** that membership change remains intact
- **AND** repository-owned client restrictions are reconciled

#### Scenario: Invitation-based enrollment completes

- **WHEN** an administrator issues an invitation and its recipient completes the configured enrollment flow
- **THEN** account creation and configured enrollment stages complete without editing repository person records
- **AND** an uninvited user cannot bypass an invitation-required enrollment policy

### Requirement: Native blueprints SHALL have explicit ownership and lifecycle

AI-5: The integration SHALL support Authentik-native flows, stages, policies, bindings and templates alongside generated common registrations. It SHALL declare required inter-blueprint dependencies explicitly and expose application failures. Retirement SHALL explicitly disable or delete previously provisioned objects; removing a source declaration or blueprint file alone SHALL NOT be reported as completed revocation.

#### Scenario: Dependent blueprints are applied

- **WHEN** an application references a repository-managed authorization flow or property mapping
- **THEN** dependency handling ensures the referenced objects exist before successful application is reported
- **AND** a failed apply does not count as successful provisioning

#### Scenario: A client is withdrawn

- **WHEN** an operator approves withdrawal of a previously provisioned client
- **THEN** the change includes explicit provider-side disablement or deletion and verifies rejection of new authorization attempts
- **AND** removal from the generated inventory alone is insufficient acceptance

### Requirement: Identity credentials SHALL remain runtime-only with explicit readership

AI-6: Provider bootstrap credentials, stable secret key, signing material, database credentials, SMTP credentials and OIDC client secrets SHALL be delivered through runtime secret interfaces, never plaintext Nix-store content or rendered diagnostics. Client and provider delivery SHALL use explicitly authorized sources and permissions. Logical credential sharing SHALL NOT implicitly widen SOPS readership.

#### Scenario: One confidential client is provisioned and consumed

- **WHEN** the server and relying application receive their credential inputs
- **THEN** both resolve the approved credential association through their own runtime paths
- **AND** neither requires the other's evaluated secret path or decrypted value at evaluation time

### Requirement: Authentik recovery SHALL restore identity state rather than only configuration

AI-7: Recovery SHALL cover the database, persistent assets and required stable encryption/signing material. Reapplying blueprints alone SHALL NOT qualify as restoring users, memberships, credentials or account links. A restore SHALL be verified in an isolated target before production cutover, and backup capture SHALL avoid inconsistent live database copies.

#### Scenario: Identity state is restored into an isolated target

- **WHEN** a version-compatible database export, persistent assets and required secret material are restored
- **THEN** a representative user, membership, application registration and login are verified
- **AND** the isolated target does not reconcile against or mutate production identity state

### Requirement: Production identity cutover SHALL require account and host-access acceptance

AI-8: The policy-derived IdP SHALL remain outside its own Cloudflare Access gate. Cutover SHALL require operator approval and evidence of existing-account continuity, allowed/denied access, Cloudflare federation, recovery and retained host login. Rollback SHALL cover identity configuration and affected application state.

#### Scenario: Host-auth endpoint is unresolved

- **WHEN** the proposed application route switch would leave a Kanidm Unix/PAM/SSH client pointing at Authentik or an unverified endpoint
- **THEN** production cutover is blocked
- **AND** existing Kanidm state and host-auth configuration remain available

#### Scenario: An existing application account is migrated

- **WHEN** the operator accepts an application's Authentik login
- **THEN** the existing account's data and permissions are verified through its supported linkage or migration mechanism
- **AND** a duplicate empty account does not count as successful migration
- **AND** unchanged client IDs, emails or secrets alone do not establish continuity

#### Scenario: The operator has not authorized deployment

- **WHEN** implementation and static validation finish without deployment authorization
- **THEN** current production provider defaults remain unchanged
- **AND** live acceptance and cutover tasks remain pending

### Requirement: Email ownership SHALL be proven by a code entered in the initiating browser

AI-9: Enrollment, unverified login and signed-in re-verification SHALL use the native email-code stage. Recording proof SHALL require a confirmed device belonging to the pending user, the verification stage and the account's current address. Verification-only devices SHALL be consumed without changing unrelated MFA devices. A verified unchanged address SHALL NOT require an email code on every login.

#### Scenario: Code is accepted during enrollment

- **WHEN** an invited person enters the code sent to their registered address
- **THEN** that address is recorded as verified and the account is activated
- **AND** the original browser completes its flow without a verification link or polling

#### Scenario: Address changed while verification was in progress

- **WHEN** a code proves an address other than the account's current address
- **THEN** it does not record the current address as verified or activate the account

### Requirement: Login SHALL support passkeys alongside username-or-email password fallback

AI-10: Identification SHALL accept username or email and offer conditional passkey authentication. Passkey setup SHALL require discoverable credentials and user verification without restricting enrollment to platform authenticators. Password and recovery paths SHALL remain available until separately approved retirement.

#### Scenario: Person enrolls and uses a passkey

- **WHEN** a signed-in person enrolls a compatible passkey from user settings
- **THEN** they can use it in a fresh browser session without entering their password
- **AND** email ownership gating still applies when their current address is unverified
