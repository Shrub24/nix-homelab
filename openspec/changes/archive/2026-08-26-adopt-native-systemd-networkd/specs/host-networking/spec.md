# Spec Delta: host-networking (ADDED)

## ADDED Requirements

### Requirement: Hosts own networking through a declarative aspect
Each fleet host SHALL own its physical networking through the shared networking aspect (`fleet.networking`), activated by importing the aspect module rather than by an enable flag. The aspect SHALL require an uplink interface fact per host and SHALL fail evaluation when required facts (uplink interface; bridge MAC when a bridge is declared) are missing.

#### Scenario: Host declares its uplink
- **WHEN** a host imports the networking aspect and declares `fleet.networking.uplink.interface`
- **THEN** evaluation emits native `systemd.network` units for that interface without scripted-networking or dhcpcd units

#### Scenario: Required fact is missing
- **WHEN** a host imports the aspect without declaring an uplink interface, or declares a bridge without its MAC address
- **THEN** evaluation fails with an assertion naming the missing fact

### Requirement: Physical addressing is DHCP with MAC-based client identity
Uplink addressing SHALL be DHCPv4 with a MAC-based DHCP client identity so provider and router lease/reservation state survives the backend migration. Hosts SHALL NOT duplicate provider-owned addresses, gateways, or routes as static configuration.

#### Scenario: Router reservation holds across migration
- **WHEN** a host with an existing DHCP reservation activates the networkd generation
- **THEN** the host receives the same leased address without operator intervention

#### Scenario: Static duplication is rejected by review
- **WHEN** a host config adds static addresses or gateways for a DHCP-served uplink
- **THEN** the change is flagged as duplicating provider/router state

### Requirement: Bridge topology preserves link identity
When a host declares a bridge, the bridge SHALL carry the pinned physical NIC MAC address, the member interface SHALL carry no addressing, and the bridge SHALL be the addressed, routed uplink. The bridge SHALL exist unconditionally as host topology, independent of which applications consume it.

#### Scenario: Bridge inherits the physical identity
- **WHEN** the bridge generation boots on a host whose router reserves addresses by MAC
- **THEN** the bridge presents the pinned MAC and receives the reserved lease

#### Scenario: Application disable does not tear down topology
- **WHEN** an application that consumes the bridge is disabled
- **THEN** the bridge, its member enslavement, and uplink addressing remain intact

### Requirement: Resolver mechanism is standardized on systemd-resolved
All fleet hosts SHALL use `systemd-resolved` as the resolver engine. Per-link DNS learned from DHCP/providers SHALL remain primary for their routing domains; globally pinned public resolvers and `FallbackDNS` SHALL provide resilience only. Fleet defaults SHALL be `DNSOverTLS = opportunistic` and `DNSSEC = allow-downgrade`; strict modes SHALL NOT be enabled against upstreams that do not support them.

#### Scenario: Provider-local names keep resolving
- **WHEN** a host whose link advertises a provider resolver and route domain (for example OCI's VCN resolver) resolves a provider-local name
- **THEN** the query is answered by the per-link resolver, not a global public resolver

#### Scenario: Tailscale split DNS is mediated by resolved
- **WHEN** tailscaled starts on any fleet host
- **THEN** MagicDNS names resolve through resolved's per-link configuration for `tailscale0`, and non-tailnet queries continue to the host's normal per-link DNS

### Requirement: IPv6 readiness without enablement
Network units SHALL be structured so provider-delivered IPv6 is picked up without redesign, but hosts SHALL run DHCPv4-only today. On hosts where the provider has not allocated IPv6, `IPv6AcceptRA` SHALL be explicitly disabled on the uplink to prevent unintended autoconfiguration.

#### Scenario: Unprovisioned provider cannot autoconfigure IPv6
- **WHEN** an unexpected router advertisement appears on a host whose provider has no IPv6 allocation
- **THEN** the host does not derive a global IPv6 address or default route from it

### Requirement: Virtual and overlay interfaces remain unmanaged
The aspect SHALL match only explicitly declared interfaces. Podman bridges, Tailscale interfaces, veth pairs, and libvirt-created links SHALL receive no addressing or management from the aspect.

#### Scenario: Container networks boot undisturbed
- **WHEN** a host with Podman networks and Tailscale activates the networkd generation
- **THEN** those interfaces retain their existing ownership and addressing behavior

### Requirement: Network ownership cutovers are boot-staged
Migrating a host between network owners SHALL stage the new generation for next boot, reboot from console access, validate connectivity and services, then perform a second ordinary reboot to prove repeatability. Operators SHALL NOT live-switch network ownership over an in-band SSH session, and the previous generation SHALL remain available as rollback.

#### Scenario: Cutover follows the staged ritual
- **WHEN** a host's networkd generation is deployed
- **THEN** activation happens at a console-backed reboot, validation gates pass before the operator proceeds, and a second reboot reproduces the same healthy state

#### Scenario: Failed cutover rolls back
- **WHEN** the networkd generation fails its validation gates
- **THEN** the operator boots the previous generation from console and the host recovers its prior networking without in-band access
