# Proposal: Harden application SSO

## Core Value

A successful Authentik identity should be the ordinary sign-in path for every active application with a native OIDC integration, without orphaning existing application data or exposing Memos publicly.

## Why

Actual Budget and Langfuse currently report OIDC sign-in errors, while several applications still permit local password or email sign-in. The active integrations need to be verified before those fallback paths are removed; otherwise tightening authentication could lock out users or strand data-owning accounts.

## What Changes

- Make Authentik the only interactive sign-in method for active, user-facing native OIDC clients where the application supports it. Do not put unrelated services behind a new Cloudflare Access layer; record unsupported applications such as Inbox Zero as exceptions.
- Resolve Actual Budget's known identity mismatch before removing its password fallback: its existing account is `saurabhj@id.shrublab.xyz`, while Authentik supplies `preferred_username=saurabhj`. Preserve the existing account and data; do not edit its live SQLite database directly or change the canonical identity claim to fit the legacy row. Password fallback remains until an account-preserving supported migration is proven.
- Verify and repair Langfuse's OIDC failure before disabling its local username/password path. Its provider callback and client settings must work before SSO-only mode is activated.
- Configure Memos 0.31 for private instance access and disallow local password authentication. Preserve existing explicit share links; private access blocks anonymous browsing, not deliberate sharing.
- Present the OIDC provider as **Shrublab** in application sign-in controls without changing client IDs, provider identifiers, callback URLs, or token claims.
- Align Authentik's desktop application list view to the left; leave the grid layout and mobile behavior unchanged.

## Capabilities

### New Capabilities
- `application-sso`: SSO-only sign-in for active native OIDC clients, safe identity continuity during cutover, and private Memos access with intentional share links preserved.
- `identity-user-experience`: The provider is presented to users as Shrublab and the desktop application list view has the agreed alignment.

### Modified Capabilities
- None. Reuse the existing `provider-owned-oidc-uris` contract unchanged; `network-access` remains private-first and is not broadened with new proxy gates.

## Impact

- Likely code: `modules/apps/actual.nix`, `modules/apps/memos.nix`, `modules/observability/langfuse.nix`, `modules/identity/authentik/_client.nix`, and `modules/identity/authentik/files/login-theme.css`.
- Tests and docs will cover supported OIDC-only behavior, Memos private access/share-link semantics, and the explicit unsupported-client exception list.
- Official Memos 0.31 documentation confirms file-backed `ACCESS`/`GENERAL` settings, and Langfuse v4 documents `AUTH_DISABLE_USERNAME_PASSWORD=true`. All twelve active OIDC discovery documents returned HTTP 200; this verifies discovery reachability, not interactive login or callback exchange.
- No secrets, live application databases, or deployed hosts are changed by this proposal. Actual account migration and live login acceptance are rollout gates.