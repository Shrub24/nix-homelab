# application-sso Specification

## Purpose

Define SSO-only access for active user-facing applications with native Authentik OIDC, while keeping existing application identities and their data intact and limiting anonymous access to intentional shares.

## ADDED Requirements

### Requirement: Active native OIDC applications SHALL use Authentik as their sole interactive sign-in method

Every active, user-facing native OIDC client SHALL require Authentik for interactive sign-in whenever the application supports disabling local credentials. An OIDC failure SHALL NOT enable local-login fallback. Machine and API authentication SHALL remain unaffected.

#### Scenario: User signs in to an active OIDC application

- **WHEN** an application with an active native OIDC client presents its interactive sign-in options
- **THEN** Authentik OIDC is the only offered interactive sign-in method where the application supports that policy
- **AND** local username/password and email sign-in are unavailable
- **AND** an OIDC failure does not enable a local-login fallback

#### Scenario: Existing application identity is migrated

- **WHEN** an existing user switches from the previous identity provider to Authentik
- **THEN** the application resolves the Authentik identity to the same application account and preserves its user ID and owned data
- **AND** the SSO-only cutover is blocked until that mapping is verified
- **AND** the application does not create a second account that silently owns none of the existing data

#### Scenario: Actual Budget has a legacy username mismatch

- **WHEN** Authentik returns `preferred_username=saurabhj` and the existing Actual Budget account is `saurabhj@id.shrublab.xyz`
- **THEN** the account-preserving mapping is corrected through a supported migration before password fallback is removed
- **AND** the SQLite account record is not edited directly as part of deployment

### Requirement: Applications without native OIDC SHALL remain explicit exceptions

Applications without an active native Authentik OIDC client SHALL be identified as exceptions rather than being treated as SSO-protected. This requirement SHALL NOT add an edge proxy or Cloudflare Access policy.

#### Scenario: An application has no native Authentik OIDC client

- **WHEN** an application such as Inbox Zero uses a different sign-in integration and has no active Authentik OIDC client
- **THEN** it is identified as an exception to this requirement
- **AND** no new edge proxy or Cloudflare Access policy is added to imply that it is covered

### Requirement: Memos SHALL be private to authenticated users while preserving explicit shares

Memos SHALL deny anonymous instance browsing and local password authentication while allowing the configured OIDC provider to authenticate users. Existing explicit memo share links SHALL remain usable; private instance mode SHALL NOT revoke or rewrite them.

#### Scenario: Anonymous visitor browses Memos

- **WHEN** a visitor without an authenticated Memos session opens the instance or requests a non-shared memo
- **THEN** Memos requires authentication and does not expose the public instance view

#### Scenario: Visitor opens an explicitly shared memo

- **WHEN** a visitor follows an existing explicit memo share link
- **THEN** the shared memo remains available according to its existing share policy
- **AND** the link is not revoked merely because the instance is private

#### Scenario: User authenticates to Memos

- **WHEN** a user signs in interactively to Memos
- **THEN** the configured Authentik OIDC provider remains available
- **AND** local password authentication is unavailable

### Requirement: SSO-only mode SHALL be enabled only after provider behavior is verified

Before local authentication is removed from an application, its Authentik discovery, authorization, callback, token exchange, and account lookup SHALL be verified against the deployed application and provider. A successful discovery response alone SHALL NOT count as login acceptance.

#### Scenario: OIDC acceptance is incomplete

- **WHEN** discovery succeeds but callback exchange or account lookup has not been verified
- **THEN** the application is not treated as ready for SSO-only cutover
- **AND** the missing verification remains an explicit rollout blocker

#### Scenario: Langfuse OIDC is failing

- **WHEN** Langfuse reports an OAuth sign-in failure
- **THEN** its OIDC failure is diagnosed and corrected before local username/password authentication is disabled
- **AND** a successful Authentik callback and account resolution are verified before cutover

#### Scenario: Unsupported password control is encountered

- **WHEN** an active OIDC application cannot disable local username/password or email sign-in through its supported configuration
- **THEN** it remains explicitly identified as a partial exception
- **AND** the application is not claimed to be SSO-only until a supported control exists
- **AND** no application frontend patch is introduced without a separate decision
