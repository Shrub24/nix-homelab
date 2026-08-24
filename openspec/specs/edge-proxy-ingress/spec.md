# edge-proxy-ingress Specification

## Purpose
TBD - created by archiving change phase1-caddy-edge-proxy. Update Purpose after archive.

## Requirements

### Requirement: Single-domain ingress supports flat subdomain routing
The ingress layer SHALL support serving services under one primary domain using flat subdomain routing for phase-1 host rollout, with the primary domain value sourced from canonical policy/config rather than duplicated literals in multiple modules.

#### Scenario: Route map is rendered for a host
- **WHEN** ingress routes are evaluated
- **THEN** each routed service maps to a flat subdomain under the same primary domain
- **AND** the primary domain is resolved from canonical policy/config inputs

### Requirement: Per-service exposure mode is explicit
Each routed service SHALL declare one exposure mode, with phase-1 defaults using `tailscale-upstream` or `tailscale-only`; `direct` remains available but deferred to explicit edge-local exceptions.

#### Scenario: Service exposure policy is configured
- **WHEN** a service is added to ingress configuration
- **THEN** exactly one supported exposure mode is selected and enforced

#### Scenario: Exposure mode is omitted
- **WHEN** a service route does not explicitly set exposure mode
- **THEN** the route defaults to `tailscale-upstream`

#### Scenario: Direct mode is requested in phase-1
- **WHEN** a route is configured as `direct`
- **THEN** it is treated as an explicit edge-local exception, not a normal cross-host default

### Requirement: Cloudflare DNS-01 certificates are automated
Ingress TLS certificates SHALL be issued using Cloudflare DNS challenge integration with host-scoped credentials.

#### Scenario: Certificate automation is enabled
- **WHEN** ingress starts with DNS challenge configuration
- **THEN** certificates are requested/renewed through Cloudflare DNS-01 without HTTP challenge dependency

### Requirement: Route ownership is modular by host and service
Ingress route declarations SHALL be composable per host and per service without hardcoding a single fixed topology.

#### Scenario: Different hosts expose different services
- **WHEN** host role composition differs between nodes
- **THEN** each host publishes only its declared route set while reusing common ingress module contracts

### Requirement: Sensitive services remain private-origin and access-gated by default
Sensitive or administrative web services SHALL default to Cloudflare Access-gated public edge routing with private-origin upstream transport, while preserving explicit support for `tailscale-only` where required.

#### Scenario: Admin route has no public exposure override
- **WHEN** ingress policy is applied
- **THEN** the admin route uses Cloudflare Access-gated edge policy with private-origin upstream transport by default

#### Scenario: Operator opts into strict private-only admin path
- **WHEN** a service is explicitly configured as `tailscale-only`
- **THEN** no public route is rendered and access remains private-only

### Requirement: Edge DNS publication SHALL consume canonical policy exports
Cloudflare DNS publication for edge routes SHALL consume generated policy exports from the canonical web-services map.

#### Scenario: Service subdomain is declared
- **WHEN** a service has a `subdomain` in canonical policy
- **THEN** OpenTofu plans a corresponding DNS record under the configured zone

#### Scenario: Service proxy posture is declared
- **WHEN** a service defines `cloudflare.proxied`
- **THEN** OpenTofu applies that proxied setting to the DNS record

### Requirement: Edge policy inputs SHALL come from canonical web-services policy
Ingress policy defaults and explicit exceptions used by edge-proxy-ingress SHALL be sourced from the canonical policy map at `policy/web-services.nix`, including authoritative subdomain/path declarations.

#### Scenario: Default policy is consumed
- **WHEN** a route has no explicit override
- **THEN** the declared global policy from canonical map is applied

#### Scenario: Host/route override is consumed
- **WHEN** a host or route is explicitly declared as an exception
- **THEN** edge-proxy-ingress consumes that exception and preserves explicit behavior in rendered route policy

#### Scenario: Route path is configured once
- **WHEN** route path metadata is required for edge rendering
- **THEN** path values come from canonical policy entries
- **AND** path literals are not redefined in separate edge module constants

### Requirement: OpenTofu input SHALL be generated from canonical web-services policy
Cloudflare OpenTofu inputs SHALL be generated from `policy/web-services.nix` through a JSON export artifact to avoid duplicated policy declarations, including canonical subdomain values.

#### Scenario: OpenTofu consumes policy for Cloudflare resources
- **WHEN** OpenTofu plans/applies Cloudflare DNS/Access resources
- **THEN** it reads generated JSON exported from canonical web-services policy

### Requirement: Music route class SHALL support grey-cloud posture declaration
The control-plane model SHALL represent music/Navidrome routes as a distinct grey-cloud class so ingress policy does not assume Cloudflare-proxied controls.

#### Scenario: Music policy is evaluated
- **WHEN** music/Navidrome route policy is generated
- **THEN** the route class is marked as grey-cloud in control-plane declarations

### Requirement: Admin routes SHALL remain Access-gated by default with explicit exceptions
Public admin-facing routes SHALL continue to require Cloudflare Access gating by default, with route-level exceptions allowed only when explicitly declared and justified.

Exception declarations consumed by this change SHALL come from canonical shared policy (`policy/web-services.nix`) and Cloudflare control-plane ownership rather than ad-hoc unmanaged route policy.

#### Scenario: Standard admin route is rendered
- **WHEN** a public admin route is rendered without exception flags
- **THEN** it enforces Cloudflare Access header gate behavior
- **AND** it retains existing admin-safe ingress defaults

#### Scenario: Route-level exception is declared
- **WHEN** a route is explicitly marked as exception in this change scope
- **THEN** the exception is visible in route declarations and contract checks
- **AND** exception intent is documented in change artifacts

#### Scenario: Identity-provider route is declared as upstream-IdP exception
- **WHEN** the Kanidm route is rendered for shared IdP hosting
- **THEN** it is explicitly declared as the required non-Access-gated upstream IdP exception
- **AND** this exception is documented as required to avoid Access→IdP loop behavior

### Requirement: Cloudflare Access SHALL use Pocket ID as upstream IdP
Cloudflare Access configuration for admin browser routes SHALL use Kanidm generic OIDC as upstream identity provider in this change scope.

#### Scenario: Access IdP switch is evaluated
- **WHEN** Cloudflare Access resources or inputs are evaluated
- **THEN** upstream IdP endpoints and client credentials resolve to Kanidm values
- **AND** legacy Pocket ID upstream assumptions are removed from this change scope

### Requirement: Music route SHALL reflect orange-cloud exposure posture with caching disabled
The music/Navidrome ingress posture SHALL be modeled as orange-cloud while ensuring CDN/caching is disabled via control-plane policy.

#### Scenario: Music route policy is evaluated
- **WHEN** route posture for music/Navidrome is reviewed in this change
- **THEN** artifacts and route checks treat music as an orange-cloud DNS exposure class
- **AND** control-plane policy disables CDN/caching for the music endpoint

### Requirement: Bypassed route classes SHALL stay explicit and minimal
Ingress policy changes that preserve bypassed/non-Access traffic classes SHALL keep exceptions explicit and constrained in canonical policy.

#### Scenario: Exposed/bypassed route classes exist
- **WHEN** route set includes traffic classes outside normal Access-gated browser flow
- **THEN** exception routes are explicitly declared in canonical policy and contract checks

### Requirement: Exposed routes in this pivot SHALL use orange-cloud posture by default
For routes in scope of this pivot, Cloudflare DNS/proxy posture SHALL be modeled as orange-cloud by default unless an explicit exception is documented.

#### Scenario: In-scope admin route posture is evaluated
- **WHEN** route policy for this pivot is rendered
- **THEN** route exposure class is orange-cloud by default
- **AND** any non-default posture is explicitly declared with rationale in artifacts

### Requirement: Traffic blocking SHALL rely on Cloudflare edge controls in this rollout
Traffic filtering and firewalling for exposed traffic in this rollout SHALL be handled by Cloudflare control-plane policies rather than host-layer CrowdSec.

#### Scenario: Security baseline for exposed traffic is reviewed
- **WHEN** rollout security controls are evaluated
- **THEN** Cloudflare firewall/WAF/traffic policies are the primary blocking layer
- **AND** CrowdSec host-layer controls are not required in this change scope

### Requirement: Music route SHALL be exposed through canonical edge policy
Music/Navidrome SHALL be exposed as a declared web service route through canonical edge-ingress policy, using `tailscale-upstream` transport to private origin.

#### Scenario: Music route is declared in canonical policy
- **WHEN** policy maps are resolved for the edge host
- **THEN** a `music` route is rendered with `tailscale-upstream` origin transport

### Requirement: Music public route SHALL enforce Cloudflare Access and AOP
The music route SHALL require Cloudflare Access gating and SHALL require Authenticated Origin Pulls (AOP) under host-level route policy.

#### Scenario: Music route policy is rendered
- **WHEN** edge route attributes are generated from canonical web-services policy
- **THEN** `cloudflareAccessRequired` is enforced for the music route
- **AND** authenticated origin pulls are required for the host/route set

### Requirement: Trusted proxy CIDRs SHALL remain single-source for edge reverse-proxy trust behavior
The CIDR source used to trust reverse-proxy client IP headers SHALL remain centrally declared and SHALL drive rendered edge trusted-proxy configuration.

#### Scenario: Edge trusted-proxy policy is rendered
- **WHEN** an edge host evaluates reverse-proxy trust configuration
- **THEN** the rendered trusted proxy configuration consumes the declared trusted proxy CIDR list
- **AND** client IP header trust is not sourced from duplicated unmanaged CIDR literals

#### Scenario: Trusted proxy configuration is updated
- **WHEN** the trusted proxy CIDR list changes
- **THEN** rendered reverse-proxy trust behavior changes from that same declared input source

### Requirement: Tagr route SHALL be exposed through canonical gated edge policy
Tagr SHALL be exposed as a declared web service route through canonical `la-admin-1` edge-ingress policy using `tailscale-upstream` transport to private origin.

#### Scenario: Tagr route is declared in canonical policy
- **WHEN** policy maps are resolved for `la-admin-1`
- **THEN** a `tagr` route is rendered with `tailscale-upstream` origin transport to `oci-melb-1`

### Requirement: Tagr public route SHALL enforce Cloudflare Access and AOP
The Tagr route SHALL require Cloudflare Access gating and SHALL require Authenticated Origin Pulls under host-level route policy.

#### Scenario: Tagr route policy is rendered
- **WHEN** edge route attributes are generated from canonical web-services policy
- **THEN** `cloudflareAccessRequired` is enforced for `tagr`
- **AND** authenticated origin pulls are required for the Tagr host/route set

### Requirement: Karakeep route SHALL be exposed through canonical edge policy
Karakeep SHALL be exposed as a declared web service route through canonical `la-admin-1` edge-ingress policy using `tailscale-upstream` transport to private origin on `oci-melb-1`.

#### Scenario: Karakeep route is declared in canonical policy
- **WHEN** policy maps are resolved for `la-admin-1`
- **THEN** a `karakeep` route is rendered with `tailscale-upstream` origin transport to `oci-melb-1`
- **AND** route ownership remains single-sourced in `policy/web-services.nix`

### Requirement: Karakeep public route SHALL rely on app-native auth and AOP
The Karakeep route SHALL NOT require Cloudflare Access gating, and SHALL require Authenticated Origin Pulls under host-level route policy while relying on app-native auth for browser and mobile/API clients.

#### Scenario: Karakeep route policy is rendered
- **WHEN** edge route attributes are generated from canonical web-services policy
- **THEN** `cloudflareAccessRequired` is disabled for `karakeep`
- **AND** authenticated origin pulls are required for the Karakeep host/route set

### Requirement: Edge-host replacement SHALL preserve declared public routes
Moving the designated edge host SHALL preserve the public URL, Cloudflare Access posture, AOP posture, and declared origin transport of every route in canonical web policy except explicitly approved admin-route changes.

#### Scenario: Policy is resolved for the replacement edge
- **WHEN** `la-admin-1` becomes the designated edge host
- **THEN** all declared routes resolve through that host without duplicate route ownership
- **AND** route-specific Cloudflare Access exceptions remain unchanged
