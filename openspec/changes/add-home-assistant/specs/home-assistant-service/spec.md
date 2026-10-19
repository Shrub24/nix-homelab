# Spec Delta

## Purpose
Run Home Assistant on `home-forge` as its own container image, with the host network namespace for discovery, an operator-owned state directory, an export-first recorder backup, and a route that stays private until the instance is accepted.

## ADDED Requirements

### Requirement: Home Assistant SHALL run as the digest-pinned upstream container on the host network
The deployment SHALL run Home Assistant's own container image, pinned by tag and registry digest, on `home-forge`. The container SHALL share the host network namespace and SHALL NOT publish a port. The image SHALL resolve for the host's architecture.

#### Scenario: The container is rendered on home-forge
- **WHEN** `home-forge` is evaluated with the `home-assistant` aspect selected
- **THEN** the configuration renders one container using the pinned Home Assistant image
- **AND** the container's options include host networking and declare no published port
- **AND** no other host renders the container

#### Scenario: The image pin drifts
- **WHEN** the image reference loses its digest, or its port is published instead of shared
- **THEN** the placement contract fails with the offending value

### Requirement: Home Assistant state SHALL be operator-owned under the service data root
The configuration directory SHALL live under `/srv/data/home-assistant`, be created with restrictive permissions, and be mounted at `/config`. Nix SHALL NOT render Home Assistant's configuration files; Home Assistant and the operator own them.

#### Scenario: First start on an empty directory
- **WHEN** the container starts with an empty configuration directory
- **THEN** Home Assistant creates its own minimal configuration
- **AND** no Nix-managed file overwrites operator changes later

#### Scenario: The directory holds credentials
- **WHEN** the directory is created
- **THEN** its mode is `0700`, because `.storage` holds integration credentials and tokens

### Requirement: The listener port SHALL be single-sourced with the web policy
The port Home Assistant listens on SHALL be declared once as an option and SHALL equal the canonical route's origin port, enforced by an assertion.

#### Scenario: The policy route and the listener disagree
- **WHEN** the route's origin port differs from the module's port option
- **THEN** evaluation fails with a message naming both, rather than the edge dialling a port nothing listens on

### Requirement: The public route SHALL stay withheld until acceptance
The `hass.shrublab.xyz` route SHALL be declared in canonical web policy with `publicReady = false` and SHALL be released by setting that field, with no host-side release switch. While withheld, the edge SHALL serve no site for it.

#### Scenario: The instance is not yet accepted
- **WHEN** the edge is evaluated while `publicReady` is false
- **THEN** no ingress route is projected for `home-assistant`
- **AND** the instance is reachable on the provider's tailnet address at its own port

#### Scenario: The route is released
- **WHEN** `publicReady` is set to true in the policy
- **THEN** the edge serves the route, with Cloudflare Access enabled outside Home Assistant's own login

#### Scenario: Application OIDC is claimed
- **WHEN** the route declares `access.oidc.enabled = true` while this instance authenticates with Home Assistant's own login
- **THEN** the placement contract fails

### Requirement: The recorder database SHALL be captured export-first
The backup contract SHALL export the recorder database through SQLite's online backup API, and SHALL exclude the live database and its `-wal`/`-shm` sidecars from the raw copy of the configuration directory. The rest of the directory, including `.storage`, SHALL be captured raw.

#### Scenario: The nightly backup runs
- **WHEN** the state-backups job captures this service
- **THEN** the recorder database is exported to a consistent artifact before capture
- **AND** the live database files are not copied mid-write

#### Scenario: A restored host has only the database
- **WHEN** an operator restores the exported database but not `.storage`
- **THEN** the runbook states that this yields an empty Home Assistant, because integrations, users and tokens live in `.storage`

### Requirement: A failing container SHALL reach the notifier
The container's unit SHALL be registered with `services.notify.events` for failure, so a crash loop reaches the notification handler once the start limit trips.

#### Scenario: The container crash loops
- **WHEN** the container fails repeatedly and the unit reaches `failed`
- **THEN** its `OnFailure` handler is the notify event handler for that unit
