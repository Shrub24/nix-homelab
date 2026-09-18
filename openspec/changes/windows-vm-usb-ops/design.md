## Context

See `proposal.md`. The Windows VM layer defines persistent libvirt XML, while `.just/ops.just` already owns remote operator actions such as the SPICE tunnel. Occasional USB media should not make VM startup depend on hardware presence.

## Goals / Non-Goals

**Goals:**
- Reuse libvirt live `hostdev` attachment.
- Select one concrete device and fail on ambiguity.
- Safely eject storage after guest detachment.

**Non-Goals:**
- Persistent USB passthrough.
- PCI/VFIO controller passthrough.
- Automatic attachment based on a physical port.

## Decisions

### USB-1 — Keep passthrough transient

Recipes generate a temporary libvirt USB `hostdev` document and use `virsh attach-device`/`detach-device --live`. No `--config` or VM module option is added. This avoids failed VM starts when a device is absent.

### USB-2 — Resolve a unique device from sysfs

A remote helper validates four-digit hexadecimal IDs, scans `/sys/bus/usb/devices/*`, and requires exactly one match. It reads the current bus/device numbers from sysfs for the live libvirt operation instead of treating them as durable configuration.

### USB-3 — Eject through the owning USB block-device tree

After detachment, the helper calls `sync`, discovers block devices beneath the matched USB sysfs node, unmounts their mounted filesystems, and writes to each SCSI device's `delete` attribute. Failure to unmount aborts removal.

### USB-4 — Put the interface in ops.just

Two thin recipes call one private remote helper. Defaults are `home-forge` and `windows-dj`, matching the existing DJ VM, while explicit parameters keep the operation reusable.

## Risks / Trade-offs

- [Two identical devices match] → Fail and require temporarily unplugging one rather than guessing.
- [Guest still writes while detaching] → Operators eject in Windows first; libvirt detach completes before host flush/removal.
- [Non-storage USB device has no block child] → Detach succeeds and ejection becomes a no-op.
- [Host sysfs layout changes] → Resolve current topology on each invocation rather than persisting bus/device numbers.
