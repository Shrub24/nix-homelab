# windows-vm Delta

## Purpose

Provide a reusable KVM/QEMU Windows VM layer so Windows-only workloads can run on NixOS hosts with declarative VM shape, same-L2 LAN presence via the host-owned always-on bridge, Tailscale-only remote display, and virtiofs shares — without each workload spawning its own ad-hoc virtualization setup.

## ADDED Requirements

### Requirement: Declarative Windows VM instances

The system SHALL provide a module option namespace for defining Windows VM instances declaratively, where each instance specifies vCPU, memory, system disk, attached virtiofs shares, and network attachment. Enabling an instance MUST produce a libvirt-managed domain whose lifecycle (autostart, stop/start) is manageable through standard tooling.

#### Scenario: Instance enabled on a host
- **WHEN** a host sets a Windows VM instance to enabled and deploys
- **THEN** the host evaluates with the libvirt daemon configured and the VM domain defined, and the domain starts on boot when autostart is set

### Requirement: Guest attachment to the host-owned bridge

A VM instance SHALL attach its guest NIC to the host's declared always-on bridge (`fleet.networking.bridge`) so the guest obtains same-L2 LAN presence with broadcast/multicast reachability. The VM layer MUST NOT create or own the bridge or its physical interface, and MUST NOT use network modes that block host-to-guest traffic on the shared link.

#### Scenario: Guest reachable from LAN peers
- **WHEN** the VM is running with its guest NIC attached to the host-owned bridge
- **THEN** LAN devices on that segment can discover and open connections to the guest, and the host retains IP-level reachability of the guest

### Requirement: Remote display is private-only

Remote display access to any VM instance SHALL be restricted to private management networks (Tailscale). No VM display or console surface MAY be exposed to public networks.

#### Scenario: Display access over tailnet
- **WHEN** an operator connects to the VM display from a tailnet device
- **THEN** the session succeeds, while equivalent connection attempts from non-tailnet interfaces fail

### Requirement: Virtiofs share plumbing

The VM layer SHALL support attaching named host directories to guests as virtiofs filesystems, with per-share options for mount tag and read-only enforcement. Shares marked read-only MUST be presented to the guest without write capability.

#### Scenario: Read-only media share
- **WHEN** a share backed by the media tree is defined read-only and the guest mounts it
- **THEN** the guest can read files but writes from the guest fail

### Requirement: Explicit install-media procedure

Guest installation SHALL be driven by a per-instance command that stages install media, redefines the domain in installer mode (CD-ROM-first boot with the virtio-win driver CD attached), and starts it. Exiting installer mode SHALL be an explicit command action that removes the media and restores normal boot. The install lifecycle MUST NOT require configuration changes or deployments.

#### Scenario: First-time guest installation
- **WHEN** an operator runs the instance's install command with a Windows ISO and the virtio-win driver ISO
- **THEN** the domain is redefined with both CDs attached and CD-ROM-first boot order, and the guest boots into Windows setup

#### Scenario: Returning to normal boot
- **WHEN** the operator runs the command's clear action after installation
- **THEN** the staged media is removed and the domain is redefined back to disk-only boot without any deployment

### Requirement: Future workloads reuse the layer

Additional Windows workloads MUST be addable as new consumers of the same VM layer (new shares, new instances) without modifying the layer's core. The first consumer MUST NOT hard-code assumptions that prevent a second application on the same VM.

#### Scenario: Second application added later
- **WHEN** a future change adds another Windows application requiring a share or a second VM
- **THEN** it composes through existing instance/share options rather than introducing parallel virtualization configuration
