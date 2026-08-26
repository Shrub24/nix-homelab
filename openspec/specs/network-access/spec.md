# Spec: Network Access

## Purpose

Define private-first network access contracts for management and services with Tailscale as baseline transport.

## Requirements

### Requirement: Baseline access is private-first
Management and service access SHALL be private and Tailscale-first by default, with a designated public edge bastion for explicitly declared web routes.

#### Scenario: Baseline network posture is checked
- **WHEN** host and service network settings are evaluated
- **THEN** non-edge origin services remain private unless explicitly introduced by a separate change

#### Scenario: Hybrid ingress exception is introduced
- **WHEN** a route is explicitly configured for public edge exposure
- **THEN** the public surface is limited to declared Cloudflare/Caddy ingress routes while upstream transport remains private-origin and Tailscale-encrypted by default for cross-host services

#### Scenario: Constant-availability exception is introduced
- **WHEN** a route is explicitly configured as `direct`
- **THEN** it is treated as an explicit, edge-local-only localhost exception to the Tailscale-upstream default and is constrained to declared exposure policy

### Requirement: Tailscale integration is standardized
Hosts SHALL use standardized Tailscale module wiring for connectivity and administrative SSH support. On hosts running `systemd-resolved`, Tailscale DNS integration SHALL operate through resolved's per-link split-DNS configuration rather than direct `/etc/resolv.conf` ownership.

#### Scenario: Host boots with Tailscale enabled
- **WHEN** system services start
- **THEN** Tailscale connectivity and expected service ordering are configured declaratively

#### Scenario: Resolved-mediated split DNS replaces resolv.conf ownership
- **WHEN** a host that previously let tailscaled own `/etc/resolv.conf` gains `systemd-resolved`
- **THEN** MagicDNS names resolve through the resolved stub with per-link configuration on `tailscale0`
- **AND** non-tailnet queries continue to the host's per-link upstream DNS without tailscaled rewriting global resolver state

### Requirement: Firewall trust boundaries are explicit
Firewall policy SHALL enforce explicit trust boundaries for allowed interfaces and ports.

#### Scenario: Firewall config is rendered
- **WHEN** networking/firewall modules are evaluated
- **THEN** only declared interfaces/ports are trusted/opened

#### Scenario: Edge host policy is applied
- **WHEN** an edge host is configured for public ingress
- **THEN** only ingress-required ports are opened and private-service ports remain non-public

### Requirement: Break-glass access remains available
Network-access design SHALL include documented recovery paths for control-plane failures, including at least one path that does not depend on the primary post-boot operator login flow remaining healthy.

#### Scenario: Tailnet access is degraded
- **WHEN** primary private access path fails
- **THEN** break-glass procedures provide alternate operator access

#### Scenario: Console recovery path is needed
- **WHEN** a host cannot be recovered through the normal post-boot SSH or tailscale login path
- **THEN** operators have a documented provider or serial console recovery path that can be used outside the normal host login flow

#### Scenario: A remote host adopts declarative network ownership
- **WHEN** a host is migrated to host-owned declarative networking under native systemd-networkd
- **THEN** the declared stack is self-contained about addresses, routes, and interface ownership
- **AND** the new generation is staged for next boot and activated from console access rather than a live in-band switch
- **AND** operators do not rely on a live SSH session surviving the ownership handoff

### Requirement: Public-edge policy SHALL be explicit by default-plus-exception model
Cloudflare public-edge access posture SHALL be modeled as a global default with explicit host/route exceptions.

The default-plus-exception model SHALL be declared in canonical shared policy (`policy/web-services.nix`).

#### Scenario: No exception declared
- **WHEN** a route has no host/route override
- **THEN** it inherits the global default policy

#### Scenario: Exception declared
- **WHEN** a host or route override is present
- **THEN** that exception is applied and remains auditable in change artifacts

### Requirement: Control-plane ownership SHALL be separated from runtime wiring
Cloudflare resource declarations SHALL be owned in control-plane artifacts, while runtime/Nix modules consume canonical policy and derived outputs.

#### Scenario: Runtime change depends on Cloudflare policy
- **WHEN** runtime/Nix change needs edge policy values
- **THEN** values are consumed from canonical policy and generated outputs rather than duplicated unmanaged config

### Requirement: Shared admin hostnames MAY carry host-specific private-origin subpaths
Private-origin admin services SHALL be able to share a public hostname while remaining distinguishable through explicit host-specific subpaths.

#### Scenario: Multiple admin routes share a hostname
- **WHEN** policy routes for different hosts use the same subdomain with distinct declared paths
- **THEN** route resolution preserves the distinct public URLs for each host-specific subpath
- **AND** upstream transport remains private-origin according to the declared exposure mode

### Requirement: Admin-host adoption SHALL preserve independent access
Before an adopted admin host disables provider-supplied password SSH, operators SHALL verify key-based access and a provider-console recovery path that does not depend on Tailscale, Kanidm, or the public edge.

#### Scenario: LA first generation is activated
- **WHEN** the first fleet generation is applied to `la-admin-1`
- **THEN** key-based SSH is verified from a second session before the original password or console session is closed
- **AND** the provider-console recovery procedure is recorded and tested

### Requirement: Tailscale node identity SHALL separate host naming from role authorization
Fleet hosts SHALL use `networking.hostName` only for their stable Tailscale node hostname. Tailscale authorization tags SHALL come from the operator-created tagged auth key and SHALL use the established tailnet role tags rather than a derived `tag:<host>` identity.

#### Scenario: LA joins the tailnet
- **WHEN** `la-admin-1` authenticates with its replacement tagged auth key
- **THEN** the node name is `la-admin-1`
- **AND** the key assigns `tag:homelab` and `tag:ssh-clients`
- **AND** the host does not request `tag:la-admin-1`

### Requirement: Deployment tooling SHALL use default SSH algorithm negotiation
Deployment tooling SHALL use default OpenSSH key-exchange negotiation with no host-specific `KexAlgorithms` overrides. The LA-specific `curve25519-sha256` fallback was removed after a fresh default `mlkem768x25519-sha256` session to `la-admin-1` succeeded over Tailscale.

#### Scenario: LA deployment uses default key-exchange negotiation
- **WHEN** `la-admin-1` is deployed over the tailnet
- **THEN** LA deployment metadata contains no `KexAlgorithms` override
- **AND** all fleet hosts retain default SSH algorithm negotiation
- **AND** no Tailscale enrollment, authorization-tag, NixOS firewall, or provider recovery-port policy changes are introduced

### Requirement: Edge replacement SHALL retain private-origin boundaries
Replacing the designated public edge host SHALL preserve existing declared public URLs except for explicitly approved admin-route changes, while cross-host origins remain Tailscale-encrypted and non-edge service ports remain non-public.

#### Scenario: LA edge receives public traffic
- **WHEN** the Cloudflare origin endpoint is changed to `la-admin-1`
- **THEN** declared routes retain their public URLs and exposure modes except the approved `/la-admin-1` Cockpit path
- **AND** OCI origins continue to use private Tailscale transport

### Requirement: Cross-host ntfy publishers SHALL use the policy-derived public route with an explicit User-Agent
Cross-host notification publishers (non-origin hosts such as `oci-melb-1`) SHALL derive the ntfy server URL from the policy catalog rather than hardcoding a host, and SHALL send an explicit application User-Agent on every ntfy HTTP request so Cloudflare Browser Integrity Check does not block them. Local ntfy origin publishers (`la-admin-1`) SHALL override the derived URL to their loopback origin. The public ntfy URL SHALL remain the canonical base URL, bearer-token authorization SHALL remain required, and no secondary private route for ntfy dispatch SHALL be introduced.

#### Scenario: OCI publishes an ntfy notification after the LA cutover
- **WHEN** the `oci-melb-1` notification daemon dispatches to ntfy
- **THEN** it resolves the server URL from `config.repo.web.catalog.ntfy-admin.publicUrl`
- **AND** it sends an explicit `User-Agent` header on the publish request
- **AND** the public `https://ntfy.shrublab.xyz` route remains unchanged
- **AND** no Cloudflare bypass, Tailscale Serve endpoint, public listener, or secret rotation is required

### Requirement: Proven Tailscale packet-size workarounds SHALL remain host-scoped
When direct LA-to-OCI Tailscale traffic exhibits a repeatable packet-size black hole while other OCI peer paths remain healthy, `la-admin-1` and `oci-melb-1` SHALL start `tailscaled` with a 1200-byte TUN MTU. The workaround SHALL not change fleet enrollment, identity, authorization tags, firewall policy, routing, or enable experimental peer PMTUD.

#### Scenario: LA reaches OCI origins through Tailscale
- **WHEN** `la-admin-1` and `oci-melb-1` activate the corrected Tailscale configuration
- **THEN** both `tailscaled.service` environments contain `TS_DEBUG_MTU=1200`
- **AND** the resulting WireGuard datagrams remain below the observed failing packet size
- **AND** OCI-origin edge routes and direct LA-to-OCI requests no longer fail according to request size
