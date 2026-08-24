## ADDED Requirements

### Requirement: Deployment topology SHALL isolate physical target selection
Fleet deployment metadata SHALL declare the active edge target and deploy order as explicit physical-host facts, while service consumers resolve canonical routing metadata from policy rather than deployment host names.

#### Scenario: Operator tooling selects the edge host
- **WHEN** an operator command, test, or deployment workflow needs the active edge target
- **THEN** it resolves the declared deployment edge host from central deployment metadata
- **AND** service URL and access consumers do not require that physical host name

### Requirement: Adopted admin hosts SHALL derive platform configuration from observed facts
An existing NixOS host adopted into the fleet SHALL use captured hardware, boot, disk, and network facts, and SHALL NOT inherit provider-specific installation, networking, or destructive disk configuration from a different host.

#### Scenario: LA admin host is adopted
- **WHEN** `la-admin-1` is added to the fleet
- **THEN** its host assembly uses configuration derived from the LA host's observed system facts
- **AND** it does not import DigitalOcean networking or provider defaults
- **AND** normal adoption does not run destructive disk provisioning against the live volume

### Requirement: Replacement host cutover SHALL preserve a recoverable source
When an active host is replaced, the source host SHALL remain available as the rollback origin until the replacement has passed the declared service, backup, and recovery verification gates.

#### Scenario: Admin host is cut over to LA
- **WHEN** public edge, identity, and admin roles move from DigitalOcean to LA
- **THEN** the DigitalOcean host remains a rollback source until LA backup and recovery verification succeeds
- **AND** its provider snapshot is retained according to the operator's recovery window

## MODIFIED Requirements

### Requirement: Fleet package baseline defaults to unstable
Fleet host outputs SHALL consume the primary repository package baseline from `nixos-unstable` unless an explicit documented exception is introduced.

#### Scenario: Active host outputs are evaluated
- **WHEN** `nixosConfigurations.oci-melb-1` and `nixosConfigurations.la-admin-1` are built from the flake
- **THEN** both host outputs resolve packages from the primary unstable baseline input

### Requirement: Recoverable hosts SHALL include host-scoped state backup architecture
Fleet hosts that carry mutable service state SHALL support host-scoped declarative backup wiring as part of the recoverable baseline.

#### Scenario: Recoverability baseline is evaluated for active hosts
- **WHEN** `nixosConfigurations.la-admin-1` and `nixosConfigurations.oci-melb-1` are reviewed for operational baseline coverage
- **THEN** each host can opt into canonical host-scoped state backup wiring without introducing cross-host repository sharing by default

### Requirement: Active hosts SHALL support a shared remote substitute baseline
Active hosts in the fleet SHALL support a shared remote substitute-consumer baseline through reusable build-profile composition, including the sovereign S3-backed binary cache as a durable secondary tier.

#### Scenario: Active host baseline is reviewed
- **WHEN** `nixosConfigurations.la-admin-1` and `nixosConfigurations.oci-melb-1` are inspected
- **THEN** both hosts inherit the same shared substitute/trust baseline through common host profile composition
- **AND** both include the `nixbuild.net` substituter and the sovereign S3 cache substituter in the configured priority order
- **AND** host files remain thin assembly layers rather than direct owner of deep substitute/trust wiring

#### Scenario: Current provider defaults remain policy-driven
- **WHEN** the fleet uses `nixbuild.net` as the primary substitute provider and the sovereign cache as secondary
- **THEN** provider-specific URLs and signing keys come from canonical policy defaults
- **AND** the reusable host build profile stays generic enough to carry future substitute/trust defaults without a provider-branded host module

### Requirement: Cache host SHALL own the sovereign binary cache infrastructure
`oci-melb-1` SHALL host the niks3 server and shared PostgreSQL service that back the fleet's sovereign binary cache, while other active hosts SHALL NOT replicate this infrastructure.

#### Scenario: Cache infrastructure is deployed on the cache host
- **WHEN** `oci-melb-1` is evaluated and deployed
- **THEN** the niks3 server is running as a NixOS service
- **AND** PostgreSQL is running with a niks3 database and user
- **AND** the S3 backend configuration points at the dedicated `shrublab-nix-cache` R2 bucket

#### Scenario: Non-cache hosts do not carry cache infrastructure
- **WHEN** `la-admin-1` is evaluated
- **THEN** it does not include niks3 server, PostgreSQL, or cache signing key configuration
- **AND** it consumes the sovereign cache only as a substituter, not as an infrastructure provider
