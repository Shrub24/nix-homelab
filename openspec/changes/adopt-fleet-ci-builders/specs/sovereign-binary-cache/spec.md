# Spec Delta

## REMOVED Requirements

### Requirement: Read path SHALL be native S3 without requiring an HTTP endpoint

**Reason:** routine consumers already use the canonical public HTTPS substituter backed by R2, not a credentialed S3 read path.

**Migration:** use the public-read requirement below; preserve signed narinfo verification and private write separation.

### Requirement: CI SHALL NOT push to the sovereign cache

**Reason:** the upstream CI contract explicitly publishes successful build outputs before deployment through scoped OIDC authorization.

**Migration:** use the CI-publication requirement below; keep host tokens and server-side signing separate from CI identity.

### Requirement: Post-deploy cache push SHALL be composed by the backups aspect

**Reason:** cache publication is independently selected through cache-publisher, and upstream builder publication requires its post-build upload hook rather than the obsolete suppression.

**Migration:** use the cache-publisher requirement below; preserve host credential bindings, local provider optimization and existing activation publication without recreating a backups bundle.

## ADDED Requirements

### Requirement: Public cache reads SHALL not require write credentials

Routine cache consumers SHALL read signed narinfo and NAR objects through the canonical public HTTPS substituter backed by R2, without acquiring S3 or cache-write credentials and without using the private niks3 write API as the read path.

#### Scenario: Nix consumer reads from sovereign cache
- **WHEN** a client uses the canonical public substituter and trusted signing key
- **THEN** it can download and verify cached outputs without a cache-write credential
- **AND** the private write endpoint is not its substituter URL

### Requirement: CI publication SHALL use scoped OIDC authorization

Authorized CI runs SHALL publish build outputs using short-lived GitHub OIDC tokens. Authorization SHALL restrict owner, repository, main ref and reusable workflow identity independently of Tailscale admission. No long-lived cache token or signing private key SHALL be supplied to the runner.

#### Scenario: Authorized main build publishes
- **WHEN** the approved reusable workflow publishes for a permitted repository on main
- **THEN** the cache validates its OIDC claims and accepts the authorized write
- **AND** the cache signs narinfo server-side

#### Scenario: Tailnet admission alone is insufficient
- **WHEN** a runner can reach the private API but lacks the required claims
- **THEN** the cache rejects its publication

### Requirement: Cache publication SHALL be composed by the cache-publisher aspect

Builder-side publication SHALL use the cache-publisher convention contributor over nix-fleet's publisher mechanism. Every selected CI builder SHALL have a working post-build upload path and its own credential binding. Mutable-state backups SHALL remain independently selected; adopting build CI SHALL NOT restore the obsolete post-build-hook suppression or create a second upload implementation.

#### Scenario: CI remote builder completes work
- **WHEN** a selected builder produces an uncached output
- **THEN** its shared publisher mechanism uploads that output
- **AND** logs and signed substitution independently verify publication

#### Scenario: Builder lacks publication credentials
- **WHEN** a selected builder has no usable host-scoped publisher credential
- **THEN** live CI adoption is not accepted as complete
- **AND** account login or successful compilation alone does not satisfy publication acceptance

#### Scenario: Cache host publishes locally
- **WHEN** the cache host invokes its publisher
- **THEN** its established token ownership and loopback write optimization remain intact

## MODIFIED Requirements

### Requirement: Push auth SHALL use host-scoped API tokens

Host-side publishers SHALL use independently revocable host-scoped API tokens from their host-specific secret sources. GitHub-native CI publishers SHALL instead use the separately scoped OIDC authorization contract; CI SHALL NOT receive a host's publication token.

#### Scenario: Authorized host pushes a closure
- **WHEN** a host presents a valid host-scoped API token
- **THEN** niks3 accepts publication according to that token's permissions

#### Scenario: Unauthorized push is rejected
- **WHEN** a client presents no valid API token or authorized OIDC token
- **THEN** publication is rejected and no artifacts are accepted

### Requirement: Private Niks3 writes SHALL use an internal transport contract

Publishers SHALL resolve the private write endpoint from the canonical service endpoint contract, distinct from the public read/substituter identity. Host publishers MAY use the web catalog's provider-local projection; CI SHALL consume the endpoint metadata supplied by the upstream build contract. No publisher SHALL restate the provider address.

#### Scenario: Remote host publishes a closure
- **WHEN** a non-provider host or CI runner publishes
- **THEN** it uses the resolved private provider endpoint and declared port
- **AND** the public cache identity remains unchanged

#### Scenario: Cache host publishes locally
- **WHEN** the provider host publishes
- **THEN** it may use the catalog's loopback projection
- **AND** remote publishers still resolve the canonical private endpoint

#### Scenario: Consumer reads from the cache
- **WHEN** a consumer substitutes an output
- **THEN** it uses public read policy, not the private write API
