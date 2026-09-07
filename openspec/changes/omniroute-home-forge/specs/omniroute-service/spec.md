# omniroute-service Specification (Delta)

## Purpose

Declaratively deploy the OmniRoute LLM router on `home-forge` as a private, tailnet-reachable service: a thin container topology (app + redis sidecar) with sops-injected bootstrap secrets, while runtime configuration and state remain imperative and app-owned under the data directory.

## ADDED Requirements

### Requirement: OmniRoute runs as an app container with a redis sidecar

When `services.omniroute.enable` is set, the service SHALL run the pinned OmniRoute OCI image as an auto-started podman container alongside a redis sidecar container, with the sidecar reachable from the app by container-name DNS and NOT published to the host.

#### Scenario: Stack activation on home-forge

- **WHEN** `home-forge` evaluates with `services.omniroute.enable = true`
- **THEN** two podman containers start (`omniroute` and its redis sidecar) using image refs pinned by tag and digest in `policy/oci-images.nix`
- **AND** the app reaches redis via the sidecar's container name on the internal container network
- **AND** the redis sidecar publishes no host port

#### Scenario: Image reference stays Renovate-managed

- **WHEN** the OmniRoute image ref is updated upstream
- **THEN** the bump lands as a tag-plus-digest update to the single `policy/oci-images.nix` entry consumed by the module's `image` option default

### Requirement: Runtime secrets are sops-injected and never baked

The module SHALL consume `JWT_SECRET`, `API_KEY_SECRET`, `STORAGE_ENCRYPTION_KEY`, `INITIAL_PASSWORD`, and `OMNIROUTE_WS_BRIDGE_SECRET` from a sops-rendered environment file bound through the host's `secretFiles` contract, and SHALL fail evaluation when the bound secret file is missing. No secret material SHALL be embedded in the image reference, module code, or repository plaintext. `STORAGE_ENCRYPTION_KEY` SHALL be unique to the server deployment and remain stable for the lifetime of persisted encrypted data.

#### Scenario: Missing host secret file blocks activation

- **WHEN** `services.omniroute.enable = true` but the bound `secretFiles.host` path does not exist
- **THEN** host evaluation fails with a required-secret assertion naming `services.omniroute`

#### Scenario: Secrets reach the container only at runtime

- **WHEN** the omniroute container starts
- **THEN** it receives the five runtime secrets through an environment file rendered by sops at activation time
- **AND** restarting the container is triggered when the environment file content changes

#### Scenario: Storage encryption key survives redeploys

- **WHEN** existing OmniRoute data is reused across a deployment or rollback
- **THEN** the same server-specific `STORAGE_ENCRYPTION_KEY` is supplied
- **AND** the workstation's local OmniRoute storage key is not reused

### Requirement: Access stays private to LAN and tailnet

The service SHALL bind its dashboard/API port on all host interfaces with no public ingress: no `web-services.nix` route, no Cloudflare/edge exposure, and no OIDC dashboard login. Reachability SHALL be LAN plus Tailscale (MagicDNS) only, with dashboard sessions valid over plain HTTP on the private network.

#### Scenario: Private posture is checked

- **WHEN** the deployed service is inspected
- **THEN** the dashboard/API port is reachable from the LAN and over the tailnet at the host's MagicDNS name
- **AND** no public route, reverse-proxy entry, or OIDC configuration exists for the service

### Requirement: Runtime sizing and shutdown grace match upstream guidance

The module SHALL set a Node heap ceiling suitable for coding-agent workloads (at least 8192 MB) and SHALL allow the container at least 40 seconds to stop so the SQLite WAL checkpoint completes.

#### Scenario: Container stop under write load

- **WHEN** the omniroute container is stopped or restarted
- **THEN** the container runtime allows the upstream-documented stop grace period before signaling kill

### Requirement: Runtime state is app-owned and backed up

All OmniRoute state (SQLite database, keys, logs) SHALL live under the module's `dataDir` (default `/srv/data/omniroute`) as mutable state owned by the application; the declarative config SHALL NOT render or manage runtime configuration files. The data directory SHALL join the host's restic state-backups contract with log output excluded.

#### Scenario: Imperative configuration survives redeploys

- **WHEN** a new generation is deployed to `home-forge`
- **THEN** providers, routing, tunnels, and other dashboard-configured state persist in the data directory unchanged

#### Scenario: Backup contract covers state

- **WHEN** the host's state-backups job runs
- **THEN** the OmniRoute data directory is included and its logs directory is excluded
