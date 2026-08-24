## ADDED Requirements

### Requirement: Open Terminal SHALL be a server-side Open WebUI integration
The system SHALL run Open Terminal as a digest-pinned OCI service reachable only through private local networking. Open WebUI SHALL use an administrator-configured terminal connection that keeps the Open Terminal API key on the server.

#### Scenario: An eligible user opens a terminal-enabled chat
- **WHEN** an authorized user selects the hosted terminal in Open WebUI
- **THEN** Open WebUI proxies terminal requests to the private Open Terminal service
- **AND** the browser does not receive the terminal API key

### Requirement: Hosted terminal access SHALL be group-governed
The system SHALL restrict the hosted terminal connection to declared Open WebUI users or Kanidm-synchronized groups. A multi-user terminal connection SHALL enable Open Terminal's per-user workspace mode.

#### Scenario: A user lacks terminal permission
- **WHEN** a user outside the terminal access grant opens Open WebUI
- **THEN** the hosted terminal connection is unavailable to that user
- **AND** the user cannot invoke terminal execution through the shared connection

#### Scenario: Two eligible users execute work
- **WHEN** two authorized users use the hosted terminal
- **THEN** Open Terminal assigns each user a separate user home and workspace identity
- **AND** one user's workspace files are not visible to the other through normal terminal access

### Requirement: Hosted terminal execution SHALL have an explicit trusted-team boundary
The system SHALL run Open Terminal without privileged mode, host filesystem mounts, runtime socket mounts, SSH credential mounts, or fleet secret mounts. It SHALL apply declared resource and network limits and SHALL document that free multi-user mode is not an untrusted-tenant isolation boundary.

#### Scenario: A terminal workload attempts host-level access
- **WHEN** a command in Open Terminal attempts to access host runtime sockets, fleet secrets, or undeclared host paths
- **THEN** those resources are absent from the workspace container
- **AND** the workload remains subject to its configured resource and network limits

#### Scenario: The audience changes to untrusted users
- **WHEN** access expands beyond the declared trusted group
- **THEN** the deployment is not treated as sufficient tenant isolation
- **AND** operators must adopt a separately approved per-user-container solution before expansion

### Requirement: Hosted terminal workspace data SHALL be explicit
The system SHALL declare whether terminal workspace data persists and SHALL include any persistent workspace path in the applicable backup and retention policy. The initial tool profile SHALL be fixed by the pinned image rather than unmanaged runtime package installation.

#### Scenario: The hosted terminal is recreated
- **WHEN** the OCI service is replaced during deployment
- **THEN** its declared workspace persistence behavior is preserved
- **AND** the resulting tool baseline is determined by the pinned image and declared configuration
