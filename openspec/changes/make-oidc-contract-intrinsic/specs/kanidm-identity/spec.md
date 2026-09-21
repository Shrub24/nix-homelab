## RENAMED Requirements

- FROM: `### Requirement: Identity provider and client SHALL consume one canonical provider URL`
- TO: `### Requirement: Identity provider and OIDC contract SHALL consume one canonical provider URL`

## MODIFIED Requirements

### Requirement: Kanidm provisioning SHALL own current OIDC client registration

Current OIDC consumers SHALL be provisioned through `services.kanidm.provision.systems.oauth2.<name>` using repo-owned client metadata and secret-file-backed client secrets.

#### Scenario: Existing app client is provisioned declaratively
- **WHEN** a current OIDC-enabled app such as Termix, Paperless, or Karakeep is configured
- **THEN** Kanidm provisioning declares its client registration, origin/landing metadata, and scope/claim mappings in Nix
- **AND** the client secret is supplied from a runtime secret file rather than inline store content

### Requirement: Kanidm SHALL run a supported version line with a clean upgrade-check gate

The repo SHALL pin Kanidm to the current supported major line (`kanidm_1_11` for the server package and `kanidm_1_11` for the client/system package). The server wrapper and the client tooling SHALL resolve from one release-family value consumed by both the provider and the host-auth capability, so the two cannot drift apart. The upgrade path SHALL be gated on `kanidmd domain upgrade-check` returning PASS from the running server binary before the package pin is bumped.

#### Scenario: Kanidm package is pinned to the supported line
- **WHEN** the flake evaluates `services.kanidm.package` for the identity host
- **THEN** the package resolves to `pkgs.kanidmWithSecretProvisioning_1_11` on the admin host
- **AND** `environment.systemPackages` and the host-auth default resolve to `pkgs.kanidm_1_11`

#### Scenario: The release family moves as one edit

- **WHEN** the Kanidm release is bumped
- **THEN** the server wrapper, the provider's system package, and the host-auth default all change together
- **AND** no second file restates the release independently

### Requirement: Identity provider and OIDC contract SHALL consume one canonical provider URL

The identity provider and the intrinsic OIDC contract SHALL independently consume the canonical Kanidm public URL from resolved web policy. The provider SHALL NOT write configuration into the OIDC contract namespace, and the provider SHALL NOT require the host-auth capability to be selected in order to evaluate.

#### Scenario: Provider and remote client evaluate

- **WHEN** the provider host and a remote OIDC consumer host evaluate
- **THEN** both resolve the same canonical provider URL
- **AND** neither requires the other capability to mutate its option namespace

#### Scenario: Provider evaluates without the host-auth capability

- **WHEN** a host selects identity-provider and does not select kanidm-host-auth
- **THEN** the provider's runtime, provisioning inputs, and OIDC client secret map evaluate successfully
- **AND** `services.identity.hostAuth.enable` remains false
- **AND** no Kanidm client package or unixd integration is installed by the provider alone
