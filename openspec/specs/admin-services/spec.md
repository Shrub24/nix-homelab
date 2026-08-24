# Spec: Admin Services

## Purpose

Define private administrative access contracts for hosts, including Tailscale SSH, Termix access, and break-glass recovery.

## Requirements

### Requirement: Admin access remains private and Tailscale-first
Administrative access SHALL remain private and Tailscale-first by default, while allowing explicit Cloudflare Access-gated web ingress at the public edge bastion with private-origin upstream transport for approved admin routes.

#### Scenario: Admin network posture is evaluated
- **WHEN** admin service and firewall config are inspected
- **THEN** access paths are private by default, and any declared admin web routes are Cloudflare Access-gated at the edge and constrained to private-origin upstream transport

#### Scenario: Public ingress is enabled for non-admin services
- **WHEN** mixed exposure policy is configured
- **THEN** admin endpoints remain private-first and Cloudflare Access-gated with private-origin upstream transport unless explicitly changed

### Requirement: Termix is exposed through controlled service wiring
Termix SHALL run under declared service wiring and SHALL be exposed through controlled route composition, using private-origin transport for cross-host paths and localhost-only direct upstream when edge-local.

#### Scenario: Termix service stack starts
- **WHEN** admin application is enabled
- **THEN** dependent units and runtime paths are configured for Termix availability

#### Scenario: Caddy ingress route map is generated
- **WHEN** public and private service routes are composed
- **THEN** admin route policy remains explicitly declared and constrained by edge access controls

### Requirement: Declarative SSH key ownership is enforced
SSH access for administrative users SHALL be sourced from declarative key configuration.

#### Scenario: User/key configuration is rendered
- **WHEN** user modules are evaluated
- **THEN** required admin users receive declared authorized keys

### Requirement: Break-glass recovery path exists
Provider-appropriate break-glass recovery SHALL be documented and operationally available.

#### Scenario: Remote admin path fails
- **WHEN** Tailscale/SSH access is unavailable
- **THEN** documented recovery procedures can be used to regain control

### Requirement: Admin application SHALL enable native admin operations services
`applications.admin` composition SHALL wire Cockpit, Webhook, Ntfy, Gatus, Vaultwarden, Quantum, Homepage Dashboard, Beszel hub, Kanidm, and Termix through service-level admin modules under `modules/services/admin/`, while keeping tightly coupled portable access and identity composition in the reusable `modules/applications/admin/` module rather than host-local assembly or redundant split glue files.

#### Scenario: Admin profile enables expanded baseline service set
- **WHEN** a host imports and enables the admin application profile
- **THEN** the host configuration includes `services.cockpit.enable`, `services.webhook.enable`, `services.ntfy-sh.enable`, `services.gatus.enable`, `services.vaultwarden.enable`, `services.homepage-dashboard.enable`, and `services.beszel.hub.enable`
- **AND** Kanidm service wiring is enabled through `services.admin.kanidm`
- **AND** Quantum service wiring is enabled through `services.admin.quantum`
- **AND** Termix service wiring is enabled through `services.admin.termix`
- **AND** service-owned wiring resides in admin service modules rather than generic-service wrapper indirection
- **AND** portable access and identity composition remains owned by `applications.admin`

### Requirement: Admin service state SHALL use predictable data root mapping
For each newly wired admin service that supports configurable state/data paths, the admin profile SHALL map that state under `applications.admin.dataRoot` using a per-service subdirectory, with mapping owned by corresponding service-level admin modules.

#### Scenario: Service state directories are derived from admin data root
- **WHEN** `applications.admin.dataRoot` is set (for example `/srv/data`)
- **THEN** supported service state paths resolve under `${applications.admin.dataRoot}/<service>` rather than implicit unmanaged defaults

### Requirement: Admin expansion SHALL preserve private-first exposure defaults
The admin profile augmentation SHALL NOT introduce public-ingress defaults for Cockpit, Webhook, Ntfy, Gatus, Vaultwarden, Quantum, Homepage Dashboard, or Beszel and SHALL remain compatible with the existing Tailscale-first access model after module decomposition.

#### Scenario: No public-ingress baseline is introduced
- **WHEN** the admin module refactor is evaluated
- **THEN** no requirement for public internet exposure is added and service wiring remains consistent with private management access patterns

### Requirement: Admin baseline SHALL provide central visibility without host log replication
This stage SHALL provide centralized operational visibility using Cockpit and Beszel surfaced in Homepage, while deferring cross-host L1 log replication to a later dedicated logging change, including after service/module decomposition.

#### Scenario: Visibility baseline is available while log sync is deferred
- **WHEN** the admin module refactor is deployed
- **THEN** Cockpit, Beszel hub, and Homepage remain enabled for central operations visibility
- **AND** no requirement is introduced that hosts must run journald remote/upload replication in this stage

### Requirement: Admin app auth SHALL support Pocket ID OIDC for phase-1 supported services
The admin baseline SHALL support app-native OIDC using Kanidm as shared issuer for the phase-1 app set (`gatus`, `beszel`, `termix`, `quantum`) while keeping explicit exceptions for services that are not in scope for this auth wave and deferring unixd/PAM/SSH host login rollout until after OIDC parity.

#### Scenario: Phase-1 supported apps are OIDC-enabled
- **WHEN** the admin baseline is rendered for `la-admin-1`
- **THEN** `gatus`, `beszel`, `termix`, and `quantum` include app-level OIDC wiring using Kanidm issuer endpoints and scoped credentials

#### Scenario: Cloudflare Access upstream IdP is Kanidm
- **WHEN** Cloudflare Access configuration is evaluated for admin browser routes
- **THEN** Access uses Kanidm generic OIDC as upstream IdP rather than Google OAuth or Pocket ID

#### Scenario: Explicit exceptions remain outside phase-1 app OIDC rollout
- **WHEN** exception services are evaluated in this change scope
- **THEN** `vaultwarden`, `navidrome`, `syncthing`, `webhook`, `ntfy`, `cockpit`, and `homepage` are not required to implement app-native OIDC in this phase
- **AND** exception rationale remains documented in change artifacts

### Requirement: Admin secrets SHALL remain host-scoped for OIDC client credentials
Kanidm OIDC app credentials used by admin services SHALL be defined in explicit scoped secret files and SHALL NOT be promoted to unrelated shared secret scope by default.

#### Scenario: OIDC credentials are added for admin apps
- **WHEN** OIDC client credentials are declared for phase-1 apps
- **THEN** they are sourced from explicit scoped secret files/templates for the consuming services
- **AND** they are not introduced under unrelated shared/common secret scope by default

### Requirement: Cockpit runtime SHALL include the ws-user dependency workaround
Cockpit service wiring SHALL include the upstream `cockpit-ws-user.service` dependency workaround required to avoid the known shutdown-ordering regression.

#### Scenario: Cockpit runtime is rendered
- **WHEN** Cockpit service wiring is evaluated
- **THEN** `cockpit-ws-user.service` has the required dependency override applied
- **AND** the workaround remains part of the declarative Cockpit service baseline rather than host-local ad hoc patching

### Requirement: Gatus endpoint inventory SHALL derive from web services policy
Admin monitoring wiring SHALL derive Gatus endpoint inventory for a host from resolved service entries in `policy/web-services.nix` via policy resolution helpers, using policy-defined origin and health metadata.

#### Scenario: Gatus endpoint generation runs for la-admin-1
- **WHEN** admin monitoring configuration is rendered for `la-admin-1`
- **THEN** Gatus endpoints are generated from resolved host services in `policy/web-services.nix`
- **AND** endpoint URLs use resolved origin values plus service health path metadata

#### Scenario: Health defaults are applied consistently
- **WHEN** service entries omit explicit health status/path overrides
- **THEN** generated Gatus checks apply policy defaults for health path and expected status

#### Scenario: Generated checks use canonical route path and origin port metadata
- **WHEN** gatus endpoints are rendered
- **THEN** route path and origin port values are sourced from canonical policy/resolved policy outputs
- **AND** those values are not redefined in independent gatus-specific literals

### Requirement: Homepage metadata SHALL remain presentation-owned
Homepage layout/services/bookmarks metadata SHALL remain owned by Homepage service files and SHALL NOT require encoding presentation concerns in `policy/web-services.nix`.

#### Scenario: Homepage config is evaluated
- **WHEN** homepage content is assembled
- **THEN** icons, descriptions, grouping, widget wiring, and bookmarks are sourced from homepage-owned files
- **AND** route policy remains focused on routing/access/health metadata

### Requirement: Homepage authenticated widget wiring SHALL use caller-owned machine-auth inputs
Homepage widgets that require authentication SHALL consume caller-owned machine-auth inputs provided through Homepage runtime environment templating, while preserving Homepage presentation ownership.

#### Scenario: Homepage widget config is rendered for authenticated integrations
- **WHEN** Homepage services are assembled for `la-admin-1`
- **THEN** authenticated widgets use Homepage runtime variables sourced from host-scoped secrets/templates
- **AND** Homepage layout/icons/grouping/bookmarks remain owned by Homepage service files

### Requirement: Homepage runtime SHALL support environment-file secret injection
Admin Homepage service wiring SHALL support injecting integration credentials using homepage-dashboard environment file configuration derived from host-scoped SOPS templates.

#### Scenario: Homepage service starts with integration credentials
- **WHEN** `services.homepage-dashboard` is configured for authenticated widgets
- **THEN** runtime environment files include the generated Homepage secret template path
- **AND** missing required template inputs fail through declarative assertions before runtime drift

### Requirement: Beszel Homepage integration SHALL use dedicated read-only account credentials
Homepage integration with Beszel SHALL use a dedicated read-only account distinct from human admin identities, with system visibility scoped to explicitly shared systems.

#### Scenario: Beszel widget credentials are configured
- **WHEN** Beszel widget auth is enabled for Homepage
- **THEN** credentials reference a dedicated read-only Beszel account
- **AND** account scope is limited to explicitly shared systems rather than global full-access sharing

### Requirement: Homepage auth exceptions SHALL remain explicit and minimal
Homepage integrations that run without app credentials SHALL be explicit exceptions and SHALL remain constrained to approved low-risk/local-only operational contexts.

#### Scenario: Caddy widget exception is evaluated
- **WHEN** Homepage includes Caddy operational widget data
- **THEN** no new broad machine credential is required for that widget
- **AND** exception rationale remains documented in change artifacts

### Requirement: Homepage-Gatus local API path SHALL be unauthenticated and loopback-only
Homepage integration for Gatus SHALL use a local unauthenticated API path, and Gatus SHALL be explicitly bound to loopback so that this unauthenticated API surface is not exposed beyond the local host.

#### Scenario: Homepage retrieves Gatus data over local API
- **WHEN** Homepage Gatus widget/integration is configured on `la-admin-1`
- **THEN** Homepage requests use local API access without bearer/basic/OIDC credentials
- **AND** Gatus web listener is explicitly configured with loopback bind (`127.0.0.1`)

### Requirement: Human Gatus access SHALL be edge-gated rather than app-OIDC-gated
Human browser access to Gatus SHALL rely on edge access controls (Cloudflare Access) and SHALL NOT require app-native OIDC wiring in Gatus for this wave.

#### Scenario: Browser user opens Gatus public route
- **WHEN** a user accesses `gatus.shrublab.xyz`
- **THEN** edge access controls enforce browser authentication
- **AND** Gatus app configuration does not require local OIDC client credentials for this flow

### Requirement: Quantum Homepage widget auth SHALL remain out of scope in this wave
This change SHALL NOT require Quantum widget machine-auth wiring.

#### Scenario: Auth coverage is reviewed for current wave
- **WHEN** implementation scope is validated
- **THEN** Quantum widget auth wiring is excluded from required deliverables
- **AND** no Quantum-specific Homepage credential contract is introduced in this change

### Requirement: Quantum SHALL replace Filebrowser for admin file management
The admin baseline SHALL expose Quantum as the file-management UI in place of Filebrowser, with local and remote host data sources configured declaratively.

#### Scenario: Quantum replaces the legacy file-management service
- **WHEN** the admin baseline is evaluated for `la-admin-1`
- **THEN** Filebrowser-specific admin wiring is absent
- **AND** Quantum is provided through `services.admin.quantum`
- **AND** Quantum state is mapped under `${applications.admin.dataRoot}/quantum`

### Requirement: Quantum SHALL support host-local and remote data sources
Quantum on `la-admin-1` SHALL expose a local source for that host and remote sources for approved hosts using the declared transport model for each source.

#### Scenario: Quantum source topology is rendered
- **WHEN** `la-admin-1` admin services are evaluated
- **THEN** Quantum exposes a host-local source for `la-admin-1`
- **AND** approved remote sources remain explicitly declared rather than discovered implicitly

### Requirement: Quantum auth SHALL support Pocket ID OIDC with controlled fallback
Quantum SHALL support Kanidm OIDC and MAY retain local password fallback only where the host configuration still chooses to keep that fallback enabled.

#### Scenario: Quantum auth posture is evaluated
- **WHEN** Quantum auth configuration is rendered
- **THEN** Kanidm OIDC wiring is present
- **AND** any local password fallback remains an explicit host-owned choice rather than an implicit default for all environments

### Requirement: Cockpit SHALL use per-host sessions instead of login-page chaining
Cockpit access SHALL be exposed as separate per-host sessions rather than relying on the login-page `Connect to:` chaining model.

#### Scenario: Operator opens Cockpit from the admin surface
- **WHEN** Cockpit entrypoints are presented to operators
- **THEN** `la-admin-1` and `oci-melb-1` are exposed as separate entrypoints

### Requirement: Vaultwarden SHALL expose a production-oriented mail-capable baseline
Vaultwarden service wiring on `la-admin-1` SHALL define a production-oriented baseline including resolved public domain settings, invite-only account posture, SMTP delivery settings, push capability, and explicit security tuning.

#### Scenario: Vaultwarden admin service is evaluated
- **WHEN** `applications.admin` enables Vaultwarden for `la-admin-1`
- **THEN** Vaultwarden config includes resolved public URL/domain inputs and reverse-proxy-aware headers
- **AND** signup posture defaults to invite-only operation rather than open self-service registration
- **AND** push and operational security settings are declared in the service baseline

### Requirement: Vaultwarden SMTP secrets SHALL be host-scoped and template-rendered
Vaultwarden SMTP and admin runtime secrets for `la-admin-1` SHALL be rendered from host-scoped SOPS secrets into a service-owned environment file.

#### Scenario: Vaultwarden secret template is rendered
- **WHEN** the host secret configuration for `la-admin-1` is evaluated
- **THEN** Vaultwarden admin token, SMTP credentials, and push credentials are sourced from host-scoped secrets
- **AND** the generated environment file is owned and permissioned for the Vaultwarden service only
- **AND** `LoginTo` remains disabled for the shared public Cockpit surface

### Requirement: Cockpit transport ownership SHALL stay module-centered
Cockpit-specific loopback TLS generation, trusted upstream configuration, and Tailscale Serve exposure SHALL remain owned by Cockpit modules, while host overlays only declare host-specific values such as URL root, public host, and local service-user secrets.

#### Scenario: Cockpit configuration ownership is reviewed
- **WHEN** host overlays and reusable modules are inspected
- **THEN** Cockpit transport behavior is defined in Cockpit-owned modules
- **AND** host overlays contain only host-specific Cockpit inputs

### Requirement: la-admin-1 local Cockpit upstream SHALL use explicit trusted loopback TLS
The `la-admin-1` Cockpit public subpath SHALL proxy to the local Cockpit listener over HTTPS using a host-local CA and explicit upstream trust, without steady-state `tls_insecure_skip_verify`.

#### Scenario: la-admin-1 local Cockpit upstream is rendered
- **WHEN** the `cockpit-la-admin-1` route is evaluated
- **THEN** the upstream uses HTTPS to the local Cockpit listener
- **AND** Caddy trusts a declaratively generated local CA for that hop
- **AND** insecure upstream TLS verification bypass is not required in steady state

### Requirement: oci-melb-1 Cockpit SHALL be exposed through host-local Tailscale Serve HTTPS
The `oci-melb-1` Cockpit entrypoint SHALL use host-local Tailscale Serve HTTPS as the upstream exposure mechanism rather than direct cross-host socket binding.

#### Scenario: OCI Cockpit route is evaluated
- **WHEN** the `cockpit-oci-melb-1` route is resolved
- **THEN** its upstream targets the OCI host over Tailscale Serve HTTPS
- **AND** the OCI host keeps Cockpit socket ownership local to the host itself

### Requirement: Admin export-first services SHALL define app-native backup behavior
Stateful admin services that require application-aware recovery, including Kanidm and Vaultwarden, SHALL participate in the backup architecture with export-first behavior and initial raw-state capture.

#### Scenario: Admin backup contract is reviewed for identity and password services
- **WHEN** backup behavior is inspected for Kanidm or Vaultwarden
- **THEN** each service defines or consumes export-first backup behavior
- **AND** Kanidm may satisfy that contract with its upstream automatic backup artifact while the initial backup payload still includes generated recovery artifacts and raw service state

### Requirement: Syncthing admin browser access MAY use shared-host subpath entrypoints
Syncthing administrative browser access SHALL remain private-first and MAY be exposed through shared-host subpath entrypoints rather than only root-host or tunnel-based access.

#### Scenario: Operator opens Syncthing admin UI for a host
- **WHEN** a host has a declared Syncthing admin browser route
- **THEN** the operator can reach the host’s Syncthing UI through the canonical admin URL for that host-specific subpath
- **AND** the access path remains compatible with existing private-origin and admin access controls

### Requirement: Local-admin Cockpit path SHALL identify the LA host
The local-admin Cockpit route SHALL use `/la-admin-1` as its deliberate public path and SHALL use a host-neutral internal policy key.

#### Scenario: Local-admin Cockpit route is resolved
- **WHEN** LA admin Cockpit policy is rendered
- **THEN** the public path is `/la-admin-1`
- **AND** the internal route key does not contain `la-admin-1`
