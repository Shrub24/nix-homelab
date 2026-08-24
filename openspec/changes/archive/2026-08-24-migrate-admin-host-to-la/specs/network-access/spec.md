## ADDED Requirements

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
Cross-host notification publishers (non-origin hosts such as `oci-melb-1`) SHALL derive the ntfy server URL from the policy catalog rather than hardcoding a host, and SHALL send an explicit application User-Agent on every ntfy HTTP request so Cloudflare Browser Integrity Check does not block them. Local ntfy origin publishers (`la-admin-1`, `do-admin-1`) SHALL override the derived URL to their loopback origin. The public ntfy URL SHALL remain the canonical base URL, bearer-token authorization SHALL remain required, and no secondary private route for ntfy dispatch SHALL be introduced.

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
