# Spec Delta

## Purpose

Define the repo-native contract for running tududi on `oci-melb-1`: a single Nix-managed container from a pinned image, its state under `/srv/data/tududi`, its secrets from sops, and its login through the canonical Kanidm OIDC client on a published route.

## ADDED Requirements

### Requirement: tududi SHALL run as a single Nix-managed container on oci-melb-1

The system SHALL run tududi as one declaratively managed container on `oci-melb-1`, from an image reference pinned by tag and digest, with enablement supplied by host aspect selection and all persistent state under `/srv/data/tududi`.

#### Scenario: The host selects the tududi aspect

- **WHEN** `tududi` is selected in `oci-melb-1`'s host record
- **THEN** the container is declared through NixOS rather than an externally managed compose file
- **AND** its database, uploads and backups are bind-mounted from paths under `/srv/data/tududi`
- **AND** those paths are owned by the image's runtime identity, taken from the image's own definition rather than assumed
- **AND** the container unit requires its data path to be mounted before startup

#### Scenario: The image reference is pinned

- **WHEN** tududi's image reference is evaluated
- **THEN** it carries both a tag and a digest
- **AND** it resolves to a multi-architecture index usable by the architecture the host runs

### Requirement: tududi SHALL authenticate through the canonical Kanidm OIDC client

tududi SHALL take its OIDC configuration from the repository's identity contract rather than from literal provider URLs, and SHALL receive its secret values from sops rather than from the store.

#### Scenario: OIDC is configured from the contract

- **WHEN** the `tududi` OIDC client and the `tududi` route are both declared
- **THEN** the container environment carries the issuer, client id and scopes derived from the contract
- **AND** its public base URL and allowed origin are the service's public route, so the registered callback matches the URL the application builds
- **AND** the client secret, the session secret and the bootstrap administrator password come from sops-backed files

#### Scenario: The OIDC client is missing

- **WHEN** OIDC is enabled but the canonical `tududi` client is absent from the evaluated identity contract
- **THEN** evaluation fails with a named error rather than rendering an unauthenticated deployment

### Requirement: tududi SHALL be published without a Cloudflare Access gate

The route SHALL be published to the public edge and SHALL not require a Cloudflare Access session, since the application's own login is the gate.

#### Scenario: The route is declared

- **WHEN** the `tududi` route is evaluated
- **THEN** it is public and carries `requireCloudflareAccess = false` with `oidc.enabled = true`
- **AND** its origin provider is `oci-melb-1` and its port equals the port the container serves
- **AND** its exposure mode matches the socket the container exposes under the repository's published-container convention

### Requirement: tududi state SHALL be covered by the state-backup contract

The container's persistent state SHALL be registered with `services.state-backups` so a host capture includes it.

#### Scenario: The capture job is rendered

- **WHEN** the host's state-backup job is evaluated
- **THEN** tududi's data path is part of the capture
- **AND** its sqlite database is captured coherently rather than copied while writable
