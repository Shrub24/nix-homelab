# Spec Delta

## Purpose

Define the repo-native contract for running Actual Budget on `oci-melb-1`: a native nixpkgs service with its state under `/srv/data/actual`, Kanidm OpenID login with the password method retained as a fallback, and a published route that does not put the application's own clients behind a Cloudflare Access gate they cannot traverse.

## ADDED Requirements

### Requirement: Actual Budget SHALL run as a native Nix-managed service on oci-melb-1

The system SHALL run Actual Budget from the nixpkgs `services.actual` module on `oci-melb-1`, with enablement supplied by host aspect selection and its mutable state under `/srv/data/actual`, rather than as a container or an externally managed deployment.

#### Scenario: The host selects the actual aspect

- **WHEN** `actual` is selected in `oci-melb-1`'s host record
- **THEN** `services.actual.enable` is set by that selection
- **AND** the rendered service runs under a dedicated system account that owns `/srv/data/actual`
- **AND** the budget files and `account.sqlite` live under that path rather than the module's default state directory

#### Scenario: The service socket is loopback-bound

- **WHEN** the Actual service configuration is evaluated
- **THEN** its listener is bound to loopback on the port the route declares
- **AND** no firewall entry is opened for it

### Requirement: Actual Budget SHALL authenticate through the canonical Kanidm OIDC client

Actual Budget SHALL take its OpenID configuration from the repository's identity contract rather than from literal provider URLs, and SHALL retain password authentication as a fallback while upstream marks OpenID as a preview feature.

#### Scenario: OpenID is configured from the contract

- **WHEN** the `actual` OIDC client and the `budget` route are both declared
- **THEN** the rendered server configuration carries the discovery URL, client id and public server hostname from the contract
- **AND** the client secret is supplied from the host-scoped secret file rather than written into the store
- **AND** `loginMethod` selects OpenID while `allowedLoginMethods` keeps password available

#### Scenario: The OIDC client is missing

- **WHEN** OpenID is enabled but the canonical `actual` client is absent from the evaluated identity contract
- **THEN** evaluation fails with a named error rather than rendering a configuration without identity

### Requirement: Actual Budget SHALL be published without a Cloudflare Access gate

The route SHALL be published to the public edge, SHALL not require a Cloudflare Access session, and SHALL declare the application's own OIDC login as its identity mechanism.

#### Scenario: The route is declared

- **WHEN** the `budget` route is evaluated
- **THEN** it is public and carries `requireCloudflareAccess = false` with `oidc.enabled = true`
- **AND** its origin provider is `oci-melb-1` and its port equals the service's listener
- **AND** its exposure mode is the edge-local loopback mode the socket supports

### Requirement: Actual Budget state SHALL be covered by the state-backup contract

The service's mutable state SHALL be registered with `services.state-backups` so a host capture includes it.

#### Scenario: The capture job is rendered

- **WHEN** the host's state-backup job is evaluated
- **THEN** Actual Budget's data path is part of the capture
- **AND** its sqlite database is captured coherently rather than copied while writable
