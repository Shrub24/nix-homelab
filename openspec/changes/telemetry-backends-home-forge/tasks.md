# Tasks

## 1. Placement, ports, and contracts

- [x] 1.1 Move `langfuse`/`latitude` selections and service bindings between `modules/hosts/{oci-melb-1,home-forge}/{default,_nixos}.nix`; keep both PostgreSQL instances and unrelated consumers unchanged. Update scaffold placement/consumer pins in the same task; verify structured host evals put both stacks on forge only and retain Paperless/Hindsight/AudioMuse consumers on their original clusters.
- [x] 1.2 Move the four backend route providers in `policy/web-services.nix` to home-forge, declare Langfuse origin 3030 and derive its listener from the catalog in `modules/observability/langfuse/service.nix`. Update route/port tests and architecture docs; verify policy/catalog checks, rendered listener/collector ports, stable public identities and Access settings, with Grafana still on 3000.

## 2. Scoped secrets and fresh-instance credentials

- [x] 2.1 Update `.sops.yaml` and `tests/fixtures/secret-scope.nix` for forge's backend/exporter service readership, retaining OCI only until retirement or where a current consumer requires it. Document operator-owned rewrap and verify `tests/check-secret-scope.sh`; never edit ciphertext.
- [x] 2.2 Move Langfuse's OIDC host binding and provider source map to forge's OIDC file; move its entry between host templates and update identity/scaffold pins. Document operator-only copying of the reusable key into the populated target file; verify provider/consumer paths agree, future templates render, and unrelated host client keys are unaffected.
- [ ] 2.3 Operator rewraps service files and prepares forge's Langfuse OIDC key; verify required cleartext key names and recipient metadata without logging values. Document Langfuse's existing fresh seed and Latitude's account/project recreation plus replacement `latitude/api_key`; verify the seed env surface and establish a temporary Latitude-exporter inhibit until the new key is ready.

## 3. Cutover readiness and gates

- [ ] 3.1 Write `docs/runbooks/telemetry-backend-migration.md` for fresh initialization, source-write pause, target validation, operator credential bootstrap, and exact cleanup. Inventory the four source databases, role dependencies, ClickHouse consumers, queue/filesystem/container resources and dedicated R2 objects; verify deletion targets exclude shared resources and target objects. No dump/restore, queue drain, state copy or retained-state rollback programme.
- [ ] 3.2 Recheck target capacity, reserved ports including 3030, pinned image architecture support, and existing target directories/database names; verify fresh initialization will not overwrite unrelated state. Parent formats/stages the settled tree, runs focused placement/identity/secret checks, `just checks all` and `nix flake check`; verify all pass without editing under running gates or changing nix-fleet.
      **Partial (2026-10-04):** the scaffold contract and `just checks all` now pass on the
      settled tree. Its pins had to move with the placement: container counts
      (`oci-melb-1` 13 → 4, `home-forge` 8 → 16), the three notify-registration maps, and the
      registered-unit lists (oci gains `bifrost`; all three gain nix-fleet's `vmagent`; the
      `opentelemetry-collector` registration is oci's alone because it is the only host that
      runs a collector). `nix flake check --no-build` is unusable on this tree for an unrelated
      reason — degoog's eval-time `bun.nix` IFD, which the relock invalidated — recorded on
      `voyage-embedding-compatibility` task 6.1.

## 4. Fresh initialization and acceptance

- [ ] 4.1 Pause old backend ingest/application writers and initialize forge's backend substrate/apps through existing service wiring, with Latitude export inhibited. Verify PostgreSQL schemas, fresh Temporal setup, ClickHouse/Redis readiness, Langfuse seed and local health; do not route traffic to an unhealthy target or delete source resources yet.
      **Note (2026-10-04):** the oci deploy that landed the Bifrost runtime swap (generation 315)
      also activated this change's source side, because the relocation was already applied in the
      staged tree: oci's `langfuse-*`/`latitude-*` units and their secret bindings are gone and
      their containers stopped. The source databases, volumes and R2 objects remain for task 5.1.
      Forge is not yet deployed, so the backends currently serve nowhere — forge initialization
      is the step that brings them back, and Latitude's account/project plus ingest key still
      have to be recreated by the operator.
- [ ] 4.2 Activate OCI edge route changes and la-admin-1's OIDC source binding; verify stable public URLs, Langfuse SSO and Latitude login. Operator recreates Latitude's account/project and fills its newly issued ingest key; verify key presence without reading its value, enable the exporter, and prove a fresh trace in both backends.
- [ ] 4.3 Verify collector destination locality, expected auth behavior and running configuration; remove temporary bootstrap inhibits and inspect collector failures. Check Grafana, Paperless, Hindsight/AudioMuse health and Hindsight's worker-off state; record target acceptance before destructive source cleanup.
  - Superseded transport (2026-10-09, D-083): the LLM-observability legs are no longer derived from the general route. The collector now runs two routes on `home-forge` — the general ingress exports to the trace store alone, and `routes.ai` carries AI sessions to VictoriaTraces, Langfuse and Latitude. Verify acceptance on the **AI route** (`home-forge:4319`), and note that producer enrolment (Pi's relay, Bifrost) is tracked in `telemetry-ai-route-isolation`; the destination-scoped settings above (project header, `compression = "none"`) already carry onto the route-scoped exporters.
  - Enrollment repair (2026-10-08): the deployed `latitude.api_keys` schema has organization binding but no project binding. Add `X-Latitude-Project: shrublab` to the gateway exporter for unscoped spans. The running header was confirmed. Direct synthetic JSON and uncompressed protobuf spans both returned HTTP 200; the same protobuf payload with gzip returned HTTP 400 `failed to decode OTLP message`. Disable compression on the Latitude exporter (`compression = "none"`); activation and real producer receipt remain pending. Langfuse had authenticated but event-object uploads failed with S3 `AccessDenied`, producing HTTP 500; the latest collector check showed no Langfuse failures, but backend receipt remains unverified.

## 5. Source retirement

- [ ] 5.1 Remove obsolete OCI backend runtime resources and execute the runbook's verified cleanup inventory: four backend PostgreSQL databases, dependency-free exclusive roles, backend Redis/filesystem/container state, and ClickHouse state only at its proven ownership boundary. Remove obsolete source-owned R2 objects only where they can be distinguished from target/shared objects; verify exact retired resources are absent and unrelated services remain healthy. Record deletions; no broad prune, cluster removal or shared-storage purge.
  - Databases and exclusive roles are done (2026-10-05): `langfuse`, `latitude`, `temporal`, `temporal_visibility` and the roles `langfuse`, `latitude` were dropped from oci-melb-1's cluster, with insurance dumps of the three dumpable databases and a schema-only dump of `latitude` left in `/srv/data/postgres-leftovers/` (deleted 2026-10-06 once the drops held: 12 GB of a 26 GB volume, superseded by the cluster's own export in the R2 backups). This was not cosmetic — the export contract runs `pg_dumpall --clean --if-exists -w` with `backupAll = true`, and `latitude`'s `vector` objects could not be dumped once pgvector left the cluster with its consumer, so the failed unit rolled back every activation (two deploys lost). Remaining: Redis/filesystem/container state, ClickHouse, and source-owned R2 objects.
  - The dead `litellm` and `audiomuse` databases on the same cluster were dropped in the same pass (2026-10-05), so nothing in this cluster is left over from the retired backends.
- [ ] 5.2 Remove stale source bindings/docs/test assumptions and unnecessary secret readership; operator removes obsolete OIDC keys and rewraps affected files. Verify scope/identity/placement checks and live unrelated-service health, record final deployment/cleanup evidence, and reconcile the paused Hindsight change's placement assumptions without enabling traces or deleting its jobs here.

