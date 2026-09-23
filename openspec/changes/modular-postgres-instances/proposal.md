# Modular PostgreSQL substrate with per-instance registration

## Why

PostgreSQL is the fleet's most-consumed substrate and its least modular component. `modules/services/postgres-shared.nix` hardcodes one consumer-shaped option block per database client:

```
services.postgres-shared.niks3.enable / paperless.enable / audiomuse.enable / litellm.enable
```

each with its own `passwordKey`, `allowedCIDRs`, and hand-written contribution to the generated `postStart` SQL and `pg_hba` rules. The consequences are structural, not cosmetic:

- **Consumers cannot register themselves.** A new database client means editing the substrate module — the same reverse-index defect already fixed twice for notification monitoring (`monitor.units.<unit>`) and backups (`state-backups.services.<name>`).
- **One instance, forever.** The operator expects multiple clusters with distinct consumer sets. Upstream nixpkgs offers no help: the pinned nixpkgs `services.postgresql` has a single `settings` block and no `instances` option, so multi-instance support is necessarily ours to build.
- **The transport contract is singular.** `repo.internal.postgres` resolves one endpoint from one provider, so consumers restate `postgresHost`/`postgresPort` to reach a second cluster.
- **Credentials are hand-synced.** The audiomuse password must match across two encrypted files — the provider's `roles/audiomuse/password` and the consumer's `audiomuse/postgres_password` — with a comment asking the operator to keep them aligned.

## What changes

- A PostgreSQL **mechanism leaf** owns rendering and provisioning only: it consumes an `instances` map and a consumer registry, and generates the SQL, `pg_hba` entries, backup/export registration, and endpoint resolution. It names no consumer and no instance.
- An **instance is a placement aspect**: `postgres` keeps the existing native cluster on `oci-melb-1`, and any later instance is a sibling aspect contributing its own entry to the instances map. Aspect selection states which host runs which cluster.
- **Consumers register themselves** from their own modules, mirroring the two established registration precedents in this repository.
- The **transport contract becomes per instance** (`repo.internal.postgres.<instance>`), with the same provider-capability and port-drift validation the current single contract has.
- **One credential per (instance, consumer)**, owned by the consumer, with explicit readership — removing the two-file sync for audiomuse.
- The **litellm** consumer is not migrated: it is being retired. The canonical `postgres-shared-access` requirements written around it (its database/role provisioning, its Tailscale-scoping rule, and the Postgres-owned-password rule shaped for that single external consumer) are removed rather than carried forward, and the credential and connection-detail rules are re-added for the per-(instance, consumer) model.

## Scope

**In scope:** `modules/services/postgres-shared.nix` and its aspect `modules/flake/postgres.nix`; the two in-repo consumers that provision databases (paperless, niks3) and the cross-host consumer (audiomuse through the music aspect); the postgres contract in `modules/fleet/internal-contracts.nix`; the LA/OCI host bindings; the contract tests that pin the postgres surface; documentation of the registration pattern.

**Out of scope, deliberately:** consumers that run outside this repository (a laptop, for example). The registry's `allowedCIDRs` per consumer is the seam that makes that possible later, but out-of-repo consumer registration is a future `nix-fleet` policy question and is not designed here. Also out of scope: retiring or replacing Bifrost and Phoenix (separate decisions), and any change to which host runs the primary cluster.

## Constraints

- The primary instance keeps the **native** `services.postgresql` runtime, because the existing `postgresqlBackup` export feeds the restic state backup; replacing it with a container would rebuild that integration for no current benefit. Instances therefore carry `port` and `dataDir` only; a later cluster that wants a container runtime makes that a fresh decision with its own consequences rather than an unused option added now.
- Evaluation-time behaviour must be preserved for the existing consumers: identical databases, roles, authentication modes, CIDR allowlists, exported dumps, and backup registration.
- No secret value, ciphertext, or `.sops.yaml` readership changes automatically; the audiomuse credential consolidation is a *readership* change and must be reviewed as a blast-radius change rather than slipped in.
- Consumers reach a cluster only through the instance contract; no consumer may hardcode a provider host name.
