# PostgreSQL substrate

One native cluster per host, declared by the host that runs it, provisioned from a consumer registry. `modules/database/postgres/_consumer.nix` declares the options and `modules/database/postgres.nix` renders provisioning; the two are separate so a feature can register on a host that does not run the cluster.

## Registration

`services.postgres.consumers.<name>` declares one database and its access:

| Field | Meaning |
| --- | --- |
| `database` | Database the consumer owns. |
| `role` | Login owning the database; defaults to the consumer name. |
| `auth` | `peer` for a host-local consumer over the Unix socket, `scram` for a password login. |
| `password` | `{ file, key }` of the owning role's password — the same source the consumer reads to authenticate. |
| `allowedCIDRs` | Sources allowed to authenticate with a password. A bridged container arrives as its bridge address, a dialer in the host network namespace as the service address. |
| `additionalRoles` | Further restricted logins for the same database, keyed by role name. |
| `extraDatabases` | Satellite databases the owning role may reach (Temporal creates its own). |
| `extensions` | Server-side extension packages this consumer needs. |
| `setupSQL` | Idempotent SQL run in the consumer's database on every cluster start, as the superuser. |

A consumer on another host is registered by the provider: only the cluster can create its role.

## Additional logins

Some applications use two roles — an owner that migrates the schema and a restricted login that serves requests — and neither may hold cluster-wide role-creation rights. `additionalRoles` provisions the second role in the same registration:

```nix
services.postgres.consumers.example = {
  database = "example";
  role = "example";                 # owner, runs migrations
  auth = "scram";
  password = { file = ../secrets/services/example.yaml; key = "roles/example/password"; };
  allowedCIDRs = [ "127.0.0.1/32" serviceNetwork.containerSourceCIDR ];
  additionalRoles.example_app.password = {
    file = ../secrets/services/example.yaml;
    key = "roles/example-app/password";
  };
};
```

An additional login gets `LOGIN`, its declared password, and HBA rows for `database` only, followed by its own catch-all `reject`. It never owns the database, is never a member of the owning role, and is never granted `CREATEROLE` or superuser. Every role and credential of a consumer exists before its `setupSQL` runs, so setup SQL may grant to the additional login.

Rotating a password means editing the secret and redeploying: the substrate's `sops.secrets` entries name `postgresql-provision.service` in `restartUnits`, and that unit re-applies the passwords it owns.

A login name is provisioned by one consumer only; the substrate fails evaluation when two registrations declare the same owning or additional role, because one role cannot carry two credentials or two sets of connection rules.

The behaviour is proven on a booted node rather than asserted from the configuration: `nix build .#checks.x86_64-linux.postgres-consumer-roles` provisions an ephemeral cluster with an owner, an application login and an unrelated consumer, then authenticates as each role, re-provisions, and rotates one password.

## Activation order

The rendered `pg_hba.conf` lives at a store path, and the cluster's `postgresql.conf` symlink only adopts a new one when the server starts. So the substrate names the rendered authentication rules as a `postgresql.service` restart trigger: adding or removing a consumer restarts the cluster, and the new rules are live when activation finishes. Other consumers see a brief restart, which is the cost of the store-path indirection rather than a choice.

A consumer whose unit runs before that restart is refused with `no pg_hba.conf entry for host …`, and a container that retries it quickly exhausts systemd's start limit, which fails the whole activation. A unit that connects over TCP therefore orders itself after the cluster and its provisioning:

```nix
wants = [ "network-online.target" ];
after = [
  "podman-network-<app>.service"
  "postgresql.service"
  "postgresql-provision.service"
];
requires = [
  "podman-network-<app>.service"
  "postgresql-provision.service"
];
```

`requires` on the provisioning unit also means a failed provisioning fails that consumer's start rather than leaving it authenticated but empty.

## Recovery

The database is not backed up by copying its data directory. `postgresqlBackup` writes a logical export of every cluster database and role into `services.state-backups.stagingRoot/postgres`, restic captures it, and the export is removed after the run. Restoring it re-creates the databases and roles, so `pg_hba` and the consumer registry must be current before the roles authenticate. `docs/runbooks/state-restore.md` covers the staged restore.

## Beyond this file

Why the substrate splits its mechanism from a declaration-only contract, and why additional logins are provisioned here instead of by each application, are recorded in `docs/decisions.md` (D-058 for the registry, D-129 for additional logins).
