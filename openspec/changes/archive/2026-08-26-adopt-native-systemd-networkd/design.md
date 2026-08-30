# Design: adopt-native-systemd-networkd

## Context

The fleet runs NixOS scripted networking + dhcpcd by omission. The 2026-08-25 `home-forge` incident proved the stack fails opaquely at its one non-trivial duty (bridge cutover): dhcpcd 10.x ignores bridge-master interfaces unless an explicit `interface <br>` section exists, and NixOS's generated config never emits one — `br0` came up addressless with no error surfaced to the operator. D-031 (do-admin-1, since decommissioned) already established declarative systemd-networkd as viable here, and its boot-time cutover discipline is codified in the network-access and fleet-infrastructure specs. This change lands the networkd baseline as a parent bookmark; the Engine DJ change rebases on top and consumes host-owned bridge topology.

## Goals / Non-Goals

**Goals:**
- Native `systemd.network` units (not the `networking.useNetworkd` translation shim) as the fleet idiom
- One thin dendritic aspect owning policy; hosts contribute facts only
- Zero addressing-outcome drift: same leases, reservations, DNS answers after migration
- Per-host console-backed staged rollout with second-reboot repeatability proof

**Non-Goals:**
- Resolver flattening to a single public upstream (would break OCI VCN name resolution)
- Global IPv6 enablement (requires provider-layer work: OCI VCN/subnet/IG/security-list; home router/LA LAN currently advertise none)
- initrd networking, nftables migration, Tailscale enrollment/tag/firewall changes
- A generic multi-uplink/bond/VLAN abstraction (no current need)

## Decisions

### D1. Import-activated aspect, not option-gated service
`modules/profiles/networking.nix` activates on import; it defines only required facts and optional overrides under `fleet.networking`. Rationale: the planned dendritic composition refactor will make import-based activation idiomatic; an `enable` flag would be API we delete later. Hosts keep explicit composition (AGENTS.md #335/#336): no blanket import in `base-server.nix`.

```nix
# hosts/<host>/default.nix
imports = [ ../../modules/profiles/networking.nix ];
fleet.networking.uplink.interface = "ens18";          # required fact
fleet.networking.dns.servers = [ "1.1.1.1" "8.8.8.8" ]; # optional; null = DHCP-only
```

### D2. Aspect emits native units; exact matches only
The aspect sets `systemd.network.enable`, disables dhcpcd/scripted networking (`networking.useDHCP = false`, `networking.dhcpcd.enable = false`), enables resolved, and renders:

| Unit | Content |
| --- | --- |
| `<uplink>.network` | `MatchName = <uplink>`; bridge member when bridged (`Bridge=br0`, `RequiredForOnline=enslaved`) or DHCPv4 uplink (`DHCP=ipv4`, `RequiredForOnline=routable`) |
| `br0.netdev` | `Kind=bridge`, `MACAddress=<pinned>` (home-forge only) |
| `br0.network` | `MatchName=br0`; `DHCP=ipv4`, `ClientIdentifier=mac`, `IPv6AcceptRA` per host, `RequiredForOnline=routable` |

Exact `MatchName` only — Podman bridges, `tailscale0`, veth, and libvirt links are unmanaged by construction (no wildcard `.network`, no denylist maintenance).

### D3. Bridge MAC continuity (the reservation trap)
Kernel bridges inherit the lowest enslaved port MAC; networkd netdevs get a random machine-id-derived MAC instead (upstream behavior since v243). home-forge's router reserves `192.168.0.100` for `84:a9:3e:6b:94:44`. The aspect therefore requires `bridge.macAddress` and pins it in the netdev. `ClientIdentifier=mac` keeps the lease identity stable regardless of client-identifier defaults.

### D4. Resolver mechanism standardized; upstream policy stays heterogeneous
Resolved becomes fleet-wide (new on LA). Per-link DHCP DNS stays primary for routing domains — this preserves OCI's `169.254.169.254` VCN resolver and `homelabvcn.oraclevcn.com` route domain, which global-DNS flattening would break. Fleet defaults via `services.resolved.settings.Resolve`: `DNSOverTLS=opportunistic`, `DNSSEC=allow-downgrade`, `FallbackDNS=["1.1.1.1","8.8.8.8"]`. Strict DoT/DNSSEC would break the OCI link resolver and typical routers. LA's Tailscale switches from resolv.conf overwrite to D-Bus split-DNS — same names, better layering.

### D5. IPv6-ready, disabled
All units run `DHCP=ipv4`. `IPv6AcceptRA=false` explicitly on OCI's uplink (unprovisioned provider; prevents surprise autoconfig/default-route); home/LA keep the default so future RA-serving networks just work. Dual-stack later = flip provider chain + set `DHCP=yes`; no redesign.

### D6. Rollout ritual per host (D-031 discipline)
For each host, in order home-forge → oci-melb-1 → la-admin-1:
1. Stage: `deploy-rs --boot --skip-checks .#<host>` (never live-switch network ownership)
2. Console reboot; validation gates (below)
3. Second ordinary reboot; gates again (repeatability)
4. Proceed to next host only after gates pass twice

Gates (all hosts): correct v4 addr/route on expected interface; tailscale online; MagicDNS resolves; `resolvectl` shows expected per-link/global split; SSH over both paths. Home-forge extra: lease is the reserved `.100`, bridge MAC stays pinned, and `eno1` remains enslaved. OCI extra: `*.oraclevcn.com` resolves; podman bridges unaffected; edge routes healthy. LA extra: key-only SSH; Kanidm/edge/ntfy publishers healthy.

Rollback: boot previous generation from console (generations retained; deploy-rs auto-rollback is not trusted across a dead session).

### D7. Engine DJ coordination (parent/child seam)
`windows-vm.nix` does not exist on `main@origin` — it lives in the child change. The parent makes `br0` unconditional host topology on home-forge. The child, once rebased, drops its `networking.bridges`/`interfaces` block entirely and asserts instead that `fleet.networking.bridge` is configured when VM instances are enabled (consume-only contract). Its spec/runbook wording about "disabling DJ restores plain LAN DHCP" updates to reflect always-on topology (approved during grill). Building and strictly validating the rebased child proves the composition seam; deploying the VM layer, checking SPICE, and running the Engine/SC6000 validation spike remain the child's open tasks and SHALL NOT be used to validate this parent change.

### D8. LA adoption-contract interplay
`tests/phase-la-admin-contract.sh` forbids `networking.(interfaces|defaultGateway|useDHCP|nameservers)` tokens in LA's host file. The aspect import plus `fleet.networking.*` facts match none of those regexes, so the contract holds unchanged; the task list includes running the test rather than editing it.

### D9. Facter DHCP interplay (discovered during implementation)
nixpkgs' nixos-facter detected-DHCP module emits `networking.useDHCP = mkDefault true` on any host with a `facter.json`, which collides at equal priority with the aspect's `mkDefault false`. All three hosts carry facter reports, so the aspect itself disables the facter DHCP backend (`hardware.facter.detected.dhcp.enable = false`, plain priority) — hardware facts stay wired; only facter's legacy DHCP auto-config yields to aspect ownership. Hosts contribute no per-host workaround.

### D10. Cockpit certificate readiness belongs to the service (discovered during LA cutover)
LA's first cold boot exposed a pre-existing ordering cycle: `cockpit.socket` waited for the normal `cockpit-loopback-tls-material.service`, whose default dependencies place it after `basic.target`, while `sockets.target` must complete before `basic.target`. Systemd broke the cycle by deleting the socket start job, so the required Tailscale Serve publisher on port 9443 stayed inactive. The socket only binds the listener and does not consume certificate files; `cockpit.service` does. Certificate generation therefore remains before and required by `cockpit.service`, wanted by Caddy (edge availability must not hinge on Cockpit certificate material), while `cockpit.socket` has no certificate-material ordering edge. This preserves fail-closed TLS startup without moving a filesystem-writing service into the early socket boot transaction.

After correcting that cycle, the next cold boot exposed a separate readiness race: Cockpit's Serve command ran while the active `tailscaled.service` backend still reported `NoState`; Tailscale reached `Running` 1.25 seconds later and Termix's delayed command succeeded. Service activity is therefore not a sufficient readiness signal. Both repo-owned Serve publishers run the package-native `tailscale wait --timeout=60s` before changing Serve state, with `Restart=on-failure` (10s delay, 3 attempts per 300s) so a slow control-plane handshake recovers while a genuinely logged-out node fails loudly. This avoids custom polling and applies the root-cause correction consistently. A future Tailscale-only Cockpit redesign remains out of scope.

## Risks / Trade-offs

- **[Boot-stall risk] wait-online semantics** → deliberate `RequiredForOnline` per link (`routable` uplinks, `enslaved` members); exact-match units mean unplugged virtual links can't stall the target.
- **[Silent MAC drift] reservation loss on home-forge** → pinned netdev MAC asserted at eval; gate includes verifying the leased address is `.100`.
- **[LA resolver regression] first resolved enablement** → gates check MagicDNS + Kanidm-dependent flows; rollback path is generation boot.
- **[Dual-management footgun] half-enabled backends** → aspect disables dhcpcd/scripted paths atomically; eval assertions reject hosts importing the aspect while keeping legacy options.
- **[OCI DHCPv6 anecdote]** secondary-VNIC reports conflict with official docs → irrelevant now (DHCPv4-only), noted for the future dual-stack change.
- **[Cold-boot dependency cycles]** live activation can hide cycles once `basic.target` is active → all host gates include a second cold boot; LA additionally verifies `cockpit.socket`, its Tailscale Serve publisher, and port 9443.

## Migration Plan

Per-host, sequenced (D6). No data migration; state impact limited to lease continuity guarded by D3. Each host's previous generation remains bootable from console until the following host completes.

## Open Questions

None — resolved during grill: scope (all three hosts), br0 ownership (always-on), activation model (import), DNS (mechanism + safe defaults), IPv6 (ready-disabled).
