## MODIFIED Requirements

### Requirement: Paperless edge route SHALL use public OIDC-gated ingress
The Paperless route SHALL be declared in `policy/web-services.nix` as a public subdomain with Kanidm OIDC auth (not Cloudflare Access), matching the Karakeep route pattern.

#### Scenario: Paperless route is accessible
- **WHEN** a browser navigates to the Paperless subdomain
- **THEN** Caddy on `la-admin-1` proxies the request over Tailscale to `oci-melb-1`
- **AND** the route requires valid OIDC session or redirects to Kanidm
