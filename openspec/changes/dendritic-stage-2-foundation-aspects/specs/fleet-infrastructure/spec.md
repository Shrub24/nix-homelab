# Delta Spec: Fleet Infrastructure

## ADDED Requirements

### Requirement: Fleet hosts SHALL select foundation aspects explicitly
Fleet hosts SHALL declare their foundation stack by selecting explicit NixOS foundation aspects — base server policy, shell tooling, networking, Tailscale, and notifications — rather than importing legacy profile bundles, and selecting an aspect SHALL be its enablement without hidden transitive imports or a generic composition bus.

#### Scenario: Host declares its foundation stack
- **WHEN** a host assembly is declared
- **THEN** it lists the foundation aspects it enables by name
- **AND** it does not import the legacy `base-server`, `fleet-standard`, or `networking` profile bundles
- **AND** the corresponding service, user, and firewall configuration is provided by the selected aspects rather than embedded in the host file

#### Scenario: Foundation conversion preserves evaluated behavior
- **WHEN** all fleet hosts convert from legacy profile bundles to explicit foundation aspects
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` evaluate with the same runtime services, users, firewall policy, secret paths/readership, deploy topology, and host outputs
- **AND** any intentional architectural delta is classified explicitly before implementation
- **AND** no `specialArgs`, generic compatibility bus, hidden transitive aspect import, or new `mkForce` workaround is introduced

### Requirement: Host machine facts SHALL be typed inputs to the base aspect
Fleet hosts SHALL provide typed bootloader choice and `/build` tmpfs size facts consumed by the base foundation aspect, so shared base configuration does not rely on per-host boot overrides or `mkForce` conflicts.

#### Scenario: Host declares its bootloader fact
- **WHEN** a host declares a typed bootloader fact (GRUB or systemd-boot)
- **THEN** the base aspect renders the corresponding bootloader configuration from the fact
- **AND** the host assembly does not repeat a conflicting bootloader override

#### Scenario: Host declares its /build size fact
- **WHEN** a host declares its typed `/build` tmpfs size
- **THEN** the base aspect renders the build mount with that size without a host-local `mkForce` override
- **AND** the evaluated filesystem behavior matches the previously forced configuration
