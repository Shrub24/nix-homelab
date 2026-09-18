## 1. USB Operations

- [x] 1.1 Add the shared remote USB resolver and live attach operation to `.just/ops.just`; verify invalid IDs, missing devices, and ambiguous matches fail before `virsh attach-device`.
- [x] 1.2 Add live detach plus safe storage eject to `.just/ops.just`; verify detachment precedes sync/unmount/device removal and a failed unmount aborts removal.

## 2. Validation

- [ ] 2.1 Run `just --dry-run ops::usb-attach 21c4 0809`, `just --dry-run ops::usb-detach 21c4 0809`, `treefmt --fail-on-change`, and `openspec validate --strict windows-vm-usb-ops`.
