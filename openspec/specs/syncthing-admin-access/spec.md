# syncthing-admin-access Specification

## Purpose
Define browser access to each host's Syncthing administrative interface: host-specific subpaths under one shared admin hostname, with the proxy preserving the subpath and keeping the interface private-only.
## Requirements
### Requirement: Syncthing admin browser access SHALL support host-specific subpaths
The repository SHALL support per-host Syncthing browser entrypoints under a shared admin hostname using explicit path-based route declarations.

#### Scenario: A host Syncthing route is resolved
- **WHEN** the canonical web policy for an eligible host is resolved
- **THEN** the host can declare a Syncthing admin route under the shared `syncthing` hostname with a host-specific path such as `/oci-melb-1/`
- **AND** the resolved public URL preserves that host-specific subpath

### Requirement: Syncthing admin proxying SHALL preserve private-only GUI exposure
Syncthing browser access SHALL be delivered through reverse-proxy routing without requiring the host Syncthing GUI to be publicly exposed beyond the fleet's private-origin posture.

#### Scenario: Syncthing GUI remains private-origin reachable
- **WHEN** a Syncthing admin route is rendered for a host
- **THEN** the upstream target may remain a host-private address such as `127.0.0.1:8384`, `0.0.0.0:8384`, or a tailnet-reachable host interface
- **AND** the requirement does not force the Syncthing GUI to be exposed through direct public ingress

### Requirement: Syncthing admin subpaths SHALL work with reverse-proxy prefix handling
The Syncthing admin route model SHALL support reverse-proxy path-prefix handling compatible with Syncthing’s documented subpath hosting pattern.

#### Scenario: A path-based Syncthing route is rendered
- **WHEN** the ingress route for a host Syncthing UI uses a non-root path
- **THEN** proxy behavior strips or otherwise handles the declared prefix so the upstream Syncthing UI remains reachable
- **AND** redirects and API/UI requests continue to function through the declared route

