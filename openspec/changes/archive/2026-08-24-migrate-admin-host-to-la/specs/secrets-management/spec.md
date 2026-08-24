## ADDED Requirements

### Requirement: LA host recipients SHALL derive from a verified persistent SSH host key
The LA age recipient SHALL be derived from the live LA SSH ed25519 host key only after its fingerprint is verified through the provider console, and the host key SHALL remain persistent for the lifetime of ciphertext encrypted to that recipient.

#### Scenario: Operator derives the LA recipient
- **WHEN** the operator adds `&la_admin_1_age` to recipient policy
- **THEN** the scanned public key fingerprint matches the provider-console fingerprint
- **AND** no separately managed age private key is created

### Requirement: LA outbound identity SHALL remain distinct from host decryption identity
The LA `dev` outbound SSH private key SHALL live only in its host-scoped encrypted system secret, and its public key SHALL be declared once in the central fleet SSH trust set.

#### Scenario: LA connects to a fleet peer
- **WHEN** LA `dev` initiates a fleet SSH connection after migration
- **THEN** it uses the LA host-scoped outbound identity
- **AND** peer authorization is derived from the central trust set

### Requirement: Replacement-host secret migration SHALL preserve least privilege
When a host role moves to a replacement host, encrypted secret reader sets SHALL add only the replacement recipient required by enabled features, retain the source recipient only for the rollback window, and remove it after source retirement.

#### Scenario: LA receives moving admin and identity scopes
- **WHEN** `la-admin-1` enables the admin, edge, and Kanidm roles
- **THEN** its recipient is granted access to only the required application, identity, service, host-system, and explicit cross-host OIDC scopes
- **AND** the DigitalOcean recipient remains only until the declared decommission gate

#### Scenario: Source host is retired
- **WHEN** DigitalOcean rollback material is no longer required
- **THEN** the source host recipient is removed from migrated secret rules
- **AND** affected encrypted files are re-encrypted by the operator

## MODIFIED Requirements

### Requirement: Termix OIDC env template SHALL consume provider-owned endpoint outputs
The Termix OIDC environment template for `la-admin-1` SHALL source OIDC endpoint values from canonical identity-provider `oidc.*` outputs rather than independently constructing endpoint URIs.

#### Scenario: Termix OIDC env is rendered from SSOT
- **WHEN** `la-admin-1` termix-oidc.env template is evaluated
- **THEN** `OIDC_ISSUER_URL`, `OIDC_AUTHORIZATION_URL`, `OIDC_TOKEN_URL`, and `OIDC_USERINFO_URL` are resolved from canonical identity-provider module outputs
- **AND** no local URL derivation from a raw provider base URL is used

### Requirement: Backup repository credentials SHALL remain host-scoped
Backup access keys, secret keys, and restic repository passwords SHALL be stored in host-scoped encrypted secret material and SHALL NOT be promoted to shared application or common secret scopes by default.

#### Scenario: Host backup secrets are reviewed
- **WHEN** backup secret definitions for `la-admin-1` and `oci-melb-1` are inspected
- **THEN** each host uses its own encrypted backup credentials and repository password material
- **AND** unrelated hosts do not gain decryption access implicitly
