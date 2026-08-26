# Tasks: adopt-native-systemd-networkd

- [x] 1. Create the networking aspect module
  - refs: `modules/profiles/networking.nix`; design D1/D2/D3/D5
  - criteria: `fleet.networking` options (uplink facts, bridge, dns.servers); emits native `systemd.network.{networks,netdevs}`; enables resolved with safe defaults; disables dhcpcd/scripted networking; eval assertions for missing uplink/bridge-MAC and legacy-option conflicts
  - delegate: CoderAgent
  - verify: `nix eval` toplevel of a test host fails without facts and succeeds with them

- [x] 2. Migrate home-forge (config)
  - refs: `hosts/home-forge/default.nix`; design D3/D7
  - criteria: aspect imported; uplink `eno1` bridged to always-on `br0` pinned to `84:a9:3e:6b:94:44`; `ClientIdentifier=mac`; legacy `networking.useDHCP = true` block removed; no application owns physical networking
  - delegate: CoderAgent
  - depends: 1
  - verify: `nix build .#nixosConfigurations.home-forge.config.system.build.toplevel`

- [x] 3. Migrate oci-melb-1 (config)
  - refs: `hosts/oci-melb-1/default.nix`; design D4/D5
  - criteria: aspect imported; DHCPv4 on `enp0s6`; `IPv6AcceptRA=false`; global DNS preserved via aspect defaults; no podman/tailscale interface management
  - delegate: CoderAgent
  - depends: 1
  - verify: aarch64 toplevel evaluates

- [x] 4. Migrate la-admin-1 (config)
  - refs: `hosts/la-admin-1/default.nix`; design D4/D8
  - criteria: aspect imported; DHCPv4 on `ens18`; resolved enabled via aspect (Tailscale split-DNS mediated); host file still passes `tests/phase-la-admin-contract.sh`
  - delegate: CoderAgent
  - depends: 1
  - verify: x86_64 toplevel evaluates + contract test green

- [x] 5. Repo-wide validation
  - refs: design D6 gates (eval-time portion)
  - criteria: `nix flake check` (x86_64 local; aarch64 eval-only), `treefmt --fail-on-change`, all three toplevels evaluate
  - delegate: BuildAgent
  - depends: 2, 3, 4

- [x] 6. Live cutover: home-forge
  - refs: design D6
  - criteria: staged boot deploy + console reboot; gates pass (reserved `.100` lease, pinned bridge MAC, `eno1` enslaved, networkd/resolved/tailscale healthy, MagicDNS resolved through `tailscale0`); second ordinary reboot reproduces healthy state
  - depends: 5
  - notes: operator-performed reboots; agent verifies gates over SSH between reboots

- [x] 7. Live cutover: oci-melb-1
  - refs: design D6
  - criteria: staged boot + console reboot; gates pass (`*.oraclevcn.com` resolves, podman bridges unaffected, edge routes healthy); second reboot repeatability
  - depends: 6
  - notes: serial console is break-glass

- [x] 8. Live cutover: la-admin-1
  - refs: design D6/D8/D10; `modules/services/admin/cockpit/loopback-tls.nix`
  - criteria: staged boot + console reboot; gates pass (key-only SSH, MagicDNS via resolved, Kanidm/edge/ntfy publishers healthy); Cockpit certificate material gates `cockpit.service` without ordering `cockpit.socket`; both Tailscale Serve publishers wait for the native backend readiness signal, and ports 8443/9443 listen; second reboot repeatability
  - verify: evaluate the Cockpit service/socket and Serve pre-start dependency contracts; build and stage the corrected LA generation; verify no boot ordering cycle, both Serve units active, and ports 8443/9443 reachable on both validation boots
  - depends: 7
  - notes: identity/edge host — migrated last; console `rescue` user verified before starting; first networkd boot passed networking gates but exposed the pre-existing Cockpit cold-boot cycle, and the corrected boot exposed a Tailscale `NoState` race before backend readiness

- [x] 9. Documentation and decision record
  - refs: `docs/architecture.md`, `docs/decisions.md`, `docs/runbooks/host-initialization.md`, `openspec/specs/bootstrap-storage/spec.md`
  - criteria: architecture networking section reflects native networkd ownership; new decision entry records adoption rationale + incident provenance; runbook wording updated (facter + aspect facts); bootstrap-storage delta assigns DHCP/interface ownership to the networking aspect without weakening facter hardware ownership
  - delegate: DocWriter
  - depends: 8

- [x] 10. Rebase Engine DJ child onto this parent
  - refs: design D7; change `windows-vm-engine-dj`
  - criteria: child rebased on parent bookmark; `windows-vm.nix` drops `networking.bridges` block and asserts host-owned bridge exists when instances enabled; its spec/runbook updated for always-on topology; home-forge toplevel builds; both changes validate strict; child live-validation tasks remain open and undeployed
  - depends: 9
  - notes: separate bookmark; pushed after this parent; do not import or deploy the child to validate the networking parent
