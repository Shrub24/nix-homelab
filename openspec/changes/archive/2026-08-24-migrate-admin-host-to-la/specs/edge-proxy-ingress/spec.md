## ADDED Requirements

### Requirement: Edge-host replacement SHALL preserve declared public routes
Moving the designated edge host SHALL preserve the public URL, Cloudflare Access posture, AOP posture, and declared origin transport of every route in canonical web policy except explicitly approved admin-route changes.

#### Scenario: Policy is resolved for the replacement edge
- **WHEN** `la-admin-1` becomes the designated edge host
- **THEN** all declared routes resolve through that host without duplicate route ownership
- **AND** route-specific Cloudflare Access exceptions remain unchanged

## MODIFIED Requirements

### Requirement: Tagr route SHALL be exposed through canonical gated edge policy
Tagr SHALL be exposed as a declared web service route through canonical `la-admin-1` edge-ingress policy using `tailscale-upstream` transport to private origin.

#### Scenario: Tagr route is declared in canonical policy
- **WHEN** policy maps are resolved for `la-admin-1`
- **THEN** a `tagr` route is rendered with `tailscale-upstream` origin transport to `oci-melb-1`

### Requirement: Karakeep route SHALL be exposed through canonical edge policy
Karakeep SHALL be exposed as a declared web service route through canonical `la-admin-1` edge-ingress policy using `tailscale-upstream` transport to private origin on `oci-melb-1`.

#### Scenario: Karakeep route is declared in canonical policy
- **WHEN** policy maps are resolved for `la-admin-1`
- **THEN** a `karakeep` route is rendered with `tailscale-upstream` origin transport to `oci-melb-1`
- **AND** route ownership remains single-sourced in `policy/web-services.nix`

## REMOVED Requirements

### Requirement: SoulSync route SHALL be exposed through canonical gated edge policy

Superseded by `openspec/changes/post-migration-cleanup`: SoulSync control-plane ingest is fully removed and the beets inbox is the sole ingest path. This requirement is removed from this change's delta so archiving it cannot resurrect the SoulSync edge route contract.
