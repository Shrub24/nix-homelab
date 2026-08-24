# engine-dj-library Delta

## Purpose

Host the Engine DJ library database and its music on Linux storage so the SC6000 consumes Engine Remote Library from a VM while Linux-side tooling retains direct, exclusive access to the library database whenever the guest is stopped.

## ADDED Requirements

### Requirement: Library database lives on Linux storage

The Engine DJ library directory (including the SQLite database) SHALL reside on the host's native service-state filesystem. The layout MUST NOT require the host to mount foreign-filesystem images to read or back up the library.

#### Scenario: Offline worker access
- **WHEN** the VM is stopped and an operator or sync worker inspects the library directory
- **THEN** the database files are present as ordinary files on the host filesystem, readable without starting the guest

### Requirement: Stable guest path mapping

The library share SHALL be presented to the guest at a stable drive letter, and the guest-visible Engine library path MUST be established once via a fixed symbolic link from the default library location. Library paths recorded in the database MUST remain valid across guest reboots.

#### Scenario: Reboot preserves paths
- **WHEN** the guest reboots with the same share definition
- **THEN** the Engine library resolves at the identical path and previously imported tracks resolve without relocation

### Requirement: Single-writer mutual exclusion

Access to the library directory SHALL be mutually exclusive between the running guest and Linux-side writers: while the VM runs, no local sync worker may write to the library; while a sync worker operates, the VM must not be running. This exclusion SHALL be enforced by unit-level dependency (conflict) rather than by convention only.

#### Scenario: Worker start stops VM
- **WHEN** a Linux sync worker targeting the library starts while the VM is running
- **THEN** the VM is stopped first (or the worker start fails), and never both operate concurrently

#### Scenario: VM start stops workers
- **WHEN** the VM is started while a library-writing worker is active
- **THEN** the worker is stopped before the guest gains access to the library

### Requirement: Music served read-only

Music files exposed to the guest SHALL be shared read-only. Track audio originates from the authoritative media tree; the guest MUST NOT be able to modify or delete media files.

#### Scenario: Guest cannot mutate media
- **WHEN** the guest attempts to write into the mounted music share
- **THEN** the write fails and the host media tree is unchanged

### Requirement: Backup scope covers the library

The library directory SHALL be included in host state backups. Backups MUST NOT run concurrently with any writer to the library (guest or worker).

#### Scenario: Consistent backup window
- **WHEN** the state backup job runs
- **THEN** it captures the library only while neither the VM nor a sync worker holds write access

### Requirement: Validation gate before production reliance

Because upstream does not document Engine DJ behavior on virtiofs-backed libraries, the change SHALL include a validation pass that exercises: guest boot with drivers, Engine DJ launch against the shared library, track import, SC6000 Remote Library connection over the bridge, and database integrity across a full guest reboot — before the layout is treated as settled.

#### Scenario: Spike failure triggers fallback
- **WHEN** the validation pass shows database corruption or unusable locking on the shared layout
- **THEN** the design falls back to a guest-local database with copy-in/copy-out exchange during VM-stopped windows, preserving Linux-side tooling
