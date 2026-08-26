# Proposal: adopt-native-systemd-networkd

## Why

Every active host runs NixOS's legacy scripted-networking backend by omission, not by decision — and that stack failed opaquely in production on `home-forge` (dhcpcd silently refuses bridge-master interfaces without an explicit config section, leaving `br0` addressless after the Engine DJ bridge cutover). The repo's one deliberate networking decision (D-031, do-admin-1) already chose declarative systemd-networkd; that host is gone, but the pattern and its boot-time cutover discipline survived in spec. This change adopts native `systemd.network` units as the fleet baseline before Engine DJ lands on top, so the VM bridge becomes stable host topology instead of application-owned physical networking.

## What Changes

- Add `modules/profiles/networking.nix`: an import-activated dendritic aspect that owns networking policy and emits native `systemd.network.{networks,netdevs}` units from required host facts (`fleet.networking.uplink`, optional `fleet.networking.bridge`). No `enable` flag; importing activates.
- Migrate all three hosts off scripted networking/dhcpcd onto the aspect:
  - `home-forge`: always-on `br0` bridge over `eno1` with pinned MAC (`84:a9:3e:6b:94:44`) and MAC-based DHCP client identity so the router reservation survives; DJ application stops owning physical networking.
  - `oci-melb-1`: DHCPv4 on `enp0s6`; explicit `IPv6AcceptRA = false` until provider-side IPv6 exists; VCN link DNS and `homelabvcn.oraclevcn.com` route domain preserved via DHCP.
  - `la-admin-1`: DHCPv4 on `ens18`; gains `systemd-resolved` for the first time — Tailscale switches from `/etc/resolv.conf` overwrite to D-Bus split-DNS.
- Standardize the resolver *mechanism* fleet-wide (`systemd-resolved`), keeping upstream policy heterogeneous: per-link DHCP/provider DNS primary, global `1.1.1.1`/`8.8.8.8` where pinned today, `FallbackDNS` resilience, `DNSOverTLS = opportunistic`, `DNSSEC = allow-downgrade`.
- Make units IPv6-ready but disabled: DHCPv4-only addressing; dual-stack enablement deferred to a provider-layer follow-up (OCI requires VCN/subnet/gateway/security-list work before any host config matters).
- Preserve current addressing outcomes exactly: DHCP everywhere, existing leases/reservations hold, firewall/Tailscale/MTU workarounds unchanged.
- Roll out per host with the codified boot-time ritual: staged generation (`deploy-rs --boot`), console reboot, validation gates, then a second ordinary reboot to prove repeatability. Order: `home-forge` → `oci-melb-1` → `la-admin-1`.
- Correct the pre-existing LA publisher boot defects discovered by the cold-boot gate: Cockpit certificate material gates `cockpit.service`, which consumes it, without delaying `cockpit.socket` behind `basic.target`; both repo-owned Tailscale Serve publishers use the native `tailscale wait` readiness gate before programming Serve state.

Non-goals: resolver flattening to public DNS, global IPv6 enablement, initrd networking, nftables migration, changes to Tailscale enrollment/tags/firewall, or deploying and live-validating the separate Engine DJ/Windows VM change.

## Capabilities

### New Capabilities

- `host-networking`: Fleet networking baseline — native systemd-networkd ownership via the `fleet.networking` aspect: required host facts, bridge topology with MAC continuity, DHCP client identity, resolver mechanism and safe defaults, IPv6 posture, virtual-interface non-interference, and boot-time cutover acceptance.

### Modified Capabilities

- `network-access`: The declarative network-ownership scenario is sharpened — the declared stack is native systemd-networkd, ownership handoff is boot-staged with console-backed rollback, and Tailscale integration standardizes on resolved-mediated split DNS rather than direct `resolv.conf` ownership.
- `bootstrap-storage`: LA's committed facter report remains authoritative for hardware, drivers, virtualisation, boot, and disk facts, while DHCP/interface ownership moves explicitly to the fleet networking aspect.

## Impact

- **Code**: new `modules/profiles/networking.nix`; `hosts/{home-forge,oci-melb-1,la-admin-1}/default.nix` gain aspect imports + facts and drop legacy networking options; `modules/services/admin/cockpit/loopback-tls.nix` corrects the cold-boot dependency cycle found during LA validation; `docs/architecture.md`, `docs/decisions.md`, runbooks updated.
- **Coordination**: the unlanded Engine DJ change (`windows-vm-engine-dj`) rebases on top of this parent and refactors `windows-vm.nix` to consume the host-owned `br0` (its `networking.bridges` block is scripted-only and would be ignored under networkd).
- **Operations**: three console-backed reboot windows; previous generations retained as rollback; weekly reboot exercise continues to validate persistence.
- **Risk concentration**: `la-admin-1` is identity/edge — migrated last with full break-glass (console `rescue` user) verified beforehand.
