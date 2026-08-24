# Spec: Fleet Infrastructure Capability

## Purpose

Define the baseline infrastructure contracts for a modular NixOS homelab fleet, starting with `oci-melb-1`, while preserving secure growth to additional hosts and providers.

## Requirements

### Requirement: Host composition is host-centric and modular
The repository SHALL organize host identity separately from reusable modules so hosts can add or remove feature stacks through explicit application/service enablement without reintroducing service ownership at the host layer.

#### Scenario: A host is composed from shared modules
- **WHEN** a host configuration is declared in `hosts/<host>/default.nix`
- **THEN** it composes reusable modules rather than embedding provider/service logic inline
- **AND** it enables composed workloads through canonical application or standalone service entrypoints instead of hidden import-only activation

#### Scenario: Edge role is assigned to one host
- **WHEN** only one host is configured as ingress edge
- **THEN** other hosts can remain private-origin nodes with shared module composition patterns

### Requirement: First-host bootstrap is declarative and repeatable
The first host SHALL be bootstrappable from repository state using `nixos-anywhere` and `disko`, and rebuildable from flake outputs.

#### Scenario: Host bootstrap workflow is executed
- **WHEN** operators run bootstrap/deploy workflows
- **THEN** installation and post-install rebuilds derive from declarative flake/module state

### Requirement: Secret blast radius is path-scoped
Secrets SHALL be split into topology-aligned application, standalone-service, and host-exception scopes with explicit path rules that do not grant implicit cross-host decryption.

#### Scenario: A new host is introduced
- **WHEN** secret files and `.sops.yaml` rules are evaluated
- **THEN** only explicitly declared recipients can decrypt that host’s system/exception scopes
- **AND** the host only gains access to application or standalone-service scopes that correspond to features it explicitly enables

#### Scenario: Cross-host exception readers are required
- **WHEN** a host-scoped exception such as an OIDC handshake requires an extra reader set
- **THEN** that exception is represented in an explicit host exception scope
- **AND** its additional readers do not broaden access to unrelated application or service secret scopes

### Requirement: Access model is private-first
Management and service access SHALL be Tailscale-first and SHALL not include broad public origin exposure in baseline configuration, while allowing explicitly declared public edge bastion ingress routes.

#### Scenario: Network posture is validated
- **WHEN** network and service configs are inspected
- **THEN** baseline access remains private and non-edge origin exposure is absent by default

#### Scenario: Phase-1 edge ingress is composed
- **WHEN** a host is designated to publish selected routes
- **THEN** only explicitly declared routes are exposed at the edge bastion and private-origin upstream boundaries are preserved for services behind that edge

### Requirement: Storage model separates service state and media
The system SHALL maintain predictable persistent storage locations for service state and media using stable `/dev/disk/by-id` device references, where each location MAY be backed by either a dedicated filesystem mount or a directory on the root filesystem as declared per host, and a media location SHALL be declared only when the host enables media workloads.

#### Scenario: Storage contracts are rendered
- **WHEN** host storage modules are evaluated
- **THEN** service-state and media locations are declared at predictable stable paths with stable `/dev/disk/by-id` device references
- **AND** each location is either a dedicated filesystem mount or a directory on the root filesystem as declared by the host
- **AND** a media location is present only on hosts that enable media workloads

### Requirement: Operations remain testable and recoverable
Routine operations SHALL be supported by executable checks and documented break-glass recovery.

#### Scenario: Day-2 operation is performed
- **WHEN** an operator applies or verifies changes
- **THEN** contract checks and recovery guidance are available before and after deployment

#### Scenario: Remote network ownership is migrated
- **WHEN** a host changes networking owners or tears down the active network stack during activation
- **THEN** the new generation can be installed as the next boot target without requiring a live in-band SSH cutover
- **AND** the migration remains recoverable through provider-console reboot and generation rollback

### Requirement: Cloudflare DNS records SHALL be policy-driven
Cloudflare DNS and Zero Trust application resources for published web services SHALL be declared in OpenTofu and generated from canonical policy exports, with hostname-scoped resources deduped by public hostname rather than emitted once per internal route key.

#### Scenario: Multiple routes share one public hostname
- **WHEN** `just tofu-sync` exports policy data for OpenTofu consumption
- **THEN** the generated Cloudflare view contains one DNS record definition for the shared public hostname
- **AND** it contains at most one Access application definition for that public hostname
- **AND** route-level policy data remains available separately for non-Cloudflare consumers

### Requirement: Shared origin endpoint SHALL be managed declaratively
The shared origin endpoint used as CNAME target for published service records SHALL be managed in OpenTofu.

#### Scenario: Origin endpoint is enabled
- **WHEN** `manage_origin_record` is true
- **THEN** OpenTofu plans a DNS record for the configured origin name/content/proxy posture

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

### Requirement: Mixed-architecture validation SHALL remain reproducible
Fleet validation workflows SHALL support reproducible checks across `x86_64-linux` and `aarch64-linux` host outputs without requiring per-architecture GitHub runner ownership.

#### Scenario: Cross-host validation is triggered
- **WHEN** CI validates both active host outputs
- **THEN** the workflow can evaluate/build against the shared remote build plane
- **AND** architecture differences do not require custom runner fleet management in phase 1

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
