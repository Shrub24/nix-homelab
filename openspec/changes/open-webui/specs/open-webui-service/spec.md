## ADDED Requirements

### Requirement: Open WebUI SHALL be a native private-origin NixOS service
The system SHALL run Open WebUI on `oci-melb-1` through the `nixos-unstable` `services.open-webui` module. Its unfree-package permission SHALL be narrowly scoped, and its mutable state SHALL reside on the declared persistent service-data mount rather than an anonymous runtime location.

#### Scenario: Host configuration is evaluated
- **WHEN** the `oci-melb-1` configuration enables the AI workbench
- **THEN** evaluation permits only the required Open WebUI unfree package
- **AND** the rendered service has an explicit persistent state location

#### Scenario: Origin service is reachable
- **WHEN** the application starts successfully
- **THEN** Open WebUI is reachable only through declared local or Tailscale-origin paths
- **AND** its application port is not directly exposed as a public origin service

### Requirement: Open WebUI SHALL use the canonical Bifrost gateway
The system SHALL configure Open WebUI with the existing host-local Bifrost OpenAI-compatible endpoint and repo-declared model aliases. Provider routing and upstream provider credentials SHALL remain owned by Bifrost's file-driven configuration.

#### Scenario: A user selects a baseline model
- **WHEN** Open WebUI requests a configured text, image, embedding, or fallback model
- **THEN** it sends the request to Bifrost's OpenAI-compatible endpoint
- **AND** it does not require a per-application upstream provider credential

### Requirement: Open WebUI authentication SHALL use Kanidm OIDC
The system SHALL register an Open WebUI OIDC client through the canonical identity policy and configure the application with its canonical external URL, callback URL, and Kanidm group/role claim handling. OAuth baseline configuration SHALL remain environment-authoritative.

#### Scenario: An authorized user signs in
- **WHEN** a user reaches the declared Open WebUI URL
- **THEN** the application redirects the user through the registered Kanidm OIDC flow
- **AND** the returned identity and configured claims determine the user's Open WebUI access

#### Scenario: Edge ingress forwards an authenticated request
- **WHEN** Caddy proxies an Open WebUI request from `do-admin-1`
- **THEN** it uses the declared policy route and Tailscale-encrypted origin transport
- **AND** the origin URL and OIDC callback match the canonical external URL

### Requirement: Open WebUI baseline configuration and state SHALL be recoverable
The system SHALL render baseline Open WebUI configuration and secrets from Nix and SOPS without permitting persistent UI configuration to override them. It SHALL back up the full declared application state and register health and failure monitoring.

#### Scenario: The application is restarted after an administrator changes UI settings
- **WHEN** a setting owned by the declarative baseline is changed through the UI
- **THEN** the declared configuration remains authoritative after restart
- **AND** user-generated chats, uploads, knowledge data, and vector state remain in the declared persistent state path

#### Scenario: State recovery is required
- **WHEN** the application state must be restored
- **THEN** the backup set contains the database, uploads, and vector data together
- **AND** health and service failure signals use the fleet's monitoring and notification path
