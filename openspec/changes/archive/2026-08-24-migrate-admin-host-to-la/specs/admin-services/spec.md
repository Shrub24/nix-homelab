## RENAMED Requirements

- FROM: `do-admin-1 local Cockpit upstream SHALL use explicit trusted loopback TLS`
- TO: `la-admin-1 local Cockpit upstream SHALL use explicit trusted loopback TLS`

## MODIFIED Requirements

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

### Requirement: Gatus endpoint inventory SHALL derive from web services policy
Admin monitoring wiring SHALL derive Gatus endpoint inventory for a host from resolved service entries in `policy/web-services.nix` via policy resolution helpers, using policy-defined origin and health metadata.

#### Scenario: Gatus endpoint generation runs for do-admin-1
- **WHEN** admin monitoring configuration is rendered for `do-admin-1`
- **THEN** Gatus endpoints are generated from resolved host services in `policy/web-services.nix`
- **AND** endpoint URLs use resolved origin values plus service health path metadata

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

### Requirement: Homepage authenticated widget wiring SHALL use caller-owned machine-auth inputs
Homepage widgets that require authentication SHALL consume caller-owned machine-auth inputs provided through Homepage runtime environment templating, while preserving Homepage presentation ownership.

#### Scenario: Homepage widget config is rendered for authenticated integrations
- **WHEN** Homepage services are assembled for `la-admin-1`
- **THEN** authenticated widgets use Homepage runtime variables sourced from host-scoped secrets/templates
- **AND** Homepage layout/icons/grouping/bookmarks remain owned by Homepage service files

### Requirement: Homepage-Gatus local API path SHALL be unauthenticated and loopback-only
Homepage integration for Gatus SHALL use a local unauthenticated API path, and Gatus SHALL be explicitly bound to loopback so that this unauthenticated API surface is not exposed beyond the local host.

#### Scenario: Homepage retrieves Gatus data over local API
- **WHEN** Homepage Gatus widget/integration is configured on `la-admin-1`
- **THEN** Homepage requests use local API access without bearer/basic/OIDC credentials
- **AND** Gatus web listener is explicitly configured with loopback bind (`127.0.0.1`)

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

### Requirement: la-admin-1 local Cockpit upstream SHALL use explicit trusted loopback TLS
The `la-admin-1` Cockpit public subpath SHALL proxy to the local Cockpit listener over HTTPS using a host-local CA and explicit upstream trust, without steady-state `tls_insecure_skip_verify`.

#### Scenario: la-admin-1 local Cockpit upstream is rendered
- **WHEN** the `cockpit-la-admin-1` route is evaluated
- **THEN** the upstream uses HTTPS to the local Cockpit listener
- **AND** Caddy trusts a declaratively generated local CA for that hop
- **AND** insecure upstream TLS verification bypass is not required in steady state

## ADDED Requirements

### Requirement: Local-admin Cockpit path SHALL identify the LA host
The local-admin Cockpit route SHALL use `/la-admin-1` as its deliberate public path and SHALL use a host-neutral internal policy key.

#### Scenario: Local-admin Cockpit route is resolved
- **WHEN** LA admin Cockpit policy is rendered
- **THEN** the public path is `/la-admin-1`
- **AND** the internal route key does not contain `do-admin-1`
