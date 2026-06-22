# LiteLLM shared Postgres access

## Why

The laptop-hosted LiteLLM proxy needs a durable database backend. The fleet already has a shared PostgreSQL instance on `oci-melb-1` that listens on TCP for local container consumers and is reachable over the private Tailscale network. Rather than deploy another database, create a dedicated LiteLLM database and role on the shared instance.

## What Changes

- Add a `services.postgres-shared.litellm` consumer that creates a `litellm` database and login role.
- Manage external-consumer Postgres role passwords from a Postgres-owned SOPS file, not from a LiteLLM service secret file, because this repository is configuring Postgres-side access control rather than running the external LiteLLM proxy.
- Restrict LiteLLM TCP password authentication to Tailscale CIDRs by default.
- Enable the LiteLLM Postgres consumer on `oci-melb-1`.
- Document the operator action required to add the encrypted password secret and configure the laptop LiteLLM `DATABASE_URL`.

## Non-Goals

- Do not deploy LiteLLM on `oci-melb-1`.
- Do not manage the laptop's LiteLLM runtime secret injection in this repository.
- Do not manually decrypt or edit existing encrypted secrets.
- Do not open public Postgres access.

## Impact

- `modules/services/postgres-shared.nix`
- `hosts/oci-melb-1/default.nix`
- `openspec/changes/litellm-postgres-shared-access/tasks.md`
- `openspec/changes/litellm-postgres-shared-access/specs/postgres-shared-access/spec.md`

