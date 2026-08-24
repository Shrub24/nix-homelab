## Why

The fleet needs a private, multi-user AI workbench that uses the existing Kanidm, Tailscale, Caddy, SOPS, and Bifrost foundations instead of introducing a parallel identity or provider stack. Open WebUI supplies the shared control plane, Open Terminal supplies centrally governed agent execution, and Open WebUI Computer gives individual users an opt-in path to expose their own workspace to the hosted control plane.

**Core Value:** Provide a reproducible, private-first AI workbench whose hosted services and trust boundaries are declared in Nix while keeping each user's personal computer under that user's control.

## What Changes

- Add an `oci-melb-1` Open WebUI service using the `nixos-unstable` NixOS module, persistent service state, scoped secrets, and the existing Bifrost OpenAI-compatible endpoint.
- Add Kanidm OIDC login, synchronized group/role access, and a policy-defined Caddy edge route with private Tailscale upstream transport.
- Add a hosted Open Terminal integration as a constrained, digest-pinned Podman service connected through Open WebUI's server-side terminal connection mechanism.
- Define trusted-team multi-user Open Terminal behavior, per-user workspaces, group-based access, bounded resources, restricted network access, and explicit non-access to host mounts, runtime sockets, and fleet secrets.
- Define an opt-in Open WebUI Computer onboarding and access model for user-owned, Tailscale-reachable workspaces exposed as OpenAI-compatible `cptr/<workspace>` models.
- Register backups, health checks, resource monitoring, notification monitoring, secret-scope validation, and operator documentation for the new workbench.

## Capabilities

### New Capabilities

- `open-webui-service`: Run Open WebUI as a private, OIDC-authenticated, Bifrost-backed NixOS service with recoverable persistent state.
- `hosted-open-terminal`: Provide a centrally hosted, access-controlled Open Terminal execution environment for Open WebUI users.
- `user-owned-computer-connection`: Define secure, opt-in connection of a user's Open WebUI Computer workspace to the hosted Open WebUI instance.

### Modified Capabilities

<!-- None. Existing AI gateway, secrets, network, and edge-ingress contracts already define the boundaries this change consumes. -->

## Impact

- **Affected code:** `hosts/oci-melb-1/`, `hosts/do-admin-1/`, `modules/applications/`, `modules/services/`, `policy/`, `lib/`, `secrets/.templates/`, `.sops.yaml`, `tests/`, and operator documentation under `docs/`.
- **Operational impact:** adds a stateful native NixOS service and a private OCI execution service on the ARM origin host; the Open WebUI package is unfree and must be permitted narrowly.
- **Security impact:** OIDC and group grants govern hosted use; Open Terminal is a bounded trusted-team environment rather than a host shell; Open WebUI Computer remains user-owned, Tailscale-only, and SSH-equivalent in authority.
- **Risk boundary:** do not add LiteLLM, Ollama, public Computer endpoints, Docker/Podman socket access, host mounts, or enterprise Terminals orchestration in this change. Per-user container orchestration remains a later decision if the trusted-team boundary changes.
