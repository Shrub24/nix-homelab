## Why

Operators need a repeatable way to hot-plug occasional USB devices into `windows-dj` and safely return removable storage to the host without making transient hardware part of the declarative VM boot contract.

**Core Value:** Keep Windows VM USB use explicit, reversible, and independent of host deployment.

Constraints:
- A missing USB device must not block VM startup.
- Attachments are live-only and disappear when the VM stops.
- Detach/eject must flush and unmount host storage before removing it from the host kernel.
- Device selection uses explicit USB vendor and product IDs and fails when the match is absent or ambiguous.

## What Changes

- Add `just ops::usb-attach <vendor> <product>` to live-attach one matching host USB device to `windows-dj`.
- Add `just ops::usb-detach <vendor> <product>` to detach it from the VM and safely eject host block devices exposed by it.
- Keep USB passthrough out of the persistent libvirt domain XML.

## Capabilities

### New Capabilities

- `windows-vm-usb-operations`: Explicit live USB attachment and safe detach/eject operations for Windows VM instances.

### Modified Capabilities

- None.

## Impact

- `.just/ops.just`
- Operator commands on `home-forge`; no VM restart, deployment, secret, or persistent domain change
- Related existing capability: `openspec/specs/windows-vm/spec.md`
