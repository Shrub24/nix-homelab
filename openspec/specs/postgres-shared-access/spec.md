## ADDED Requirements

### Requirement: Shared Postgres can provision external LiteLLM access

The shared PostgreSQL module SHALL support an explicit LiteLLM external-consumer configuration that creates a dedicated `litellm` database and login role.

#### Scenario: LiteLLM database consumer is enabled

- **WHEN** `services.postgres-shared.litellm.enable` is true
- **THEN** the NixOS PostgreSQL configuration SHALL ensure a `litellm` database exists
- **AND** it SHALL ensure a login-capable `litellm` role exists
- **AND** the `litellm` role SHALL own the `litellm` database

### Requirement: External consumer role passwords are Postgres-owned secrets

PostgreSQL role passwords for external consumers SHALL be sourced from a Postgres-owned SOPS secret file, because this repository is managing Postgres-side access control rather than the external consumer runtime.

#### Scenario: LiteLLM password is configured

- **WHEN** `services.postgres-shared.litellm.enable` is true
- **THEN** the module SHALL require a SOPS secret file containing the LiteLLM role password
- **AND** it SHALL render that secret only for the `postgres` user
- **AND** it SHALL apply the password to the `litellm` role during PostgreSQL startup or restart

### Requirement: LiteLLM Postgres authentication is Tailscale-scoped

LiteLLM TCP password authentication SHALL be scoped to explicitly configured allowed CIDRs and SHALL default to Tailscale address ranges.

#### Scenario: Authentication rules are rendered

- **WHEN** LiteLLM Postgres access is enabled
- **THEN** `pg_hba.conf` SHALL include SCRAM authentication rules for the `litellm` database and role
- **AND** the default allowed IPv4 CIDR SHALL be `100.64.0.0/10`
- **AND** the default allowed IPv6 CIDR SHALL be `fd7a:115c:a1e0::/48`
- **AND** it SHALL NOT add unrestricted `0.0.0.0/0` or `::/0` access for the `litellm` role by default

### Requirement: Operator-facing connection details are documented

The change SHALL document the external LiteLLM connection string shape without committing plaintext credentials.

#### Scenario: Operator configures laptop LiteLLM

- **WHEN** the operator needs to configure laptop LiteLLM
- **THEN** the repository SHALL provide the `DATABASE_URL` shape using the Tailscale host name
- **AND** it SHALL instruct the operator to retrieve or inject the password outside this repository's plaintext history
