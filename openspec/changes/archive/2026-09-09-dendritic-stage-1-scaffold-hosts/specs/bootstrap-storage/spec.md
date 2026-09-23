## MODIFIED Requirements

### Requirement: Bootstrap workflow is declarative
Host bootstrap SHALL be driven by repository-defined declarative workflows whose host selection and bootstrap metadata derive from the typed host registry.

#### Scenario: Operator performs bootstrap
- **WHEN** bootstrap commands are executed for a host
- **THEN** installation inputs resolve from host/provider module state and flake wiring
- **AND** bootstrap metadata is exposed through a stable flake output derived from the selected host record
- **AND** reimage-only metadata is excluded from automatic module imports

### Requirement: LA hardware facts SHALL be host-local and committed
The LA host SHALL use a `nixos-facter` report generated as root on the LA guest without swap or ephemeral capture. The report SHALL be committed beside the LA host configuration under `modules/hosts/la-admin-1/` and selected directly through `hardware.facter.reportPath`; reports SHALL NOT be shared between hosts or translated into hand-written driver or virtualisation configuration. The fleet networking aspect SHALL disable facter's detected-DHCP backend and derive interface/DHCP ownership from explicit `fleet.networking` host facts.

#### Scenario: LA hardware configuration evaluates
- **WHEN** `la-admin-1` is evaluated
- **THEN** its hardware-dependent configuration reads `modules/hosts/la-admin-1/facter.json`
- **AND** KVM, UEFI, and disk configuration derive from that host-local report
- **AND** native networkd and DHCP configuration derive from the host's `fleet.networking` uplink facts
