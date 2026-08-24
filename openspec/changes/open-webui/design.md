## Context

`oci-melb-1` already hosts private-origin workloads, the file-driven Bifrost gateway, PostgreSQL, state backups, and notification monitoring. `do-admin-1` provides Kanidm and the policy-driven Caddy edge. The repository has no Open WebUI configuration today.

Open WebUI is available as a `nixos-unstable` NixOS module, while Open Terminal and Open WebUI Computer are upstream OCI/Python ecosystem components without NixOS modules. The design must preserve the fleet's native-service preference, use Bifrost rather than per-application provider credentials, and distinguish hosted agent execution from a user's own computer.

## Goals / Non-Goals

**Goals:**

- Run Open WebUI on `oci-melb-1` as a private-origin, Kanidm-authenticated application with durable, recoverable state.
- Use the existing file-driven Bifrost gateway as the default OpenAI-compatible model connection.
- Provide Open Terminal as the server-side integrated tool and execution environment for a small trusted group.
- Permit an opted-in user to connect their own Open WebUI Computer workspace over Tailscale without making that machine a fleet-managed or shared host.
- Keep baseline configuration, secrets, access policy, runtime pins, backups, and monitoring declarative.

**Non-Goals:**

- Deploy LiteLLM, Ollama, public Computer endpoints, or a separate web SSH product.
- Mount host filesystems, Podman/Docker sockets, SSH credentials, or fleet secrets into Open Terminal.
- Treat Open Terminal's free multi-user mode as a boundary for untrusted tenants.
- Automate Open WebUI Computer enrollment, identity forwarding, or device provisioning beyond upstream-supported flows.
- Add Enterprise Terminals, Kubernetes, Redis, PostgreSQL/pgvector, or multi-worker Open WebUI in the initial release.

## Decisions

### OW-1: Use the native `services.open-webui` module on `oci-melb-1`

Open WebUI SHALL use the `nixos-unstable` NixOS module instead of an application OCI container. A leaf wrapper may add fleet contracts, but it SHALL retain the upstream module as its runtime owner. The host will permit only the `open-webui` unfree package through a narrow `allowUnfreePredicate`.

**Rationale:** The module provides a hardened systemd unit, state ownership, lifecycle, and `environmentFile` support with less runtime machinery than a container.

**Alternatives considered:** A pinned OCI image would follow some existing service modules but duplicates a supported native runtime. Overlaying a newer package is unnecessary while the unstable module remains current enough for the required integration.

### OW-2: Model the workbench as an application composition root

`applications.ai-workbench` SHALL compose the native Open WebUI service with the hosted Open Terminal service, shared connection policy, persistent paths, backup registration, and monitoring. Hosts SHALL explicitly import and enable the application; no blanket module import will be added.

**Rationale:** Open WebUI is the control plane and Open Terminal is its tightly coupled action substrate. Their shared access and state contracts belong in an application layer, while Open Terminal remains an independently configurable leaf service.

**Alternatives considered:** Direct host-level wiring would repeat state, secret, and connection policy. A single monolithic Open WebUI module would obscure Open Terminal's separate security boundary.

### OW-3: Consume Bifrost as the only baseline model-provider boundary

Open WebUI SHALL consume the host-local Bifrost OpenAI-compatible endpoint and repo-declared aliases. Provider credentials and routing SHALL remain in Bifrost's file-driven configuration with `config_store` disabled. Open WebUI will not configure Bifrost providers or become a canonical gateway configuration store.

**Rationale:** This preserves the existing single gateway contract and makes a future gateway replacement an endpoint-level change rather than a per-user credential migration.

**Alternatives considered:** LiteLLM and direct upstream provider connections add duplicate credential, routing, and governance surfaces. Ollama is deferred until a local-model need is demonstrated.

### OW-4: Reuse Kanidm and policy-driven edge ingress

The workbench SHALL have a Kanidm OIDC client with its callback URL derived from the canonical web-service policy. Caddy on `do-admin-1` SHALL be the only cross-host ingress path, with Tailscale-encrypted upstream transport to `oci-melb-1`. The declared route controls whether an additional Cloudflare Access gate is required; the origin service is never directly public.

Open WebUI configuration SHALL set its canonical external URL, enable OIDC signup and group/role synchronization, and keep OAuth configuration environment-authoritative.

**Rationale:** The Paperless and Karakeep patterns already provide an auditable ingress, identity, secret, and host topology.

**Alternatives considered:** A local login bypasses fleet identity. A second proxy or direct public origin duplicates policy and expands attack surface.

### OW-5: Use an immutable baseline configuration plus managed application state

The application SHALL set `ENABLE_PERSISTENT_CONFIG=false` and retain non-persistent OAuth configuration so that Nix/SOPS settings are authoritative. Bifrost connections, terminal connection metadata, and baseline auth settings are rendered from Nix and SOPS.

Chats, uploads, knowledge bases, vectors, workspace records, tools, functions, MCP definitions, and access grants remain Open WebUI state. Fleet-managed model presets SHALL use the supported model synchronization API, never direct database changes.

**Rationale:** It separates reproducible service behavior from user data while retaining supported application APIs for controlled reconciliation.

**Alternatives considered:** UI-managed persistent settings drift from the repository. Direct SQLite edits are unsupported and make restore/migration unsafe.

### OW-6: Host Open Terminal privately with an explicit trusted-team boundary

Open Terminal SHALL run as a digest-pinned Podman OCI service available only to Open WebUI over loopback/private networking. It SHALL use a SOPS-provided API key and an admin-configured `TERMINAL_SERVER_CONNECTIONS` entry, keeping the key out of browsers. Group-based access grants limit terminal availability.

For more than one eligible user, `OPEN_TERMINAL_MULTI_USER=true` SHALL create separate user homes. The service SHALL have bounded CPU, memory, PID, storage, and network access; no privileged mode, runtime socket, host mount, or fleet secret mount is allowed. Its image is the baseline tool contract; runtime package installation is not the reproducible default.

**Rationale:** Upstream integrates Open Terminal directly with Open WebUI and its server-side proxy, while the constrained OCI boundary contains agent execution without pretending it is a tenant-isolation platform.

**Alternatives considered:** Bare-metal Open Terminal would give agents host authority. Warpgate is a separate human SSH/bastion product, not Open WebUI's action substrate. Enterprise Terminals provides per-user containers but adds a license and orchestration control plane that is unjustified for the initial trusted group.

### OW-7: Treat Open WebUI Computer as user-owned and opt-in

Open WebUI Computer SHALL not run as a shared fleet service. A user may run `cptr` on their own Tailscale-reachable machine and expose a selected workspace through its OpenAI-compatible gateway. The baseline onboarding is curated: the user creates a gateway key and an operator registers the connection, then restricts its `cptr/<workspace>` model to the intended user or group.

Open WebUI Direct Connections MAY be documented as an experimental self-service alternative, but it is not a supported fleet baseline because credentials are browser-held and browser-to-device CORS/Tailscale connectivity is required.

**Rationale:** Computer represents real-machine authority and does not forward the hosted Open WebUI identity through its gateway. Explicit opt-in and per-workspace model access prevent accidental shared-host access.

**Alternatives considered:** Hosting Computer centrally contradicts its ownership and single-trust-domain model. A custom device-enrollment service is out of scope.

### OW-8: Start with one local state store and defer scale substrates

Open WebUI SHALL use its local SQLite state on the host's persistent data mount in the initial topology. The service state, uploads, and vector data SHALL be backed up together. PostgreSQL/pgvector and Redis are deferred until demonstrated RAG, concurrency, or replication requirements require them.

**Rationale:** One native instance on local persistent storage is the smallest recoverable operating model for the current ARM host.

**Alternatives considered:** Adding PostgreSQL, pgvector, Redis, and worker coordination immediately would exceed current demand and consume scarce memory.

### OW-9: Integrate existing operational controls

The application SHALL register health checks, Beszel-visible resource monitoring, notification monitoring, state backups, secret-scope validation, and operator documentation. The initial release SHALL measure actual ARM build and runtime memory before enabling optional RAG or large workspace images.

**Rationale:** The workbench is a stateful and agentic service; recovery and resource evidence are required before expanding capability.

## Risks / Trade-offs

- **[R1: ARM build or runtime pressure]** Open WebUI and terminal images are large, and `oci-melb-1` already hosts stateful services. **Mitigation:** build/evaluate the exact `aarch64-linux` target first, pin a slim terminal image, monitor memory, and defer optional RAG substrates.
- **[R2: Unfree package gate]** NixOS evaluation rejects Open WebUI by default. **Mitigation:** permit only the exact package name and validate the host configuration before deployment.
- **[R3: OIDC redirect or claim mismatch]** A wrong external URL or Kanidm group claim can lock out users. **Mitigation:** derive the callback from policy, retain documented break-glass recovery, and test a non-admin group before disabling local login.
- **[R4: Shared-container terminal exposure]** Free multi-user mode does not isolate network namespaces or kernels. **Mitigation:** restrict the initial audience to a trusted group, use resource/network controls, and require Enterprise Terminals before opening access to untrusted users.
- **[R5: Agent exfiltration or host escape]** Terminal tools could access data or runtime privileges beyond intent. **Mitigation:** no host mounts or runtime sockets, private service reachability, minimal image, explicit egress policy, and no provider credentials in the workspace.
- **[R6: Computer identity ambiguity]** A Computer gateway key represents its local owner, not the hosted WebUI user. **Mitigation:** one curated connection per user-owned workspace, model ACLs, Tailscale-only reachability, and no shared Computer instances.
- **[R7: Backup incompleteness]** Backing up only the database loses uploads or vector data. **Mitigation:** back up the full declared state directory and perform a restore drill before relying on user data.

## Migration Plan

1. Add policy, OIDC-client, secret-template, and scope-validation scaffolding without encrypted values.
2. Add the native Open WebUI and private Open Terminal modules, application composition root, image pin, and persistent paths.
3. Bind the application and OIDC client on `oci-melb-1` and `do-admin-1`; have the operator create the encrypted secret values.
4. Add Caddy/web policy, backup, health, monitoring, and documentation wiring.
5. Evaluate and build the exact `aarch64-linux` configuration, then deploy through the existing host workflow.
6. Verify Bifrost model discovery, OIDC login and group grants, constrained terminal execution, backup restore, and a single user-owned Computer pilot.

**Rollback:** Disable the edge route and application enable flag, then remove the Open Terminal container. Preserve `/srv/data/open-webui` and terminal workspace state for recovery until an explicit retention decision is made. Re-enable the previous system generation through deploy-rs/NixOS rollback if activation fails.

## Open Questions

- Which Kanidm group is the initial trusted terminal cohort, and which group owns Open WebUI administration?
- Should the first edge route require Cloudflare Access in addition to Kanidm OIDC, or remain tailnet-only until external use is required?
- What fixed tool profile belongs in the initial terminal image, and what workspace-retention period is appropriate?
- Is curated Computer enrollment sufficient for the first users, or should experimental Direct Connections be enabled after a security review?
