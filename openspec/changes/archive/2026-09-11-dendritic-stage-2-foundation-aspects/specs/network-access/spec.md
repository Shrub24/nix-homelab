# Delta Spec: Network Access

## MODIFIED Requirements

### Requirement: Tailscale integration is standardized
Hosts SHALL enable Tailscale by selecting the Tailscale foundation aspect, and the aspect SHALL own the standardized module wiring for connectivity and administrative SSH support. On hosts running `systemd-resolved`, Tailscale DNS integration SHALL operate through resolved's per-link split-DNS configuration rather than direct `/etc/resolv.conf` ownership.

#### Scenario: Host boots with Tailscale enabled
- **WHEN** a host selects the Tailscale foundation aspect and system services start
- **THEN** Tailscale connectivity and expected service ordering are configured declaratively by the aspect-owned wiring
- **AND** the host assembly does not repeat the underlying Tailscale enablement

#### Scenario: Resolved-mediated split DNS replaces resolv.conf ownership
- **WHEN** a host that previously let tailscaled own `/etc/resolv.conf` gains `systemd-resolved`
- **THEN** MagicDNS names resolve through the resolved stub with per-link configuration on `tailscale0`
- **AND** non-tailnet queries continue to the host's per-link upstream DNS without tailscaled rewriting global resolver state

### Requirement: Proven Tailscale packet-size workarounds SHALL remain host-scoped
When direct LA-to-OCI Tailscale traffic exhibits a repeatable packet-size black hole while other OCI peer paths remain healthy, `la-admin-1` and `oci-melb-1` SHALL select the proven 1200-byte TUN MTU through the Tailscale aspect's host-specific MTU contract, expressed once in the aspect rather than repeated per host. The workaround SHALL not change fleet enrollment, identity, authorization tags, firewall policy, routing, or enable experimental peer PMTUD.

#### Scenario: LA reaches OCI origins through Tailscale
- **WHEN** `la-admin-1` and `oci-melb-1` activate the corrected Tailscale configuration through the aspect's host-specific MTU contract
- **THEN** both `tailscaled.service` environments contain `TS_DEBUG_MTU=1200`
- **AND** the resulting WireGuard datagrams remain below the observed failing packet size
- **AND** OCI-origin edge routes and direct LA-to-OCI requests no longer fail according to request size

#### Scenario: Host without the workaround is unaffected
- **WHEN** a host does not select the MTU workaround through the aspect contract
- **THEN** its `tailscaled.service` environment does not contain `TS_DEBUG_MTU`
- **AND** the host's Tailscale behavior is unchanged from the pre-change baseline