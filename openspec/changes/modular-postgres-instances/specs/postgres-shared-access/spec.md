## REMOVED Requirements

### Requirement: Shared Postgres can provision external LiteLLM access

The LiteLLM consumer is retired. Database and role provisioning for it is no longer part of the substrate, and no replacement requirement carries its per-consumer option block forward.

### Requirement: External consumer role passwords are Postgres-owned secrets

Superseded: the requirement was written around a single external consumer and Postgres-side ownership. Credential ownership is now expressed per (instance, consumer) with one authoritative encrypted source.

### Requirement: Operator-facing connection details are documented

Superseded: connection details are now required to derive from the resolved instance contract for every consumer, not documented per external integration.

### Requirement: LiteLLM Postgres authentication is Tailscale-scoped

Tailscale-scoped password authentication is retained as a general consumer property (see the modified requirement below), but the LiteLLM-specific rule is removed with its consumer.

## ADDED Requirements

### Requirement: Consumer connection details SHALL derive from the instance contract

Connection details for consumers SHALL be documented from the resolved instance contract rather than a restated provider host name, for in-repository and out-of-repository consumers alike.

#### Scenario: An operator configures a consumer outside this repository

- **WHEN** the operator needs connection details for a consumer that does not run on a fleet host
- **THEN** the documented connection string SHALL be derived from the instance's resolved endpoint (its `host`, `port`, and `fqdn`)
- **AND** it SHALL instruct the operator to retrieve or inject the password outside this repository's plaintext history

#### Scenario: An in-repository consumer resolves its database

- **WHEN** a service on another fleet host consumes the instance
- **THEN** the endpoint SHALL come from the internal contract for that instance
- **AND** the consumer SHALL NOT contain a provider host literal

### Requirement: PostgreSQL SHALL be composed from a mechanism, instances, and consumer registrations

PostgreSQL support SHALL separate the provisioning mechanism from the clusters that use it and from the consumers that register against it, so that adding a consumer or an additional cluster does not require editing a shared monolith.

#### Scenario: A consumer is added

- **WHEN** a service needs a database and role on an instance
- **THEN** the consumer's own module SHALL register the requirement in the instance's consumer registry
- **AND** the substrate module SHALL NOT need to be edited to add the consumer
- **AND** the substrate module SHALL name no consumer

#### Scenario: A cluster is placed

- **WHEN** a host runs a PostgreSQL cluster
- **THEN** that host SHALL select an instance aspect that contributes the instance to the shared mechanism
- **AND** the mechanism SHALL be imported once and SHALL NOT select any instance itself
- **AND** a second instance SHALL be addable without changing the consumer surface

#### Scenario: An instance is not declared

- **WHEN** a consumer registers against an instance that no selected aspect provides
- **THEN** evaluation SHALL fail with a named error identifying the instance and the consumer
- **AND** the failure SHALL occur before activation

#### Scenario: A consumer lacks a credential

- **WHEN** a consumer's declared authentication mode requires a credential and none is registered
- **THEN** evaluation SHALL fail with a named error naming the consumer and the instance

### Requirement: Consumers may require PostgreSQL extensions

A consumer SHALL be able to declare the SQL extensions its database requires, and the mechanism SHALL create them in that database at instance startup using `IF NOT EXISTS` semantics, while the extension packages themselves are an instance-level choice.

#### Scenario: A consumer requires a vector extension

- **WHEN** a consumer declares an extension such as `vector`
- **THEN** the instance aspect's package set SHALL provide the extension package
- **AND** the extension SHALL be created in the consumer's database during instance startup with `IF NOT EXISTS` semantics
- **AND** the consumer's role SHALL be able to use the extension without superuser rights

#### Scenario: A consumer declares no extensions

- **WHEN** a consumer declares no extensions
- **THEN** its database SHALL be created without additional extension installation

### Requirement: Instance sizing defaults SHALL be host-overridable

The mechanism's PostgreSQL tuning defaults SHALL be declared as defaults rather than fixed assignments, so a host can size its instance for its hardware without force-overriding, while hosts that override nothing keep their current evaluated values.

#### Scenario: A host sizes its instance

- **WHEN** a host overrides a PostgreSQL tuning setting
- **THEN** evaluation SHALL succeed with the host's value
- **AND** a host that overrides nothing SHALL keep the mechanism's evaluated defaults

### Requirement: Instance facts belong to the host, enablement to the aspect

An instance's listen port and data directory SHALL be declared by the host that runs the cluster, so the placement aspect stays host-agnostic and two hosts can run distinct instances without renaming collisions.

#### Scenario: A host places an instance

- **WHEN** a host selects the `postgres` aspect
- **THEN** the host's private composition SHALL declare `services.postgres.instances.<name>` with its port and data directory
- **AND** the aspect SHALL supply enablement only

### Requirement: Internal PostgreSQL endpoints SHALL resolve per instance

Consumers SHALL reach a cluster through a resolved endpoint keyed by instance, never by a restated provider host name.

#### Scenario: A cross-host consumer resolves its database

- **WHEN** a service on another host consumes an instance
- **THEN** it SHALL read `host`, `port`, and `fqdn` from the internal contract for that instance
- **AND** it SHALL NOT contain a provider host literal

#### Scenario: A declared port disagrees with the cluster

- **WHEN** an instance's real listen port differs from the port declared for it in the contract
- **THEN** evaluation SHALL fail with a named error naming the instance and both ports

#### Scenario: Consumers outside this repository

- **WHEN** a consumer runs outside this repository, such as a workstation
- **THEN** its access SHALL be expressible through the consumer's declared allowed CIDRs and the resolved instance endpoint
- **AND** registering such a consumer SHALL remain a separate policy question rather than a requirement of this composition model
