# host-storage-recovery Specification

## Purpose
Require that a recovered or reshaped host storage layout becomes canonical declarative state, with one declarative owner per shared media directory and offline rebuild guidance alongside the recovered layout.
## Requirements
### Requirement: Recovered host storage reshapes SHALL be captured declaratively
When a host storage layout is recovered or reshaped, the repository SHALL record the resulting mount and partition contract as canonical host state.

#### Scenario: A recovered host layout is reviewed
- **WHEN** the recovered host configuration and storage module are inspected
- **THEN** the rendered filesystem contract matches the intended recovered layout
- **AND** the host no longer depends on stale pre-recovery disk assumptions

### Requirement: Shared media directories SHALL have one declarative directory owner
Shared media paths used by multiple services SHALL have one authoritative directory-creation definition, while other modules may layer ACLs or marker files without redefining the same directory ownership contract.

#### Scenario: Tmpfiles rules are rendered for shared media paths
- **WHEN** tmpfiles rules are evaluated for paths such as `/srv/media/library` or `/srv/media/quarantine`
- **THEN** each shared directory has a single canonical directory-creation rule
- **AND** additional ACL or marker-file rules do not produce duplicate directory ownership declarations

### Requirement: Recovery workflows SHALL include offline rebuild guidance
Host recovery after storage disruption SHALL have a documented offline rebuild workflow that covers rescue mounting, chroot requirements, bootloader update prerequisites, and post-recovery validation.

#### Scenario: Operator follows the recovery runbook
- **WHEN** an operator performs break-glass recovery from a rescue instance
- **THEN** the runbook includes required mounts for root, `/nix`, `/boot`, and service filesystems as applicable
- **AND** it includes the commands needed to rebuild bootable system state and verify successful recovery

