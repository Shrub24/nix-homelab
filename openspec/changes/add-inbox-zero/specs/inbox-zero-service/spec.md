## ADDED Requirements

### Requirement: IZ-1 Personal Gmail deployment

The fleet SHALL provide Inbox Zero on `oci-melb-1` using a pinned release compatible with `aarch64-linux`. Sign-in SHALL use Google and SHALL be restricted to the operator-configured Gmail allowlist. A missing allowlist SHALL prevent an unrestricted deployment.

#### Scenario: Operator signs in

- **WHEN** an allowlisted Gmail user completes Google authorization
- **THEN** the application SHALL establish that user's session and authorized mailbox connection
- **AND** a non-allowlisted account SHALL NOT acquire an application account

### Requirement: IZ-2 Authenticated public mail delivery

The application SHALL accept wrapped Google Pub/Sub POST deliveries over public HTTPS without an interactive Cloudflare Access gate. A nonempty webhook verification token SHALL be required. Database access and model calls SHALL NOT use public application routes.

#### Scenario: Invalid webhook credential

- **WHEN** a Pub/Sub-shaped POST carries a missing or incorrect verification token
- **THEN** it SHALL be rejected before mailbox processing

#### Scenario: Valid mail notification

- **WHEN** a correctly authenticated notification names a connected mailbox
- **THEN** the application SHALL attempt to process its Gmail history
- **AND** successful HTTP acknowledgement SHALL NOT be represented as proof that processing completed durably

### Requirement: IZ-3 Scheduled mailbox maintenance

The deployment SHALL renew Gmail watches every six hours and dispatch scheduled email actions every minute through authenticated calls to the private local application origin. Failed HTTP responses SHALL cause the maintenance unit to fail rather than report success.

#### Scenario: Timer authorization fails

- **WHEN** a maintenance call receives an HTTP error
- **THEN** its job SHALL report failure
- **AND** the deployed failure-notification mechanism SHALL receive that failure

### Requirement: IZ-4 Isolated recoverable database

Inbox Zero SHALL use a dedicated database and non-superuser role on the placing host's native PostgreSQL substrate. Its authentication SHALL be scoped to the application network, and the application SHALL start only after provisioning. Application state SHALL be covered by the substrate's database-export backup; recovery SHALL retain the associated email-encryption secrets.

#### Scenario: Application deployment and recovery

- **WHEN** the operator starts a fresh deployment
- **THEN** the required database extensions SHALL exist before application migrations run
- **AND** acceptance SHALL verify migration success rather than infer it from a listening web process

#### Scenario: Database restoration

- **WHEN** a database export is restored with the original encryption secret and salt
- **THEN** recovery instructions SHALL include checking stored account-credential usability and renewing mailbox watches
- **AND** a database restore alone SHALL NOT be claimed to reconstruct missing Google Cloud resources

### Requirement: IZ-5 Local structured AI routing

Inbox Zero SHALL use the colocated Bifrost gateway through an address reachable from its container and the configured fleet text-model alias. Deployment acceptance SHALL exercise a representative schema-constrained request produced by the application integration, not merely ordinary chat.

#### Scenario: Gateway or model cannot satisfy the request

- **WHEN** the gateway or routed model rejects the structured request or returns nonconforming output
- **THEN** the deployment SHALL be reported as failing AI acceptance
- **AND** it SHALL NOT silently switch to a public route or unrelated provider credential

### Requirement: IZ-6 Secret and operating boundaries

OAuth, session, encryption, database, webhook and maintenance credentials SHALL be delivered outside the Nix store and scoped to this application's placing host. Logs under deployment control SHALL NOT expose webhook query tokens. The runbook SHALL describe best-effort ingestion, Google consent configuration and refresh-token expiry, and SHALL NOT recommend External Testing as an unattended long-term operating configuration.

#### Scenario: Preparing an unattended instance

- **WHEN** the operator prepares Google consent and Pub/Sub configuration
- **THEN** the runbook SHALL identify the two OAuth callbacks, publisher grant, wrapped push endpoint and watch-renewal checks
- **AND** it SHALL warn that Gmail-scoped refresh tokens in External Testing expire after seven days
- **AND** it SHALL distinguish external operator prerequisites from repository configuration validation
