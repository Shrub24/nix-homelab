# paperless-service Specification

## Purpose
TBD - created by archiving change paperless-ngx-fleet-integration. Update Purpose after archive.
## Requirements
### Requirement: Paperless SHALL run as a native NixOS service on oci-melb-1
The system SHALL use `services.paperless` from nixpkgs stable as the operational interface — no Docker Compose, no manual setup. The module SHALL bind the web service to `0.0.0.0` on a configurable port (default 8080) for direct Caddy-over-Tailscale ingress without nginx.

#### Scenario: Paperless service is enabled on the host
- **WHEN** `services.paperless` is configured on `oci-melb-1`
- **THEN** Paperless web, consumer, scheduler, and task queue services are declared as systemd units
- **AND** the web service binds to `0.0.0.0:8080`

#### Scenario: Paperless is configured with native SECRET_KEY
- **WHEN** the module is evaluated
- **THEN** `PAPERLESS_SECRET_KEY` is sourced from a sealed SOPS environment file
- **AND** Paperless starts without manual key generation

### Requirement: Paperless SHALL use OIDC as the primary authentication method
Paperless SHALL configure django-allauth with Kanidm as the OIDC provider, redirect login to SSO by default, and disable local password login for daily use. An initial admin user SHALL be created via a SOPS-administered password for first-setup and break-glass access.

#### Scenario: User authenticates via Kanidm OIDC
- **WHEN** an unauthenticated user visits the Paperless web UI
- **THEN** they are redirected to Kanidm for authentication
- **AND** after successful SSO, they are returned to Paperless as an authenticated session

#### Scenario: Admin creates initial superuser
- **WHEN** the admin runs `paperless-manage createsuperuser` after first deploy
- **THEN** the admin password is available from the SOPS-backed environment
- **AND** password login can be disabled after OIDC is confirmed working

### Requirement: Paperless SHALL use shared PostgreSQL
Paperless SHALL connect to the fleet's existing shared PostgreSQL service on `oci-melb-1` with a dedicated `paperless` database and user. The DB password SHALL be sourced from the sealed SOPS environment file.

#### Scenario: Paperless connects to shared PostgreSQL
- **WHEN** Paperless starts
- **THEN** it connects to the shared PostgreSQL instance with the configured database name, user, and password
- **AND** `createLocally` is `false` (database lifecycle managed externally)

### Requirement: Paperless SHALL notify on document consumption
Paperless SHALL invoke `notify` after each successfully consumed document, passing the document title and metadata as notification content.

#### Scenario: Document is consumed
- **WHEN** Paperless finishes processing a document
- **THEN** `PAPERLESS_POST_CONSUME_SCRIPT` runs a wrapper script
- **AND** the script calls `notify info "Paperless: $DOCUMENT_TITLE"`
- **AND** the notification is dispatched to the configured Telegram topic

### Requirement: Paperless SHALL back up data and media state
Paperless SHALL declare its state paths (data dir, media dir, consumption dir) for the existing `services.state-backups` module, enabling consistent fleet-wide backup policy.

#### Scenario: Backups are collected
- **WHEN** `services.state-backups` runs on `oci-melb-1`
- **THEN** Paperless data, media, and consumption directories are included in the backup paths
- **AND** backup mode is `live` for data dir, `live` for media dir

### Requirement: Paperless OIDC client SHALL follow established fleet pattern
The Kanidm OIDC client registration for Paperless SHALL be declared in `policy/identity.json` with the callback URL matching the Caddy route subdomain, and the client secret SHALL be sourced from the host's shared OIDC secret file.

#### Scenario: Paperless OIDC client is registered
- **WHEN** Kanidm provisioning evaluates OIDC clients
- **THEN** a `paperless` client is created with callback path `/accounts/oidc/kanidm/login/callback/`
- **AND** the callback URL resolves to `https://paper.shrublab.xyz/accounts/oidc/kanidm/login/callback/`

### Requirement: Paperless edge route SHALL use public OIDC-gated ingress
The Paperless route SHALL be declared in `policy/web-services.nix` as a public subdomain with Kanidm OIDC auth (not Cloudflare Access), matching the Karakeep route pattern.

#### Scenario: Paperless route is accessible
- **WHEN** a browser navigates to the Paperless subdomain
- **THEN** Caddy on do-admin-1 proxies the request over Tailscale to oci-melb-1
- **AND** the route requires valid OIDC session or redirects to Kanidm

