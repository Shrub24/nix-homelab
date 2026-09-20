## Context

`modules/services/postgres-shared.nix` is the only substrate in the fleet that a consumer cannot extend without editing it. This design fixes that by separating three concerns that are currently fused: the **mechanism** (how a cluster is configured, provisioned, and backed up), the **instance** (which cluster runs where), and the **consumer** (which database and role a service needs).

Two registration precedents already exist in this repository and are the template:

- `services.state-backups.services.<name>` — feature modules register their own paths, excludes, and prepare/cleanup commands (`modules/services/paperless/default.nix:238`, `modules/services/karakeep.nix:292`); the backup aspect never learns who it backs up.
- `services.notification-daemon.monitor.units.<unit>` — feature modules register per-event hooks, the module generates mechanics, and a named assertion rejects registrations that do not correspond to a real unit.

## Decisions

### MPI-1 — Three layers: mechanism leaf, instance aspects, consumer registrations

- **Mechanism** (`modules/services/postgres/`): options `instances.<name>.{runtime, port, dataDir, version}` plus a registry `consumers.<instance>.<consumer>`. It renders SQL and `pg_hba`, registers backup/export, and resolves endpoints. It names no consumer and no instance.
- **Instance** (`modules/<domain>/postgres-<name>.nix` or `modules/flake/postgres.nix` for the primary): a discovered contributor publishing `flake.modules.nixos.postgres-<name>` that imports the mechanism and sets `instances.<name>`. Several instance aspects merge into the same mechanism options — the multi-contributor merge pattern already used for `identity-client`.
- **Consumer** (`services.postgres.consumers.<instance>.<consumer>`): contributed by the consumer's own module as a `mkIf cfg.enable` block, exactly like a backup registration.

A consumer key is a **consumer name**, not a host ID: the same database may be consumed by a host-local service today and by an out-of-repo client later. `allowedCIDRs` expresses "who may authenticate as this role", which is the seam that makes non-repo consumers expressible without a new mechanism.

### MPI-2 — The primary instance stays native; a second cluster is a fresh runtime decision

*(Narrowed after review: the `runtime` and `version` instance fields were dropped. Instances carry `port` and `dataDir` only, so a container instance is not expressible yet — choosing that runtime is its own decision with consequences for the backup/export path, not an option added speculatively.)*

The primary instance keeps `services.postgresql`, because `postgresqlBackup` feeds the restic state backup and that integration works. `instances.<name>.runtime` exists so a later cluster can be a container (matching the nine containerized services) without changing the consumer surface. No container runtime is implemented by this change, and no placeholder option stands in for one.

### MPI-3 — Registration is validated fail-closed

Named evaluation errors, in the shape the fleet already uses for host references, web policy, and internal contracts:

- a consumer naming an instance that no selected aspect provides;
- an instance aspect running on a host that does not need it (reported through the contract's provider check rather than a new rule);
- a consumer whose declared role has no credential path when its authentication mode requires one;
- a contract whose declared port differs from the instance's real listen port.

### MPI-4 — The transport contract becomes per instance

`repo.internal.postgres` becomes `repo.internal.postgres.<instance>.{provider, port, host, fqdn, url}`, resolved from the provider's canonical host record, with the existing provider-capability and port-drift checks retained per instance. `tests/check-internal-contracts.sh` currently pins the contract surface to exactly two names; it is updated to pin the *families* (`postgres`, `niks3Write`) and to assert per-instance resolution. The single-instance default keeps consumers that do not care about instances reading a stable attribute — the music aspect's audiomuse binding is the only cross-host consumer today.

### MPI-5 — One credential per (instance, consumer)

Today the audiomuse password must be identical in two encrypted files. In the new shape the consumer owns its credential and the provider reads it only to provision the role, or the provider owns it and the consumer reads only its own — either way exactly one file is authoritative, and the other side's readership is explicit. Because this changes `.sops.yaml` readership, it is a blast-radius change: it is proposed in the design, verified by an explicit scope check, and applied as an operator-owned step rather than an automatic re-encryption.

### MPI-6 — litellm is not migrated

`litellm` is being retired; its consumer block is deleted rather than translated. If it is still enabled anywhere at implementation time, the change stops and asks rather than carrying it forward.

## Risks

| Risk | Mitigation |
| --- | --- |
| The refactor changes provisioning for existing databases | Equivalence gate: evaluated `postStart` SQL, `pg_hba` rules, enabled databases/roles, export paths, and backup registration are compared before and after; any delta is classified rather than accepted |
| Instance aspects drift into a bundle | Each instance aspect is independently selectable and the mechanism imports nothing itself; the scaffold contract's aspect inventory is extended, not bypassed |
| The per-instance contract breaks the "exactly two contracts" rule the tests encode | The test is updated to pin families and per-instance entries, and to keep rejecting a third family (identity and ntfy stay web-catalog contracts) |
| Consumers on other hosts lose their endpoint | The cross-host consumer (audiomuse via the music aspect) is the conformance case: it must resolve through `repo.internal.postgres.<instance>` with no host literal, proven by the existing no-literal check |
| Out-of-repo consumers are designed in prematurely | They are explicitly out of scope; only `allowedCIDRs` and the consumer-name keying leave room for them |

## Evidence base

- Upstream constraint: the pinned nixpkgs `services.postgresql` has no `instances` option and a single `settings` block (no multi-instance support to build on).
- In-repo precedents: `state-backups.services.<name>` and `notification-daemon.monitor.units.<unit>` registrations; the Stage 8 internal-contract module with provider-capability and port-drift validation.
- Current consumer surface: `services.postgres-shared.{niks3,paperless,audiomuse,litellm}` with `passwordKey` and `allowedCIDRs` per consumer, all four enabled on `oci-melb-1`.
