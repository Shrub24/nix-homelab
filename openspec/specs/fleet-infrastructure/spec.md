# Spec: Fleet Infrastructure Capability

## Purpose

Define the baseline infrastructure contracts for a modular NixOS homelab fleet, starting with `oci-melb-1`, while preserving secure growth to additional hosts and providers.

## Requirements

### Requirement: Host composition is host-centric and modular
The repository SHALL construct fleet hosts from typed `nixos.configurations.<host>` records and SHALL organize host identity separately from reusable aspects and modules so hosts can select feature stacks explicitly without owning service implementation.

#### Scenario: A host is composed from shared modules
- **WHEN** a host configuration is declared under `modules/hosts/<host>/`
- **THEN** a typed registry entry declares its system and explicit composition
- **AND** the flake materializes the same `nixosConfigurations.<host>` output expected by operator and CI workflows
- **AND** the host composes reusable aspects or modules rather than embedding provider or service logic inline
- **AND** workload selection remains explicit rather than arising from accidental import-tree discovery

#### Scenario: Edge role is assigned to one host
- **WHEN** only one host is configured as ingress edge
- **THEN** other hosts can remain private-origin nodes with shared composition patterns

### Requirement: First-host bootstrap is declarative and repeatable
The first host SHALL be bootstrappable from repository state using `nixos-anywhere` and `disko`, and rebuildable from flake outputs whose host metadata is derived from the typed configuration registry.

#### Scenario: Host bootstrap workflow is executed
- **WHEN** operators run bootstrap or deploy workflows
- **THEN** installation and post-install rebuilds derive from declarative flake/module state
- **AND** existing host names and bootstrap-facing flake outputs remain compatible

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
Fleet host outputs SHALL consume the primary repository package baseline from `nixos-unstable` unless an explicit documented exception is introduced, independent of the system evaluating the flake.

#### Scenario: Active host outputs are evaluated
- **WHEN** `nixosConfigurations.oci-melb-1`, `nixosConfigurations.la-admin-1`, and `nixosConfigurations.home-forge` are evaluated
- **THEN** each host resolves packages for its declared target system from the primary unstable baseline input
- **AND** per-host checks do not force an evaluator to build another architecture locally

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

### Requirement: Host machine facts SHALL be typed inputs to the base aspect
Fleet hosts SHALL provide typed bootloader choice and `/build` tmpfs size facts consumed by the base foundation aspect, so shared base configuration does not rely on per-host boot overrides or `mkForce` conflicts.

#### Scenario: Host declares its bootloader fact
- **WHEN** a host declares a typed bootloader fact (GRUB or systemd-boot)
- **THEN** the base aspect renders the corresponding bootloader configuration from the fact
- **AND** the host assembly does not repeat a conflicting bootloader override

#### Scenario: Host declares its /build size fact
- **WHEN** a host declares its typed `/build` tmpfs size
- **THEN** the base aspect renders the build mount with that size without a host-local `mkForce` override
- **AND** the evaluated filesystem behavior matches the previously forced configuration

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
