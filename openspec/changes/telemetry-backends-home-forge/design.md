# Design

## Context

See `proposal.md` for motivation and `specs/llm-observability/spec.md` for required behavior. The operator approved a fresh start: the trial accounts and backend state are disposable, so no database, trace, queue, workflow, or object transfer is required. This is authorization to discard that state, not a new measured claim that every table is empty.

The earlier read-only inventory found ample forge capacity: 18 GiB available RAM, 770 GiB free on root and 838 GiB free on `/srv/storage`. Grafana owns port 3000; port 3030 was free. Recheck ports/capacity at deployment. Source ClickHouse includes application and system data; its directories are not evidence that all contents are traces.

## Goals / Non-Goals

**Goals:** Initialize both stacks on forge, preserve public identities and access posture, and remove obsolete OCI resources after target acceptance.

**Non-Goals:** Data transfer, queue draining, trace/history/account preservation, a retained-source rollback programme, nix-fleet edits/relock/publish or agent–gateway adoption, Bifrost placement changes, and Hindsight tracing/queue deletion. Hindsight's disabled worker remains untouched.

## Decisions

### PLACE-1: Move aspects and host bindings

Move `langfuse`/`latitude` selections between `modules/hosts/{oci-melb-1,home-forge}/default.nix` and bindings between their `_nixos.nix` fragments. Existing concern-owned contributors and PostgreSQL registrations stay authoritative (`feature-topology`, D-058). No new bundle or duplicated backend body.

### PORT-1: Langfuse origin becomes 3030

Keep Grafana on 3000 and move Langfuse to 3030. Declare 3030 once in `policy/web-services.nix`; derive `services.langfuse.port` from the catalog. Latitude keeps 3001/3002/3110. Verify the remaining Redis, Temporal and ClickHouse listeners are free before activation.

Change providers of `langfuse`, `latitude`, `latitude-api`, and `latitude-ingest` to home-forge. The edge stays on OCI; public names, OIDC callbacks and Access settings do not change.

### STATE-1: Use normal fresh initialization

Forge's existing PostgreSQL instance `forge` provisions new `langfuse` and `latitude` databases/roles through their consumer registrations. Latitude keeps vector, BYPASSRLS and CREATEDB setup; Temporal's existing auto-setup creates fresh `temporal` and `temporal_visibility` databases. Do not copy either host's PostgreSQL cluster or alter Hindsight/AudioMuse.

ClickHouse initializes fresh at `/var/lib/clickhouse` on forge's spacious NVMe root. Redis instances and Latitude's `/srv/storage/latitude` state initialize through existing service wiring. No new bind mount, dump/restore, queue snapshot, staging dataset, or transfer manifest is needed.

Keep Langfuse's dedicated R2 bucket configuration and reusable credentials. Inventory and remove any obsolete source-owned objects after acceptance, without deleting shared buckets or objects; do not promise an empty object store merely because the databases restart fresh.

### SECRET-1: Reuse applicable credentials without widening host scope

Add forge to the three service-secret rules (`langfuse.yaml`, `latitude.yaml`, `telemetry.yaml`) and corresponding fixtures for cutover. Operator rewraps exactly those three files once the recipient rules are in the working tree, with `sops updatekeys -y secrets/services/langfuse.yaml`, `sops updatekeys -y secrets/services/latitude.yaml`, and `sops updatekeys -y secrets/services/telemetry.yaml`; no other file is rewrapped by this change and ciphertext is never edited by hand. After source retirement, remove obsolete OCI readership where no current consumer needs it and have the operator apply the recipient updates. Future gateway credential placement belongs to its own change.

Operator copies only `langfuse/client_secret` into forge's existing host OIDC file. Move the consumer binding and `modules/identity/identity-provider.nix` source map together. Move Langfuse between host templates for future bootstrap; never re-bootstrap populated files or grant forge access to all OCI OIDC clients. After acceptance, the operator removes the obsolete source key without changing Paperless/Karakeep/Grafana keys.

Langfuse's existing `LANGFUSE_INIT_*` contract seeds its fresh organization/project using the configured project keys; verify it actually succeeds and both login and ingest work. Latitude's old API key belonged to the discarded organization: the operator recreates the account/project, mints a key and fills `latitude/api_key` in `telemetry.yaml`. Keep the Latitude exporter disabled during this bootstrap window, then enable it after the replacement key is ready. Avoid exporting against a known-invalid old key.

### ROUTE-1: Leave gateway architecture to its own change

Current `modules/flake/telemetry.nix` derives colocated backend destinations from catalog locality, so those destinations move to forge. Verify this without implementing forwarding or direct producer-to-gateway wiring. Use a narrow temporary Latitude-exporter inhibit for fresh-instance bootstrap and remove it at acceptance; no second endpoint registry or permanent alternate routing surface.

### CLEAN-1: Retire exact source resources after target acceptance

Prepare an ownership-scoped cleanup inventory before deletion:

- PostgreSQL databases `langfuse`, `latitude`, `temporal`, `temporal_visibility`; drop their roles only after checking they have no remaining dependencies. Keep source instance `postgres`, Paperless, and all unrelated databases.
- Source ClickHouse application state and state directory only after proving the instance serves no remaining consumer. If shared, remove only the two backends' owned databases/tables/users.
- Backend Redis queues/cache state, Latitude's filesystem tree, Langfuse's exclusive runtime directories, and obsolete named containers/network resources. Inspect mounts and ownership before deleting; no broad Podman prune or generic parent-directory removal.
- Obsolete dedicated Langfuse R2 objects, if present, identified by actual bucket/prefix ownership. Inventory exact source object keys before target writes; delete only objects still distinguishable as obsolete, never target-created or overwritten objects. Reusable credentials/bucket configuration stay when the fresh instance consumes them.
- Source aspect selections, host bindings, stale OIDC template/provider entries, docs/test placement pins and unneeded secret readership. Encrypted key removal/rewrap remains operator-owned.

Do not delete source resources until forge is accepted. No indefinite old deployment remains for rollback.

## Risks / Trade-offs

- **Fresh state loses trial accounts and jobs:** explicitly approved; expose the reset in the runbook rather than pretending to preserve identities or histories.
- **Latitude old key fails on the fresh database:** inhibit its exporter, require the operator's replacement, and prove authenticated ingest before acceptance.
- **Langfuse seed may fail despite intended configuration:** verify organization/project creation, SSO and ingest from the running instance.
- **Shared-resource deletion:** verify exact ownership before cleanup; no whole PostgreSQL cluster deletion, unchecked ClickHouse wipe, bucket-wide purge or broad container prune.
- **Ingest during cutover goes to the wrong instance:** pause backend export/source writes, switch only after target readiness, then resume. A lossless ingestion window is not promised for disposable trial state.
- **More backends depend on forge:** consolidation is intentional; monitor RAM/disk/I/O after startup.
- **ARM → x86_64 image support:** confirm pinned images support the target architecture. No physical database portability problem remains because state is not copied.
- **Cleanup removes stateful rollback:** before cleanup, failed activation can leave source resources available; after deletion, recovery means fresh deployment, not restoration of discarded histories.

## Cutover and Cleanup

1. Implement placement/port/secret bindings, related tests and docs; verify target ports, image architecture and capacity. Inventory exact source cleanup resources.
2. Operator prepares recipient updates and the forge OIDC key. Gate the settled staged tree; do not edit while gates run.
3. Pause old backend exports/writers. Initialize forge's normal substrate/apps with the Latitude exporter inhibited. Do not expose target traffic until health checks pass.
4. Deploy edge route changes and the identity-provider source binding. Verify Langfuse seed/SSO and Latitude login; the operator recreates Latitude's project and supplies its new ingest key.
5. Remove the bootstrap exporter inhibit. Verify a fresh synthetic trace in each backend and expected collector destinations; check Grafana, Paperless, Hindsight/AudioMuse health.
6. Remove source backend units/selections and execute the verified scoped cleanup inventory. Remove stale config/secret access with operator-owned ciphertext updates; verify unrelated services remain healthy and retired resources are absent.
7. Record accepted deployment revisions and cleanup evidence. Resume the paused Hindsight change separately.

No source-state export or restore is part of these steps. If target activation fails before cleanup, withhold destructive cleanup and correct or revert placement. Once source resources are deleted, rebuilding services is the recovery path.

