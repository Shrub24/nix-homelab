## ADDED Requirements

### Requirement: Deployment aspects and infrastructure support modules SHALL be classified separately
The fleet composition model SHALL distinguish host-selected deployment capabilities from infrastructure support modules that provide typed repository data, package projections, or provenance to lower-level consumers.

#### Scenario: Host composition is reviewed
- **WHEN** a typed host registry record is inspected
- **THEN** deployment-capability selections are distinguishable from support-module and upstream-module imports
- **AND** support modules are not described as independently deployable capabilities
- **AND** the classification does not change the resulting host configuration

### Requirement: Aspect relationships SHALL reflect semantic ownership
Relationships between deployment aspects SHALL be modeled as intrinsic composition, policy co-selection, or optional integration according to whether the capabilities have meaningful independent placement.

#### Scenario: Dependency is intrinsic
- **WHEN** a capability cannot provide its declared behavior without another implementation component and that component has no meaningful independent placement
- **THEN** the owning aspect may compose the dependency directly
- **AND** the relationship is documented at the ownership boundary

#### Scenario: Fleet policy requires independently placeable capabilities together
- **WHEN** two capabilities remain meaningful independently but fleet policy requires both on a host
- **THEN** the host explicitly selects both
- **AND** a named evaluation assertion may enforce the required contract

#### Scenario: Integration is optional
- **WHEN** either capability remains useful without the other
- **THEN** integration activates only when both relevant contracts are available
- **AND** neither capability silently selects the other

## MODIFIED Requirements

### Requirement: Fleet hosts SHALL select foundation aspects explicitly
Fleet hosts SHALL declare their foundation stack by selecting explicit NixOS foundation aspects—base server policy, shell tooling, networking, Tailscale, and notifications—rather than importing legacy profile bundles. Selecting a deployment aspect SHALL be its enablement; intrinsic implementation dependencies MAY be composed by their owner, independently placeable capabilities SHALL use explicit policy co-selection, and optional integration SHALL NOT force either capability.

#### Scenario: Host declares its foundation stack
- **WHEN** a host assembly is declared
- **THEN** it lists the foundation deployment aspects it enables by name
- **AND** it does not import the legacy `base-server`, `fleet-standard`, or `networking` profile bundles
- **AND** the corresponding service, user, and firewall configuration is provided by the selected aspects rather than embedded in the host file
- **AND** infrastructure support modules are classified separately from those deployment capabilities

#### Scenario: Foundation conversion preserves evaluated behavior
- **WHEN** source ownership is redistributed without changing the public foundation surface
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` evaluate with the same runtime services, users, firewall policy, secret paths/readership, deploy topology, and host outputs
- **AND** any intentional architectural delta is classified explicitly before implementation
- **AND** no `specialArgs`, generic compatibility bus, accidental activation, or new `mkForce` workaround is introduced

### Requirement: Fleet hosts SHALL select operational aspects explicitly
Fleet hosts SHALL declare their operational stack by selecting explicit NixOS operational aspects—backups, builder-access, and observability-agent—rather than repeating leaf imports and enablement in each host assembly. Selecting an operational deployment aspect SHALL be its enablement, while its intrinsic private implementations and required upstream modules MAY be composed by the owning source contributor.

#### Scenario: Host declares its operational stack
- **WHEN** a host assembly is declared
- **THEN** it lists the operational deployment aspects it enables by name
- **AND** it does not repeat the leaf imports for state backups, niks3 upload/post-deploy, nixbuild SSH trust, or Beszel agent auth
- **AND** policy dependencies between independently placeable aspects remain explicit and testable

#### Scenario: Operational conversion preserves evaluated behavior
- **WHEN** operational aspect definitions move from a central source registry to feature-owned top-level contributors
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` retain the same operational selections and evaluated behavior
- **AND** all three hosts continue to select backups, builder-access, and observability-agent, including builder access on home-forge
- **AND** the registry continues not to import `inputs.niks3.nixosModules.niks3-auto-upload`, while OCI retains the niks3 server module import
- **AND** no support module, secret contract, monitoring behavior, deploy output, generic composition bus, compatibility wrapper, or new `mkForce` workaround is introduced
