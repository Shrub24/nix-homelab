# Spec Delta: bootstrap-storage (MODIFIED)

## MODIFIED Requirements

### Requirement: LA hardware facts SHALL be host-local and committed
The LA host SHALL use a `nixos-facter` report generated as root on the LA guest without swap or ephemeral capture. The report SHALL be committed with the LA host configuration and selected directly through `hardware.facter.reportPath`; reports SHALL NOT be shared between hosts or translated into hand-written driver or virtualisation configuration. The fleet networking aspect SHALL disable facter's detected-DHCP backend and derive interface/DHCP ownership from explicit `fleet.networking` host facts.

#### Scenario: LA hardware configuration evaluates
- **WHEN** `la-admin-1` is evaluated
- **THEN** its hardware-dependent configuration reads `hosts/la-admin-1/facter.json`
- **AND** KVM, UEFI, and disk configuration derive from that host-local report
- **AND** native networkd and DHCP configuration derive from the host's `fleet.networking` uplink facts

### Requirement: Existing filesystem mounts SHALL remain a minimal explicit adoption boundary
Because nixos-facter does not report filesystems, LA SHALL declare only the observed root and ESP by-UUID mounts required to preserve its existing installation. It SHALL NOT add hand-maintained hardware or driver configuration beside those mounts; physical interface and DHCP ownership SHALL be expressed through the fleet networking aspect rather than duplicated raw networkd units.

#### Scenario: LA mounts its adopted disk
- **WHEN** LA boots the first fleet generation
- **THEN** its root and ESP mount through the observed UUIDs
- **AND** all other hardware behavior derives directly from the facter report
- **AND** DHCP/interface behavior derives from the fleet networking aspect
