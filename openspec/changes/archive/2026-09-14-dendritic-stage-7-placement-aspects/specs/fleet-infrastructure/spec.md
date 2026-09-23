## MODIFIED Requirements

### Requirement: Host composition is host-centric and modular
The repository SHALL construct fleet hosts from typed `nixos.configurations.<host>` records and SHALL organize host identity separately from reusable discovered aspects so hosts select every deployed product and platform capability explicitly without importing service, application, or provider implementation files.

#### Scenario: A host is composed from shared modules
- **WHEN** a host configuration is declared under `modules/hosts/<host>/`
- **THEN** a typed registry entry declares its system and explicit aspect composition
- **AND** the flake materializes the same `nixosConfigurations.<host>` output expected by operator and CI workflows
- **AND** the host record selects reusable aspects rather than embedding or directly importing provider or service implementation
- **AND** workload selection remains explicit rather than arising from accidental import-tree discovery

#### Scenario: Edge role is assigned to one host
- **WHEN** only one host is configured as ingress edge
- **THEN** that host and private-origin hosts may co-select the discovered `edge` aspect with explicit role variants
- **AND** other hosts remain free of edge runtime activation

## ADDED Requirements

### Requirement: Fleet hosts SHALL select deployed placement aspects explicitly
Every deployed product and provider-specific capability SHALL be represented by a named discovered NixOS deployment aspect. Typed host records SHALL be the placement authority for those aspects during this stage, while host modules retain only machine facts, explicit product variants, and host-local exceptions.

#### Scenario: OCI host placement is inspected
- **WHEN** `oci-melb-1` is evaluated
- **THEN** its typed record explicitly selects `oci`, `edge`, `cockpit`, `paperless`, `postgres`, `ai-gateway`, `karakeep`, `niks3-cache`, and `phoenix` in addition to its established foundation, operational, identity-client, and support selections
- **AND** its host module directly imports none of those implementations

#### Scenario: LA host placement is inspected
- **WHEN** `la-admin-1` is evaluated
- **THEN** its typed record explicitly selects `edge`, `cockpit`, `push-server`, `identity-provider`, and `admin-hub` in addition to its established foundation, operational, identity-client, and support selections
- **AND** its host module directly imports none of those implementations

#### Scenario: Home-forge placement is inspected
- **WHEN** `home-forge` is evaluated
- **THEN** its typed record explicitly selects `music`, `dj`, and `omniroute` in addition to its established foundation, operational, and support selections
- **AND** its host module directly imports none of those implementations

#### Scenario: Placement conversion preserves fleet behavior
- **WHEN** current implementations move behind the discovered placement aspects
- **THEN** all three host toplevels retain the same services, units, routes, secret paths/readership, permissions, packages, backup contracts, provider behavior, and deployment topology
- **AND** no new transitive aspect selection, compatibility bus, or `mkForce` workaround is introduced
