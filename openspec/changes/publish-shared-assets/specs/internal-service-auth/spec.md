# Spec Delta

## MODIFIED Requirements

### Requirement: Service-to-service secrets SHALL remain host-scoped by default

Credentials used for caller-owned internal integrations SHALL be defined in explicit service-, application-, or host-exception-scoped secret files according to integration ownership and SHALL NOT be promoted to unrelated shared scope without explicit justification. A credential MAY be shared by every host that uses it when the credential's own authority is itself the limit — specifically when it is restricted to a single inert object-storage bucket with object read and write only, and carries no account, bucket-administration or other-bucket authority.

#### Scenario: Homepage integration credentials are declared
- **WHEN** new Homepage or related integration credentials are added
- **THEN** they are sourced from an explicit feature-owned secret scope and templated for runtime use
- **AND** they are not introduced in unrelated shared/common secret scope by default

#### Scenario: A single-bucket publish credential is shared

- **WHEN** several hosts publish into one asset bucket
- **THEN** they may read one shared credential from common secrets, scoped to that bucket alone
- **AND** the readership widening is justified by the credential's own authority rather than by convenience

#### Scenario: A broader credential is requested for the same reason

- **WHEN** a shared credential would carry account-level, bucket-administration or multi-bucket authority
- **THEN** it remains host-scoped, per-host or otherwise separated, and is not shared on the single-bucket justification
