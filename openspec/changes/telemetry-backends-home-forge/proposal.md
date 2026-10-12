# Proposal

## Why

Langfuse and Latitude run on OCI while the telemetry stores and Grafana run on home-forge. Putting the backends on home-forge reduces the number of hosts involved in operating the observability stack.

**Core Value:** One telemetry-backend host, with fresh application state and no abandoned OCI deployment.

## What Changes

- Move the `langfuse` and `latitude` aspect selections and their host bindings from `oci-melb-1` to `home-forge`.
- **BREAKING:** Initialize both stacks afresh. The operator has declared the trial accounts and backend state disposable; projects, traces, queues, workflow histories, and filesystem objects are not transferred.
- Keep OCI's PostgreSQL cluster for Paperless and preserve forge's Hindsight/AudioMuse databases.
- Move the four backend route providers to home-forge without changing public hostnames, OIDC callbacks, or Access posture. Give Langfuse origin port 3030 because Grafana already uses 3000.
- Reuse applicable service and OIDC credentials through scoped, operator-owned secret updates. Move only Langfuse's OIDC key into forge's host OIDC file; do not grant forge access to OCI's other clients.
- Seed Langfuse through its existing initialization contract. The operator recreates Latitude's account/project and replaces its collector API key; the old organization key does not authenticate to a fresh database.
- After forge acceptance, remove the obsolete OCI runtime, four backend databases and exclusive roles, queues, ClickHouse state, filesystem state, and stale bindings. Delete only resources whose ownership is verified; reconcile dedicated Langfuse R2 objects without deleting shared storage.
- Verify collector destination locality follows backend placement without modifying nix-fleet's separately developing agent–gateway architecture.

## Capabilities

### New Capabilities

- `llm-observability`: Placement, private ingestion, fresh-start relocation, and scoped retirement of the Langfuse/Latitude backend stacks.

### Modified Capabilities

None. Existing `feature-topology`, `policy-service-catalog`, `secrets-management`, and `postgres-shared-access` conventions remain applicable. `phoenix-otel-collector` describes a different service and is not rewritten into a specification for these backends.

## Impact

Host contributors/fragments, `policy/web-services.nix`, backend port wiring, `.sops.yaml`, OIDC templates/provider bindings, placement/secret-scope contract tests, and architecture/runbook documentation. Live operations create fresh target services and retire only backend-owned source resources.

Constraints: no dump/restore, queue drain, filesystem transfer, or retained-state rollback programme; stop old writers before exposing the fresh services; validate forge before deleting source resources. Agents do not decrypt or edit secrets. The edge remains on OCI. Bifrost placement, nix-fleet pins/source, Hindsight worker toggle and queue are out of scope; Hindsight trace enablement resumes separately.

