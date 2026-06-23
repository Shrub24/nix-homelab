# Postgres Shared — SOPS Secret File

The `services.postgres-shared` module can manage database role passwords
for external consumers (e.g. LiteLLM) from a single Postgres-owned
SOPS-encrypted YAML file.

## File path

```
secrets/services/postgres-shared.yaml
```

This file is **owned by the postgres-shared module** — it is declared in
`.sops.yaml` under `secrets/services/postgres-shared.yaml` with key groups
for the admin (`owner_age`) and the Postgres host (`oci_melb_1_age`).

The `.sops.yaml` creation rule was added at the same time as the module
options. You do not need to add a new rule.

## Creating the encrypted file

```bash
# Create and edit the new SOPS file
sops secrets/services/postgres-shared.yaml
```

## Required key structure

The expected YAML keys follow a `roles/<name>/password` pattern:

```yaml
roles:
  litellm:
    password: <generated-password>
```

The default `passwordKey` for each consumer:

| Consumer | Default key path             |
| -------- | ---------------------------- |
| litellm  | `roles/litellm/password`     |

## Enabling a consumer on the host

After the secret file exists with the required keys, enable the consumer
in `hosts/oci-melb-1/default.nix`:

```nix
services.postgres-shared = {
  enable = true;
  secretFile = ../../secrets/services/postgres-shared.yaml;
  litellm.enable = true;
  # Existing consumers stay unchanged:
  niks3.enable = true;
  paperless.enable = true;
  audiomuse.enable = true;
};
```

The module will:
1. Create the `litellm` database and login role with DB ownership.
2. Render the Postgres password from the SOPS secret and apply it via
   `ALTER USER litellm PASSWORD ...` on PostgreSQL start/restart.
3. Add `pg_hba.conf` SCRAM authentication rules for the allowed CIDRs
   (default: Tailscale `100.64.0.0/10` and `fd7a:115c:a1e0::/48`).

## Database URL for the consuming application

Once the consumer is enabled and Postgres has restarted, the consuming
application (e.g. laptop LiteLLM) connects over Tailscale using the
custom `DATABASE_URL` format:

```
postgresql://litellm:<password>@oci-melb-1.tailnet-name.ts.net:5432/litellm
```

Components:
- **User**: `litellm`
- **Password**: Retrieved from `roles/litellm/password` in
  `secrets/services/postgres-shared.yaml` (do not check in plaintext).
- **Host**: Tailscale hostname or MagicDNS name — `oci-melb-1` (or the
  full `<hostname>.<tailnet-name>.ts.net` FQDN).
- **Port**: `5432` — Postgres standard port, accessible only over
  Tailscale (the podman interface firewall opens port 5432 but the
  Tailscale ACL is the real access boundary).
- **Database**: `litellm`

> **Important**: The LiteLLM service on the laptop must manage its own
> secret injection. The password in the SOPS file is a Postgres-side
> credential, not a LiteLLM runtime secret. The operator copies the
> password into the laptop's own secrets environment (out of scope for
> this repository).

## Validation

After enabling the consumer:

```bash
# Check that Postgres applies the password correctly
sudo journalctl -u postgresql --since "5 minutes ago" | grep -i "ALTER USER"
```
