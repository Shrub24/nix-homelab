# Research: OpenLIT self-host evaluation (co-tenant with langfuse on oci-melb-1)

## Summary

OpenLIT is viable to deploy alongside langfuse on oci-melb-1 sharing the existing native ClickHouse.
Verified against `docker-compose.yml`, `assets/clickhouse-init.sh`, `src/otlp-receiver/internal/{config/config.go,chschema/schema.go}`, `src/client/prisma/schema.prisma`, `docs/latest/openlit/{installation,multiple-db,otlp-receiver}.mdx`, and the GHCR manifest (all fetched 2026-09-25 at release `openlit-2.1.0`).

## Facts

| Question | Answer (verified) |
|---|---|
| Components | One container: `ghcr.io/openlit/openlit` — dashboard/API **plus first-party OTLP receiver** (4317 gRPC / 4318 HTTP built in). No separate collector (`installation.mdx`, compose has no otelcol service). |
| Datastores | Telemetry in ClickHouse (database `openlit` by default, `INIT_DB_DATABASE`); app metadata (orgs/projects/prompt hub/vault/evals) in **SQLite** (`SQLITE_DATABASE_URL=file:/app/client/data/data.db`, prisma `provider = "sqlite"`). No MySQL/Postgres. |
| External ClickHouse | Explicitly supported: point `INIT_DB_HOST/PORT/DATABASE/USERNAME/PASSWORD` at it (`installation.mdx` "Already have ClickHouse?" + multiple-db doc). The receiver itself ensures the `otel_*` schema (`chschema.Ensure` → `CREATE TABLE IF NOT EXISTS`), tolerating a user without CREATE rights if tables already exist. |
| Co-tenancy | All tables live inside the configured database (`otel_traces/logs/metrics_*`, `openlit_controller_*`) — no cluster-global objects; co-exists with langfuse's `default`-database use. |
| Auth | UI: seeded local user (defaults in seed), OAuth via Google/GitHub env only (no generic OIDC in OSS docs). OTLP: `OTLP_REQUIRE_API_KEY` (default false) + API-key tenant routing when enabled (`config.go:31`, `otlp-receiver.mdx:54`). |
| Ports | UI/API 3000 (collides with langfuse-web on our host → override, e.g. 3100); 4317/4318 free. |
| ARM64 | Yes — `linux/arm64` digest `sha256:8fc54c10…` in the `latest` manifest; `2.1.0` tag exists (digest `sha256:94552ccd…`) → Renovate-pinnable. |
| License | Apache-2.0, all documented features free to self-host, no license key (`installation.mdx` FAQ). |
| Versioning | Server releases tagged `openlit-<semver>`; current 2.1.0 (2026-09-10). |

## Fleet-shape implications (as deployed in the A/B)

- Deployed as the `openlit` placement aspect (`modules/observability/openlit.nix`), selected on oci-melb-1 next to langfuse; image pinned `2.1.0` + digest in `policy/oci-images.nix`.
- Zero secrets: UI auth is the seeded local user (Access-gated route `openlit.shrublab.xyz`, category `app`); OTLP requires UI-minted API keys (`OTLP_REQUIRE_API_KEY=true`); the ClickHouse `openlit` user is passwordless and loopback-only, added to langfuse's existing `users.d` fragment — no sops template, no substitution include.
- The receiver creates `otel_*` tables but not the database; a `openlit-db-init` oneshot runs `CREATE DATABASE IF NOT EXISTS openlit` after clickhouse.service.
- UI on 3100 (`HOSTNAME=127.0.0.1` so the seeded-auth UI never binds the tailnet); OTLP 4317/4318 on all interfaces — firewall keeps them tailnet-only, exporters dial `http://oci-melb-1:4318` with a key.
- State: `/srv/data/openlit/data` (SQLite); backup via `sqlite3 .backup` export, matching the docs-mcp pattern.

## A/B assessment

- No port, datastore, or OTLP-endpoint conflicts with langfuse (4318 vs langfuse's 3000/api/public/otel).
- Cost: one node server (~200–400 MB RAM) + CH co-tenancy; no S3 needed (langfuse needs R2, openlit doesn't).
- Risk: young platform (2.x line), SQLite metadata is fine for a trial; SDK surface is OTel-native so both accept the same exporter families.

## Sources

- docker-compose.yml, assets/clickhouse-init.sh, env.example (repo root, openlit-2.1.0)
- src/otlp-receiver/internal/config/config.go:31-39, internal/chschema/schema.go:16-43,110-146
- src/client/prisma/schema.prisma:2-7
- docs/latest/openlit/installation.mdx, developer-resources/multiple-db.mdx, otlp-receiver.mdx
- GHCR manifest for ghcr.io/openlit/openlit (latest + 2.1.0)
