# Spec Delta

## Purpose

Define placement, private ingest, and clean retirement of the fleet's Langfuse and Latitude LLM-observability backends.

## ADDED Requirements

### Requirement: LLM backends SHALL share the telemetry-store host

Langfuse and Latitude SHALL run on home-forge alongside the fleet telemetry stores. Public service identities and existing access policy SHALL remain unchanged when backend placement changes.

#### Scenario: Backend placement moves

- **WHEN** the relocation is accepted
- **THEN** both stacks serve from home-forge and their former OCI application units are absent
- **AND** their existing public hostnames and login callbacks remain unchanged
- **AND** Latitude's API remains application-authenticated without an interactive Access gate, while its ingest remains private

### Requirement: Approved trial relocation SHALL initialize fresh application state

This relocation SHALL initialize fresh backend databases, queues, workflow state, and local object storage without transferring the disposable trial state. Account/project recreation SHALL be explicit, and unrelated services' state SHALL remain intact.

#### Scenario: Target initializes

- **WHEN** the stacks start on home-forge
- **THEN** their normal initialization creates fresh application schemas and queues
- **AND** Langfuse's configured seed can create its organization, project, and project keys
- **AND** the operator can recreate Latitude's account/project and mint its replacement ingest key
- **AND** OCI Paperless and forge Hindsight/AudioMuse state remain intact

### Requirement: Backend secret access SHALL remain scoped

Only the operator SHALL rewrap or edit encrypted secrets. Target decryption access SHALL cover the relocated services without exposing unrelated OCI host secrets. Reusable credentials SHALL remain usable; project credentials invalidated by fresh initialization SHALL be replaced before authenticated ingest is accepted.

#### Scenario: Target secrets are prepared

- **WHEN** the operator prepares home-forge for relocation
- **THEN** it can decrypt the backend and exporter service secrets
- **AND** Langfuse's OIDC key is available in forge's host-scoped file and the identity provider uses that same source
- **AND** forge gains no access to unrelated OCI OIDC clients

#### Scenario: Latitude ingest is enabled after recreation

- **WHEN** the operator has recreated Latitude's account/project
- **THEN** its collector uses a key issued by the fresh instance
- **AND** successful authentication is verified rather than inferred from an existing encrypted key name

### Requirement: Source retirement SHALL remove only verified backend-owned resources

After target acceptance, obsolete OCI backend units, databases, exclusive roles, queues, files, storage objects, and secret bindings SHALL be removed where ownership is verified. Shared resources SHALL remain intact. Cleanup SHALL NOT leave an abandoned deployment as an implicit rollback mechanism.

#### Scenario: Old resources are retired

- **WHEN** forge health, login, and authenticated ingest have been verified
- **THEN** the former backend resources on OCI are removed using an explicit ownership-scoped inventory
- **AND** Paperless's PostgreSQL cluster and unrelated databases, containers, storage objects, and secrets remain intact
- **AND** shared ClickHouse or object storage is not deleted on an unverified ownership assumption

### Requirement: Cutover SHALL avoid competing writers

Source application and ingest writers SHALL stop before the fresh target is exposed. Destructive cleanup SHALL follow target acceptance, not precede it. After source deletion, recovery SHALL rebuild services rather than promise restoration of discarded trial accounts or histories.

#### Scenario: Target verification fails

- **WHEN** forge fails readiness checks before source cleanup
- **THEN** routes are not switched to the unhealthy target
- **AND** source resources have not been deleted

### Requirement: Telemetry routing SHALL remain collector-owned

Applications SHALL continue using their host-local collector interface. Backend placement SHALL update collector destinations through declared endpoint policy; this relocation SHALL NOT implement the independently developing nix-fleet agent–gateway architecture.

#### Scenario: Backend-host collector is evaluated

- **WHEN** home-forge is evaluated after backend placement changes
- **THEN** its configured LLM exporter destinations resolve to the colocated services and their current origin ports
- **AND** producer modules contain no new physical gateway address

