# Delta Spec: Fleet Infrastructure

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
- **AND** `aspects.identity-client` is selected on `oci-melb-1` and `la-admin-1` only, each contributor nests its own options/config directly in its `flake.modules.nixos.identity-client` definition with no shared private leaf or wrapper, and no host or application file imports `identity-oidc` or `kanidm-host-auth` directly

#### Scenario: Reclassification preserves evaluated behavior
- **WHEN** source contributors are reclassified or relocated without changing the public deployment surface
- **THEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` evaluate with the same runtime services, secret paths/readership, deploy topology, endpoints, package set, and host outputs
- **AND** no `specialArgs`, generic compatibility bus, accidental activation, or new `mkForce` workaround is introduced