## Context

The fleet runs a shared PostgreSQL instance on `oci-melb-1` (`services.postgres-shared`) that already serves internal Podman consumers like AudioMuse via TCP with SCRAM password auth. A laptop-hosted LiteLLM proxy needs a durable database backend. Rather than deploy another database on the laptop or a separate Postgres container on the fleet, the shared instance can provision a dedicated `litellm` database and role reachable over Tailscale.

The key architectural distinction: this repository manages **Postgres-side access control** (database, role, auth rules, password application), not the LiteLLM proxy runtime. The laptop's LiteLLM process is external to this fleet and manages its own secret injection.

## Goals / Non-Goals

**Goals:**
- Provision a `litellm` database and login role on the shared Postgres instance.
- Apply the role password from a Postgres-owned SOPS secret during PostgreSQL startup.
- Scope TCP auth to Tailscale CIDRs by default.
- Document the operator steps for secret creation and laptop `DATABASE_URL` configuration.

**Non-Goals:**
- Deploy or manage LiteLLM on `oci-melb-1` or any fleet host.
- Manage laptop-side secret injection for LiteLLM.
- Open public Postgres access.
- Migrate or back up LiteLLM data (the laptop owns its own backups).

## Decisions

### LLM-1: Postgres-owned secret file, not LiteLLM service secret

**Chosen:** The LiteLLM role password lives in a Postgres-owned SOPS file (`secrets/services/postgres-shared.yaml` under key `roles/litellm/password`), rendered only for the `postgres` user.

**Rationale:** This repository configures Postgres-side access control, not the LiteLLM runtime. Putting the password in a LiteLLM service secret file would imply this repo owns LiteLLM's runtime secrets, which it does not. The Postgres-owned file keeps the blast radius scoped to Postgres configuration.

**Alternatives considered:** Reuse the existing `audiomuse` pattern of per-service SOPS files. Rejected because AudioMuse is a fleet-hosted service whose entire runtime is repo-managed; LiteLLM is external.

### LLM-2: Tailscale-scoped pg_hba rules

**Chosen:** SCRAM auth rules for the `litellm` role default to Tailscale IPv4 (`100.64.0.0/10`) and IPv6 (`fd7a:115c:a1e0::/48`) CIDRs. No `0.0.0.0/0` or `::/0` fallback.

**Rationale:** The laptop connects over Tailscale. Restricting to Tailscale CIDRs means only authenticated tailnet members can attempt the Postgres connection. This is stricter than the AudioMuse pattern (which allows `0.0.0.0/0` for Podman bridge access) because LiteLLM is an external consumer, not a local Podman container.

**Alternatives considered:** Allow `0.0.0.0/0` like AudioMuse. Rejected — AudioMuse needs broad CIDRs because Podman bridge IPs are unpredictable; LiteLLM connects over a known Tailscale range.

### LLM-3: Password applied via postStart, same pattern as AudioMuse

**Chosen:** Use `systemd.services.postgresql.postStart` to run `ALTER USER litellm PASSWORD ...` reading from the rendered SOPS template, identical to the AudioMuse password pattern.

**Rationale:** `ensureUsers` does not support password assignment. The `postStart` hook is the established repo pattern for applying passwords from SOPS templates on each Postgres start/restart, ensuring password rotations take effect without manual SQL.

## Risks / Trade-offs

- **Operator must create the SOPS file before enabling** → Task 2.1/2.2 are blocked until `secrets/services/postgres-shared.yaml` exists with `roles/litellm/password`. The module includes assertions that fail evaluation if the secret file is not provided.
- **Tailscale CIDR assumption** → If the tailnet uses a non-default range, the operator must override `allowedIpv4Cidr`/`allowedIpv6Cidr`. Default values match standard Tailscale allocations.
- **No LiteLLM-side validation** → This change provisions Postgres access only. End-to-end validation (laptop connecting to the database) is an operator step outside this repository's scope.
