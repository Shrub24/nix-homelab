# windows-vm-usb-operations Specification

## Purpose
Provide explicit operator commands for temporary USB passthrough to a running Windows VM and safe return of removable storage to its NixOS host.

## Requirements

### Requirement: USB attachment is explicit and transient
The system SHALL let an operator attach exactly one host USB device selected by vendor and product IDs to a running Windows VM without modifying its persistent domain definition.

#### Scenario: One matching device is attached
- **WHEN** the operator supplies valid vendor and product IDs that identify exactly one connected USB device and the target VM is running
- **THEN** that device is attached to the live VM and the attachment does not persist after the VM stops

#### Scenario: Selection is missing or ambiguous
- **WHEN** no connected device or more than one connected device matches the supplied IDs
- **THEN** the command fails without attaching any device

### Requirement: USB storage detach is safely ejected
The system SHALL detach a selected USB device from the running VM, flush host writes, unmount any host-mounted filesystems exposed by the device, and remove each resulting block device from the host kernel.

#### Scenario: Attached storage is detached and ejected
- **WHEN** the operator requests detach for a uniquely matching attached USB storage device
- **THEN** the VM releases the device, host writes are flushed, mounted filesystems are unmounted, and the block device disappears from the host

#### Scenario: Unsafe unmount fails closed
- **WHEN** a filesystem exposed by the device cannot be unmounted
- **THEN** the command fails without removing the block device from the host kernel
