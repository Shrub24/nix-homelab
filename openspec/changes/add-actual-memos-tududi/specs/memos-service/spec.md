# Spec Delta

## Purpose

Define the repo-native contract for running Memos on `oci-melb-1`: a native nixpkgs service with its state under `/srv/data/memos`, published without a Cloudflare Access gate, and with its identity-provider configuration rendered into the directory the service loads providers from — with the manual fallback recorded for the case where that file is not honoured.

## ADDED Requirements

### Requirement: Memos SHALL run as a native Nix-managed service on oci-melb-1

The system SHALL run Memos from the nixpkgs `services.memos` module on `oci-melb-1`, with enablement supplied by host aspect selection, sqlite storage, and its mutable state under `/srv/data/memos`.

#### Scenario: The host selects the memos aspect

- **WHEN** `memos` is selected in `oci-melb-1`'s host record
- **THEN** `services.memos.enable` is set by that selection
- **AND** the rendered service runs as the module's dedicated account with `/srv/data/memos` as its data directory
- **AND** the instance URL is the service's public route so generated links resolve publicly

#### Scenario: The service socket is loopback-bound

- **WHEN** the Memos environment is evaluated
- **THEN** its address is loopback on the port the route declares
- **AND** the module's firewall option stays unset, because its listener needs no firewall entry behind the edge

### Requirement: Memos SHALL be declared an OIDC consumer whose provider configuration is a rendered file

The system SHALL declare Memos' route, its Kanidm OIDC client, the client's secret, and its identity-provider configuration as a file rendered into the directory Memos loads providers from, SHALL mark the route as an application-OIDC consumer, and SHALL document the fallback for the case where that file is not honoured, so that any undeclared portion is explicit rather than implied.

#### Scenario: The declared identity surface is complete

- **WHEN** the `memos` OIDC client, the `memos` route and the provider file are declared
- **THEN** the identity provider provisions a client whose registered callback is the route's public URL plus Memos' callback path
- **AND** the client's secret is sourced from the host-scoped secret file
- **AND** the route carries `oidc.enabled = true` and `requireCloudflareAccess = false`

#### Scenario: The provider file is derived rather than transcribed

- **WHEN** the provider file's contents are rendered
- **THEN** it holds a single OAuth2 provider at the path Memos loads providers from, carrying a name, the authorization, token and userinfo endpoints, and the client secret
- **AND** every endpoint value derives from the identity contract rather than from a hand-copied document
- **AND** its field mapping keys on the identifier claim that stays stable across a rename
- **AND** the file is readable by the account the service runs as
- **AND** password authentication is left available as the recovery path

#### Scenario: The manual fallback is documented

- **WHEN** the running service does not honour the rendered provider file
- **THEN** a runbook states that the SSO provider is configured in Memos' instance settings instead, lists the field values to enter, and identifies them as read from the live provider discovery document
- **AND** it records that a provider configured that way lives in Memos' database, so it is neither reviewable in the repository nor restored by a reimage

### Requirement: Memos SHALL be published without a Cloudflare Access gate

The route SHALL be published to the public edge and SHALL not require a Cloudflare Access session, because the mobile application and API tokens cannot carry one.

#### Scenario: The route is declared

- **WHEN** the `memos` route is evaluated
- **THEN** it is public with `requireCloudflareAccess = false`
- **AND** its origin provider is `oci-melb-1` and its port equals the service's listener
- **AND** its exposure mode is the edge-local loopback mode the socket supports

### Requirement: Memos state SHALL be covered by the state-backup contract

The service's mutable state SHALL be registered with `services.state-backups` so a host capture includes it.

#### Scenario: The capture job is rendered

- **WHEN** the host's state-backup job is evaluated
- **THEN** Memos' data path is part of the capture
- **AND** its sqlite database is captured coherently rather than copied while writable
