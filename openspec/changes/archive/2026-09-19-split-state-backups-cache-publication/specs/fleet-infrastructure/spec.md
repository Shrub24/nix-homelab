## MODIFIED Requirements

### Requirement: Fleet hosts SHALL select operational aspects explicitly

Fleet hosts SHALL declare their operational stack by selecting explicit NixOS operational aspects, including independent `state-backups`, `cache-publisher`, `builder-access`, and `observability-agent` capabilities. Selecting an operational aspect SHALL be its enablement, while intrinsic private implementations and required upstream modules MAY be composed only by that owning contributor.

#### Scenario: Host declares its operational stack

- **WHEN** a host requires mutable-state recovery and Nix closure publication
- **THEN** it explicitly selects both `state-backups` and `cache-publisher`
- **AND** it also selects builder-access and observability-agent according to host policy
- **AND** it does not select or reference the removed combined `backups` aspect
- **AND** no operational aspect silently enables another independently meaningful capability

#### Scenario: Operational conversion preserves evaluated behavior

- **WHEN** the combined backups aspect is decomposed without an intended runtime change
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` retain their existing backup units, timers, repositories, upload client, publication trigger, secret paths, monitoring behavior, and bootstrap gates
- **AND** all three hosts explicitly select both `state-backups` and `cache-publisher`, and continue to select `builder-access` and `observability-agent`, including builder access on `home-forge`
- **AND** the registry continues not to import the upstream Niks3 auto-upload module, while OCI retains the Niks3 server module import
- **AND** no support module, generic composition bus, compatibility wrapper, or new `mkForce` workaround is introduced
