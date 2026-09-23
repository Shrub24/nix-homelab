## MODIFIED Requirements

### Requirement: Deployment aspects and infrastructure support modules SHALL be classified separately
The fleet composition model SHALL distinguish host-selected deployment capabilities from infrastructure support modules that provide typed repository data, package projections, or provenance to lower-level consumers.

#### Scenario: Host composition is reviewed
- **WHEN** a typed host registry record is inspected
- **THEN** deployment-capability selections are distinguishable from support-module and upstream-module imports
- **AND** support modules are not described as independently deployable capabilities
- **AND** the classification does not change the resulting host configuration

#### Scenario: Infrastructure support is selected where its data is required
- **WHEN** a module carries typed repository data consumed by other modules rather than a deployable feature surface
- **THEN** it is classified as an infrastructure-support module and selected or imported wherever its data is required
- **AND** it is not described as an independently deployable edge or service capability

#### Scenario: Web policy is selected on every repo.web consumer
- **WHEN** a host requires `config.repo.web` for notification defaults or host policy
- **THEN** `aspects.web-policy` appears in its typed registry record as an infrastructure-support selection
- **AND** all three active hosts — `oci-melb-1`, `la-admin-1`, and `home-forge` — carry the selection because all three consume `config.repo.web`
- **AND** the selection does not present web-policy as a deployable edge capability

#### Scenario: A deployment aspect merges multiple source contributors
- **WHEN** several top-level source contributors provide pieces of one coherent deployment capability
- **THEN** they merge into a single host-selected deployment aspect without a central wrapper module
- **AND** selecting the deployment aspect on a host enables all of its contributors' configuration
- **AND** `cache-publisher` is the current multi-contributor example (`cache-publisher.nix` plus the `cache-publisher/{upload-client,post-deploy}.nix` siblings), each contributor nesting its own options/config directly in its `flake.modules.nixos.cache-publisher` definition

#### Scenario: A projection is not carried by a deployment aspect
- **WHEN** a module provides only derived, read-only contract data and deploys no runtime
- **THEN** it is imported intrinsically by the participants that read it and is not published as a host-selected aspect
- **AND** a capability is not bundled with a projection such that selecting the capability becomes a condition for reading the projection

#### Scenario: Reclassification preserves evaluated behavior
- **WHEN** source contributors are reclassified or relocated without changing the public deployment surface
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` evaluate with the same runtime services, secret paths/readership, deploy topology, endpoints, package set, and host outputs
- **AND** no `specialArgs`, generic compatibility bus, accidental activation, or new `mkForce` workaround is introduced

### Requirement: Fleet hosts SHALL select deployed placement aspects explicitly
Every deployed product and provider-specific capability SHALL be represented by a named discovered NixOS deployment aspect. Typed host records SHALL be the placement authority for those aspects during this stage, while host modules retain only machine facts, explicit product variants, and host-local exceptions.

#### Scenario: OCI host placement is inspected
- **WHEN** `oci-melb-1` is evaluated
- **THEN** its typed record explicitly selects `oci`, `edge`, `cockpit`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, `phoenix`, and `kanidm-host-auth` in addition to its established foundation, operational, and support selections
- **AND** its host module directly imports none of those implementations

#### Scenario: LA host placement is inspected
- **WHEN** `la-admin-1` is evaluated
- **THEN** its typed record explicitly selects `edge`, `push-server`, `identity-provider`, `kanidm-host-auth`, `vaultwarden`, `gatus`, `beszel`, `homepage`, and `webhook` in addition to its established foundation, operational, and support selections
- **AND** its host module directly imports none of those implementations

#### Scenario: Home-forge placement is inspected
- **WHEN** `home-forge` is evaluated
- **THEN** its typed record explicitly selects `music`, `dj`, and `omniroute` in addition to its established foundation, operational, and support selections
- **AND** its host module directly imports none of those implementations

#### Scenario: Placement conversion preserves fleet behavior
- **WHEN** current implementations move behind the discovered placement aspects
- **THEN** all three host toplevels retain the same services, units, routes, secret paths/readership, permissions, packages, backup contracts, provider behavior, and deployment topology
- **AND** no new transitive aspect selection, compatibility bus, or `mkForce` workaround is introduced
