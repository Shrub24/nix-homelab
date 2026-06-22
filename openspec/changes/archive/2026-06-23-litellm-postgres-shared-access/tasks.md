## 1. Shared Postgres module

- [x] 1.1 Add module options for a Postgres-owned secret file and LiteLLM password key/allowed CIDRs.
- [x] 1.2 Add `litellm` to `ensureDatabases` and `ensureUsers` with login and database ownership.
- [x] 1.3 Add Tailscale-scoped `pg_hba.conf` SCRAM authentication rules for the LiteLLM role.
- [x] 1.4 Render the LiteLLM password from the Postgres-owned SOPS secret file and apply it with `ALTER USER` on PostgreSQL start/restart.
- [x] 1.5 Add assertions so enabling LiteLLM requires the Postgres-owned secret file.

## 2. Host wiring

- [x] 2.1 Enable `services.postgres-shared.litellm` on `oci-melb-1`.
  - Enabled at `hosts/oci-melb-1/default.nix`; secret file `secrets/services/postgres-shared.yaml` exists.
- [x] 2.2 Point the LiteLLM password source at a Postgres-owned secret file path, without creating or editing encrypted secret contents.
  - `secretFile = ../../secrets/services/postgres-shared.yaml` set on host; password key path defaults to `roles/litellm/password`.

## 3. Operator docs

- [x] 3.1 Document the required SOPS key path and example `sops` command for the operator to add the password.
- [x] 3.2 Document the laptop LiteLLM `DATABASE_URL` shape over Tailscale.

## 4. Validation

- [x] 4.1 Run a focused Nix parse/eval check for the changed module/host wiring.
- [~] 4.2 Run `openspec validate --strict litellm-postgres-shared-access` if the OpenSpec CLI is available.
  - Attempted, but `openspec` is not available on PATH in this shell.
- [x] 4.3 Update these task checkboxes as work completes.
