# kanidm-identity Specification

## Purpose
TBD - created by archiving change kanidm-identity-migration. Update Purpose after archive.

## Requirements

### Requirement: Kanidm SHALL be the canonical declarative identity provider
The repository SHALL provide Kanidm as the canonical repo-owned identity provider using the native nixpkgs Kanidm service surface, with server bootstrap and provisioning owned declaratively in Nix rather than by post-deploy web UI state.

#### Scenario: Kanidm server is enabled on the identity host
- **WHEN** the designated identity/admin host enables the Kanidm service
- **THEN** native `services.kanidm.server` wiring is used for runtime configuration
- **AND** bootstrap and identity-management provisioning are declared from repository state

### Requirement: Kanidm provisioning SHALL own current OIDC client registration
Current OIDC consumers SHALL be provisioned through `services.kanidm.provision.systems.oauth2.<name>` using repo-owned client metadata and secret-file-backed client secrets.

#### Scenario: Existing app client is provisioned declaratively
- **WHEN** a current OIDC-enabled app such as Termix, Quantum, or Karakeep is configured
- **THEN** Kanidm provisioning declares its client registration, origin/landing metadata, and scope/claim mappings in Nix
- **AND** the client secret is supplied from a runtime secret file rather than inline store content

### Requirement: Kanidm bootstrap/admin secrets SHALL use identity-scoped runtime files
Kanidm bootstrap/admin credentials SHALL be sourced from identity-scoped SOPS-managed secret paths and rendered to runtime files for provisioning inputs.

#### Scenario: Kanidm provisioning credentials are evaluated
- **WHEN** Kanidm provisioning is enabled
- **THEN** `adminPasswordFile` and `idmAdminPasswordFile` resolve to runtime secret files sourced from identity-scoped encrypted inputs
- **AND** those values are not embedded directly in committed Nix content

### Requirement: Kanidm provisioning SHALL merge committed topology with encrypted authoritative identity state
Kanidm provisioning SHALL keep non-sensitive identity topology and OIDC scope structure in committed JSON policy and SHALL source sensitive person metadata plus authoritative memberships from an encrypted whole-file JSON overlay that follows Kanidm provisioning structure.

#### Scenario: Identity topology remains reviewable without committed real-user metadata
- **WHEN** the identity policy source is reviewed in repo
- **THEN** it contains only non-sensitive topology such as Kanidm-shaped `systems.oauth2` mappings and structural access relationships
- **AND** usernames, display names, legal names, email addresses, and real-user membership data are absent from committed cleartext policy

#### Scenario: Encrypted authoritative identity state is merged into Kanidm provisioning
- **WHEN** Kanidm provisioning evaluates person data for the identity host
- **THEN** sensitive person/account metadata and authoritative group memberships are sourced from an encrypted whole-file JSON input
- **AND** that overlay is merged through `services.kanidm.provision.extraJsonFile`
- **AND** the resulting provisioning data still resolves to valid Kanidm `groups` and `persons` structures

### Requirement: Kanidm SHALL run a supported version line with a clean upgrade-check gate
The repo SHALL pin Kanidm to the current supported major line (`kanidm_1_11` for the server package and `kanidm_1_11` for the client/system package). The upgrade path SHALL be gated on `kanidmd domain upgrade-check` returning PASS from the running server binary before the package pin is bumped.

#### Scenario: Kanidm package is pinned to the supported line
- **WHEN** the flake evaluates `services.kanidm.package` for the identity host
- **THEN** the package resolves to `pkgs.kanidmWithSecretProvisioning_1_11` on the admin host
- **AND** `environment.systemPackages` and the host-auth default resolve to `pkgs.kanidm_1_11`

### Requirement: Kanidm offline restore verification SHALL be fail-closed with no acceptance path
The `kanidm-restore@` helper SHALL treat every nonzero offline verification result as fatal before ownership repair or service start, with no version-pinned exception predicate, no `db-scan` proof acceptance path, and no acceptance of `RefintNotUpheld` findings. Clean acceptance SHALL require exit zero, the clean-success marker, and zero error-bearing output.

#### Scenario: A nonzero offline verification result is fatal
- **WHEN** `database verify` exits nonzero during a stopped-service restore
- **THEN** the helper refuses to repair ownership or start the service
- **AND** the failure output is surfaced to the operator
- **AND** no version, finding-id, or `db-scan` proof can downgrade the failure

#### Scenario: The clean verification path is unchanged
- **WHEN** `database verify` exits zero with `Verification passed` and no error-bearing output
- **THEN** the helper proceeds to ownership repair and prints the manual-start message

### Requirement: Identity-host migration SHALL preserve the canonical Kanidm state
When the designated Kanidm host is replaced, the replacement SHALL restore the canonical identity state and retain the existing declarative OIDC client topology and encrypted client credentials before it receives public identity traffic.

#### Scenario: LA becomes the identity host
- **WHEN** `la-admin-1` is prepared to replace the existing Kanidm host
- **THEN** Kanidm backup recovery and OIDC client validation complete before the Cloudflare origin endpoint changes
- **AND** existing consumer callback URLs and client secrets remain valid through the transition

### Requirement: Kanidm replacement SHALL restore portable state before service authority
The replacement SHALL use the version-matched Kanidm portable backup export as the authoritative restore input. A source-controlled helper SHALL restore and verify the export while `kanidm.service` is stopped; only then may the service start and reconcile its unchanged declarative provisioning inputs. The helper SHALL treat every nonzero offline verification result as fatal before ownership repair or service start, with the verifier's output surfaced for diagnosis. It SHALL otherwise accept a verification only when it exits zero, carries its clean-success marker, and reports no error-bearing output. Routine non-error startup and reindex diagnostics MAY be present only on that clean path, but inconsistent clean output and temporary verifier-output leakage SHALL remain fatal defects.

#### Scenario: LA restores Kanidm before first start
- **WHEN** LA receives a staged or final Kanidm backup artifact
- **THEN** its stopped restore helper performs offline restore and verification
- **AND** any nonzero or error-bearing verification result remains fatal before ownership repair or service start
- **AND** the service does not create or provision a fresh authoritative database before that restore

### Requirement: Kanidm target readiness SHALL be independent of the public edge

Before public cutover, Kanidm provisioning and its startup readiness check SHALL connect to the local loopback server endpoint using the upstream `https://localhost:<bind-port>` default. The target SHALL NOT require Cloudflare DNS, Authenticated Origin Pull client credentials, or a public-edge TLS route to start and reconcile restored declarative inputs.

#### Scenario: LA starts after private restore before DNS cutover

- **WHEN** the restored LA Kanidm service starts while public DNS still resolves to DO
- **THEN** local provision readiness reaches LA's loopback Kanidm listener without contacting the public route
