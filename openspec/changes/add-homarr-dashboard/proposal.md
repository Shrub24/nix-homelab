# Proposal

## Why

User-facing services need a clear, authenticated landing page that is distinct from the existing operator Homepage on `la-admin-1`. Homarr v2 provides per-user identities, board permissions and home-board selection, while its UI-managed configuration suits the requested model: Nix owns deployment and secrets; Homarr owns most boards and catalogue edits.

**Core Value:** Give each household user an OIDC-authenticated entry point to the services they are allowed to use, without making Homarr another source of infrastructure or endpoint truth.

## What Changes

- Add a user-facing Homarr v2 service on `oci-melb-1`, alongside and independent from the operator Homepage.
- Pin the released Homarr v2 image by tag and registry digest; run it as a host-networked or otherwise minimally exposed container bound only to loopback, with persistent `/appdata` under `/srv/data/homarr` and no Docker socket.
- Add a public `home.shrublab.xyz` route through canonical web policy, using the existing edge-to-origin transport and relying on Homarr's Kanidm OIDC rather than Cloudflare Access.
- Add a Kanidm OIDC client and service-owned secret inputs. Configure OIDC login while retaining only the minimum bootstrap path required to create the first Homarr administrator.
- Document that Homarr users, boards, permissions, service catalogue and personal home-board choices are imperatively managed in Homarr and persist in `/appdata`; do not generate a second endpoint inventory from Nix.
- Add backup coverage, placement and identity contract checks, and operator bootstrap/recovery guidance.

## Capabilities

### New Capabilities
- `user-service-dashboard`: Homarr deployment and its user-facing, per-user dashboard access contract, including OIDC and persistent imperative configuration.

### Modified Capabilities
None. Existing `kanidm-identity`, `provider-owned-oidc-uris`, `policy-service-catalog`, `edge-proxy-ingress`, and `state-backups` contracts cover the generic identity, routing, and recovery behavior; this change introduces the Homarr-specific user dashboard capability.

## Impact

- `modules/apps/` (new Homarr aspect), `modules/hosts/oci-melb-1/` (aspect and secret binding), `modules/identity/` and `policy/identity.json` (OIDC client), `policy/web-services.nix` and `policy/oci-images.nix` (route and pinned image).
- Service-scoped secret template and SOPS scope, state-backups registration, contract tests, and service/runbook/architecture documentation.
- Upstream: `ghcr.io/homarr-labs/homarr`, Apache-2.0, released v2 line (latest release observed during planning: v2.5.2). No Docker socket or Redis is in scope unless implementation research finds a hard runtime requirement.
- Existing `admin-homepage` on `la-admin-1` remains unchanged and independent.
