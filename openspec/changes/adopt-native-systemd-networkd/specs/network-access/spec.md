# Spec Delta: network-access (MODIFIED)

## MODIFIED Requirements

### Requirement: Tailscale integration is standardized
Hosts SHALL use standardized Tailscale module wiring for connectivity and administrative SSH support. On hosts running `systemd-resolved`, Tailscale DNS integration SHALL operate through resolved's per-link split-DNS configuration rather than direct `/etc/resolv.conf` ownership.

#### Scenario: Host boots with Tailscale enabled
- **WHEN** system services start
- **THEN** Tailscale connectivity and expected service ordering are configured declaratively

#### Scenario: Resolved-mediated split DNS replaces resolv.conf ownership
- **WHEN** a host that previously let tailscaled own `/etc/resolv.conf` gains `systemd-resolved`
- **THEN** MagicDNS names resolve through the resolved stub with per-link configuration on `tailscale0`
- **AND** non-tailnet queries continue to the host's per-link upstream DNS without tailscaled rewriting global resolver state

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
