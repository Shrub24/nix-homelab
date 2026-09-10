# Delta Spec: Fleet Infrastructure

## ADDED Requirements

### Requirement: Fleet hosts SHALL select operational aspects explicitly
Fleet hosts SHALL declare their operational stack by selecting explicit NixOS operational aspects — backups, builder-access, and observability-agent — rather than repeating the deferred leaf imports and enablement in each host assembly, and selecting an aspect SHALL be its enablement without hidden transitive imports or a generic composition bus.

#### Scenario: Host declares its operational stack
- **WHEN** a host assembly is declared
- **THEN** it lists the operational aspects it enables by name
- **AND** it does not repeat the deferred leaf imports for state backups, niks3 upload/post-deploy, nixbuild SSH trust, or Beszel agent auth, and the registry does not import the `niks3-auto-upload` upstream module (the backups aspect owns that import)
- **AND** the corresponding service, secret, and monitoring configuration is provided by the selected aspects rather than embedded in the host file

#### Scenario: Operational conversion preserves evaluated behavior
- **WHEN** all fleet hosts convert from repeated leaf imports to explicit operational aspects
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` evaluate with the same runtime services, secret paths/readership, deploy topology, and host outputs
- **AND** all three hosts select backups, builder-access, and observability-agent, including builder access on home-forge
- **AND** the registry records no longer import `inputs.niks3.nixosModules.niks3-auto-upload`; OCI retains the niks3 server module import
- **AND** any intentional architectural delta is classified explicitly before implementation
- **AND** no hidden transitive aspect import, generic composition bus, compatibility wrapper, or new `mkForce` workaround is introduced