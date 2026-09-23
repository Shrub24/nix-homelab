# Postgres — consumer credentials

A consumer's role credential belongs to the consumer. It is declared in the
registration itself (`password = { file, key }`), and the same file and key are
read twice on the same host: by the cluster to provision the role's password,
and by the service to authenticate. One authoritative source, no hand-synced
pair (D-058).

## Where credentials live

| consumer | file | key | readers |
| --- | --- | --- | --- |
| `paperless` | — | — | `auth = "peer"` over the Unix socket; no credential exists |
| `audiomuse` | `secrets/applications/music.yaml` | `audiomuse/postgres_password` | home-forge's cluster (provisioning) and the AudioMuse container (authentication) |

`secrets/services/postgres-shared.yaml` is retired: it held the OCI-side
AudioMuse role password and the LiteLLM password, and after the AudioMuse
database moved to home-forge nothing reads it. Deleting the file and its
`.sops.yaml` rule is an operator action.

## Declaring a consumer

```nix
services.postgres.consumers.<name> = {
  database = "<database>";
  # role defaults to the consumer name
  auth = "scram";
  password = {
    file = ../../../secrets/applications/<name>.yaml;
    key = "<path/within/file>";
  };
  allowedCIDRs = [ "<source range>" ];
  extensions = ps: [ ps.pgvector ];
  setupSQL = "CREATE EXTENSION IF NOT EXISTS vector;";
};
```

A `scram` consumer without a `password`, or one whose file does not exist, fails
evaluation with a named error. `auth = "peer"` needs no credential at all and is
the right choice for a host-local consumer that connects over the Unix socket.

## Cross-host consumers

A consumer whose database lives on another host is registered by the **provider**
host, because that is the only host that can create the role and apply its
password. Registering it there means the provider host gains read access to the
consumer's secret file — an explicit, reviewed widening of `.sops.yaml`
readership, never an automatic consequence.

## Rotation

Edit the value in the consumer's own file and re-encrypt that one file; the
cluster applies it on the next `postgresql.service` start
(`restartUnits = [ "postgresql.service" ]` is set on the derived secret). No
second file needs to change.

## Runtime paths

The cluster materialises each credential at
`/run/secrets/postgres/<consumer>.password`, owned by `postgres` with mode
`0400`, and never copies it elsewhere.
