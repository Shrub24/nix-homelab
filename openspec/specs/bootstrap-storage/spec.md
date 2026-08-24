# Spec: Bootstrap and Storage

## Purpose

Define declarative bootstrap and storage contracts for host installation, mount layout, and provider-aware disk composition.

## Requirements

### Requirement: Bootstrap workflow is declarative
Host bootstrap SHALL be driven by repository-defined declarative workflows.

#### Scenario: Operator performs bootstrap
- **WHEN** bootstrap commands are executed for a host
- **THEN** installation inputs resolve from host/provider module state and flake wiring

### Requirement: Disk layout is encoded in disko modules
Host disk and filesystem layout SHALL be represented in disko module definitions.

#### Scenario: Storage plan is evaluated
- **WHEN** storage modules are rendered for a host
- **THEN** partition/filesystem/mount structure is derived declaratively
- **AND** `oci-melb-1` can declare root, `/srv/data`, `/nix`, and `/srv/media` as stable labeled filesystems on the OCI boot volume

### Requirement: Service-state and media mounts are separated
The storage model SHALL separate service-state and media storage at predictable, stable locations backed by stable `/dev/disk/by-id` references, where each location MAY be a dedicated filesystem mount or a directory on the root filesystem as declared per host, and a media location SHALL be present only when the host enables media workloads.

#### Scenario: Host mount contracts are validated
- **WHEN** host filesystem config is inspected
- **THEN** service-state and media locations are at distinct declared paths backed by stable `/dev/disk/by-id` references
- **AND** each location is either a dedicated mount or a root-backed directory as declared by the host
- **AND** a media location is absent on hosts that do not enable media workloads

### Requirement: Provider-specific defaults stay isolated
Provider-specific storage/bootstrap defaults SHALL remain isolated from reusable service logic.

#### Scenario: Multiple providers are supported
- **WHEN** provider modules are compared
- **THEN** provider-specific assumptions appear only in provider/host composition layers

### Requirement: Preinstalled LA hosts SHALL receive their first fleet generation non-destructively
The preinstalled LA host SHALL use captured disk, boot, and network facts; its first fleet generation SHALL be written with source-controlled boot activation through the existing sudo account and a provider-console reboot, not with `nixos-anywhere`, `disko`, or a live network-owner switch.

#### Scenario: First LA fleet boot
- **WHEN** the reviewed LA configuration is ready for its first activation
- **THEN** the operator applies `nixos-rebuild boot` through the existing sudo account
- **AND** reboots through the provider console
- **AND** no destructive disk action or live network replacement occurs

### Requirement: LA hardware facts SHALL be host-local and committed
The LA host SHALL use a `nixos-facter` report generated as root on the LA guest without swap or ephemeral capture. The report SHALL be committed with the LA host configuration and selected directly through `hardware.facter.reportPath`; reports SHALL NOT be shared between hosts or translated into hand-written driver, virtualisation, or interface configuration.

#### Scenario: LA hardware configuration evaluates
- **WHEN** `la-admin-1` is evaluated
- **THEN** its hardware-dependent configuration reads `hosts/la-admin-1/facter.json`
- **AND** KVM, UEFI, disk, and DHCP configuration derive from that host-local report

### Requirement: Existing filesystem mounts SHALL remain a minimal explicit adoption boundary
Because nixos-facter does not report filesystems, LA SHALL declare only the observed root and ESP by-UUID mounts required to preserve its existing installation. It SHALL NOT add hand-maintained hardware, driver, or network-interface configuration beside those mounts.

#### Scenario: LA mounts its adopted disk
- **WHEN** LA boots the first fleet generation
- **THEN** its root and ESP mount through the observed UUIDs
- **AND** all other hardware and DHCP behavior derives directly from the facter report

### Requirement: LA SHALL preserve its existing systemd-boot authority
The LA host SHALL preserve its current UEFI systemd-boot ESP and SHALL explicitly avoid inheriting the fleet base module's GRUB removable-media configuration.

#### Scenario: LA first fleet generation is selected
- **WHEN** the LA generation is written and rebooted through provider console
- **THEN** the existing systemd-boot path selects the new generation
- **AND** no GRUB conversion is performed

### Requirement: Host initialization SHALL have one canonical runbook
The repository SHALL document host initialization in one canonical runbook that selects either preinstalled-NixOS adoption or destructive reimage/bootstrap based on observed host state. It SHALL define the fact, SSH host-key/age, operator SSH key, outbound identity, SOPS, Tailscale, recovery, first-boot, and steady-state deployment boundaries; migration-specific runbooks SHALL reference it rather than duplicate it.

#### Scenario: Operator initializes a future host
- **WHEN** an operator adds a host after this migration
- **THEN** they follow `docs/runbooks/host-initialization.md` to choose the appropriate initialization path
- **AND** durable configuration is added only to the flake, policy, and SOPS SSOTs

### Requirement: Adopted host storage SHALL be configured from observed capacity
The LA host configuration SHALL establish service-state and build-storage settings from its observed root, `/srv/data`, boot, and 4 GB memory facts rather than inheriting DO disk or tmpfs assumptions.

#### Scenario: LA storage evaluates
- **WHEN** `la-admin-1` is evaluated
- **THEN** it does not import the DO storage or static-network configuration
- **AND** its configured `/build` and service-state paths are compatible with the captured host layout
