# Research: Latitude self-host evaluation (candidate alongside langfuse on oci-melb-1)

## Summary

**Latitude is a real self-hostable OSS platform with full `linux/arm64` coverage on every image in its stack, but it is the heaviest candidate in this gauntlet and it is not the product the operator remembers.** `latitude-dev/latitude-llm` (MIT, no rename; site `latitude.so`, docs `docs.latitude.so`) is now **Latitude V2 — "observability and signal discovery for agents"**, and V2 **removed the prompt manager, PromptL, the AI gateway, and the playground**: prompts live in your codebase and are versioned by Git (`migrate-from-v1.md`, fetched). The self-host stack is 6 application images plus **Postgres+pgvector, ClickHouse, 2× Redis, Temporal and SeaweedFS** (11–12 containers), the UI defaults to **port 3000 (collides with langfuse)**, ingest is **OTLP/HTTP only at `:3002/v1/traces` with `Bearer` + project header/slug** (no gRPC listener), and login is **magic-link email, so a working SMTP transport is mandatory**. Verified 2026-09-26 against `development` (latest commit `93f0733d`, 2026-09-23), app images `0.3.118`, `CHANGELOG.md` `v0.3.118`, `docker-stack.yml`, `.env.example`, Helm `charts/latitude/values.yaml`, `apps/ingest/src/**`, `docker/init-db.sh`, goose migration scripts, and `skopeo inspect --raw` manifest reads.

## 1. Identity

| Question | Answer | Support |
|---|---|---|
| Exact repo | `github.com/latitude-dev/latitude-llm` — **no rename**; `curl -o /dev/null` returns `200` with no redirect; the name is current | direct evidence (GH API + HTTP HEAD) |
| Site / docs | `https://latitude.so`, `https://docs.latitude.so` (index at `/llms.txt`); Docker Hub org `hub.docker.com/u/latitudedata`; Slack community; `status.latitude.so` | direct evidence |
| License | **MIT** (`license.spdx_id = MIT`) — no license key, no feature-license enforcement | direct evidence (GH API) |
| Stars / forks / issues | 4685 stars, 394 forks, 71 open issues (GH API, 2026-09-26). A search-index snapshot minutes earlier said 4631/387 — treat the API numbers as current | direct evidence |
| Activity | `pushed_at 2026-09-25T13:26:54Z`; latest commit on default branch `development`: `93f0733d` 2026-09-23 `docs: add the Agent Score guide (#4720)`; **≥200 commits since 2026-08-26** (commits pagination `last=200` with `per_page=1`); ~41 contributor pages | direct evidence |
| Default branch | `development` (not `main`) — fetch raw files against `development` | direct evidence |
| Created | 2024-06-28 — ~2.2 years old, but V2 is new (see §6) | direct evidence |
| Releases | **No server releases.** GitHub releases are only CLI/SDK tags: `cli-7.16.0` (2026-09-23), `typescript-sdk-9.15.0`, `python-sdk-9.14.0`. The server version lives in Docker Hub tags (`0.3.118`, 2026-09-23) and `CHANGELOG.md` | direct evidence |
| Maturity posture | Monorepo with 6 apps + Helm chart + Railway template; SOC2/ISO27001/GDPR marketing pages; **very high velocity, product under active re-positioning (V1→V2)** | evidence (structure) + interpretation (posture) |

## 2. Self-host story

**Official paths** (`deployment/single-host.md`, `.md` versions fetched): single-host via `docker-stack.yml` + a single `.env.production`; cluster via the Helm chart `charts/latitude`; one-click Railway. The self-host docs explicitly name Docker Hub: "It uses the published Docker images (https://hub.docker.com/u/latitudedata)".

**Images in the official stack** (`docker-stack.yml`, `development`):

| Container | Image | Role |
|---|---|---|
| `web` | `latitudedata/web:${LAT_IMAGE_TAG:-latest}` | UI, binds 3000 |
| `api` | `latitudedata/api:${LAT_IMAGE_TAG:-latest}` | Public API + MCP, binds 3001 |
| `ingest` | `latitudedata/ingest:${LAT_IMAGE_TAG:-latest}` | OTLP ingest, binds 3002 |
| `workers` | `latitudedata/workers:${LAT_IMAGE_TAG:-latest}` | BullMQ jobs, health 9090 (internal) |
| `workflows` | `latitudedata/workflows:${LAT_IMAGE_TAG:-latest}` | Temporal workers, health 9091 (internal) |
| `migrations` | `latitudedata/migrations:${LAT_IMAGE_TAG:-latest}` | one-shot Postgres+ClickHouse migrations |
| `postgres` | `pgvector/pgvector:pg16` | OLTP + pgvector, `wal_level=logical` |
| `clickhouse` | `clickhouse/clickhouse-server:26.2` | span/telemetry OLAP |
| `redis` | `redis:7` | cache |
| `redis-bullmq` | `redis:7` (`--appendonly yes --maxmemory-policy noeviction`) | durable queue |
| `temporal` | `temporalio/auto-setup:1.27.2` | workflow engine, Postgres-backed |
| `seaweedfs` | `chrislusf/seaweedfs:4.32` | S3 gateway on 8333 |

**ARM64 — verified with `skopeo inspect --raw` (not inferred from docs).** All app images are OCI indexes with `linux/arm64`:

| Image | arm64 | amd64 | latest arm64 manifest digest |
|---|---|---|---|
| `latitudedata/web` | yes | yes | `sha256:b02944106c3b…` |
| `latitudedata/api` | yes | yes | `sha256:d74f1bf41318…` |
| `latitudedata/ingest` | yes | yes | `sha256:06a677de314e…` |
| `latitudedata/workers` | yes | yes | `sha256:019d9621f938…` |
| `latitudedata/workflows` | yes | yes | `sha256:01378f6b3c1e…` |
| `latitudedata/migrations` | yes | yes | `sha256:5783a531fbcb…` |
| `pgvector/pgvector:pg16` | yes | yes | — |
| `clickhouse/clickhouse-server:26.2` | yes | yes | — |
| `redis:7` | yes (`arm64/v8`) | yes | — |
| `temporalio/auto-setup:1.27.2` | yes | yes | — |
| `temporalio/server:1.27.2` (Helm) | yes | yes | — |
| `temporalio/admin-tools:1.27` (Helm) | yes | yes | — |
| `chrislusf/seaweedfs:4.32` | yes | yes | — |

The same `linux/arm64` platform entry is present at the **pinned tag `0.3.118`** for all six `latitudedata/*` images. So ARM64 is a **yes across the entire stack**, not a docs claim.

**Pinnability for Renovate:** clean. `docker-stack.yml` interpolates one variable into all six app images (`LAT_IMAGE_TAG`), and the docs say "To pin a specific release instead of `latest`, set `LAT_IMAGE_TAG=X.Y.Z` (image tags have no leading `v`)". Infra images carry explicit tags (`pg16`, `26.2`, `7`, `1.27.2`, `4.32`). Tag `development` also exists — avoid it. Current release `0.3.118` (2026-09-23); Docker Hub shows near-daily bumps (0.3.106…0.3.118 within ~5 days).

**Footnote:** `ghcr.io/latitude-dev/web:latest` also exists (skopeo found it), which reconciles the older doc text that mentions "our GitHub Container Registry", but the official compose/guide uses Docker Hub. See Contradictions.

**Rough resource footprint.** Docker Hub compressed sizes for the app images: web 563 MB, api 473 MB, ingest 470 MB, workers 477 MB, workflows **726 MB**, migrations **807 MB** → **~3.5 GB compressed**, and workflows/migrations unpack much larger. `charts/latitude/values.yaml` gives the only published sizing: requests of **250m CPU / 512Mi** each for `web`, `api`, `ingest`; **500m / 1Gi** each for `workers`, `workflows` → **≈1.75 vCPU and ≈3.25 GiB of requests for the app services alone**, before migrations, Postgres, ClickHouse, 2 Redis, Temporal and object storage. (Values are *requests*, not limits; no benchmark numbers are published anywhere I fetched.) *Interpretation:* adding this to oci-melb-1 alongside langfuse + native ClickHouse + openlit makes Latitude the heaviest candidate so far and puts it in tension with the "low-complexity, recovery-simple first host" constraint.

## 3. Stateful dependencies

| Dependency | Required or degradable | Evidence |
|---|---|---|
| **Postgres + pgvector** | **Required, not degradable.** Primary OLTP store; needs the `vector` extension, a schema-create admin role, `wal_level=logical`, and a *second* restricted runtime user subject to RLS | `docker-stack.yml` (`pgvector/pgvector:pg16`, `postgres -c wal_level=logical`, BYO comment: "needs the `vector` extension + a schema-create admin"); `docker/init-db.sh` creates `${POSTGRES_RUNTIME_USER}` and grants CONNECT; `.env.example` documents `LAT_DATABASE_URL` (RLS runtime) vs `LAT_ADMIN_DATABASE_URL` (superuser, bypasses RLS) |
| **ClickHouse** | **Required.** `LAT_CLICKHOUSE_URL` (HTTP 8123), `LAT_CLICKHOUSE_MIGRATION_URL` (native 9000, goose), `LAT_CLICKHOUSE_DB` = a **dedicated database**; `LAT_CLICKHOUSE_CLUSTER_ENABLED` for clustered DDL | `.env.example`; `deployment/configuration.md`; `packages/platform/db-clickhouse/clickhouse/scripts/up.sh` builds `clickhouse://user:pass@host:port/${LAT_CLICKHOUSE_DB}` |
| **Redis (cache)** | Required (locks, rate limiters, budgets) | `docker-stack.yml` |
| **Redis (BullMQ queue)** | Required, and needs `appendonly yes` + `maxmemory-policy noeviction` | `docker-stack.yml` (`redis-bullmq` command) |
| **Temporal** | Required. Bundled `auto-setup` is Postgres-backed and creates `temporal` + `temporal_visibility`; Temporal Cloud is the recommended BYO | `docker-stack.yml` temporal block; `charts/latitude/values.yaml` comments |
| **Object storage** | Degradable: SeaweedFS (S3 on 8333) **or** any S3-compatible store **or** `LAT_STORAGE_DRIVER=fs` on a path shared by every service | `.env.example`; `deployment/configuration.md` §Object storage |
| **Email transport** | **Required for login** (magic link). "A working email transport is required for anyone to log in… production is not bundled with an email service" — Mailgun, SendGrid, SMTP, or Mailpit (dev) | `deployment/configuration.md` §Email; `.env.example` |
| **External AI provider** | Optional: "The stack boots and core observability (ingest + trace viewing) works without API keys. AI-dependent features stay disabled until you add credentials" — Generation (Bedrock default), Embeddings (Voyage default), Reranking (Voyage/Bedrock). An OpenAI-compatible custom endpoint (Ollama/vLLM/…) is supported for generation **and** embeddings | `deployment/single-host.md` §AI features; `.env.example` |

**Shared-instance / co-tenancy support is a documented feature.** `deployment/single-host.md` §"Bring your own infrastructure": "Each infra service in `docker-stack.yml` is a clearly-marked, independently removable block… Repoint: Postgres `LAT_DATABASE_*`/`LAT_ADMIN_DATABASE_*`; ClickHouse `LAT_CLICKHOUSE_*` — **Dedicated `LAT_CLICKHOUSE_DB` database**; Redis (cache/queue) `LAT_REDIS_*`/`LAT_BULLMQ_*` — **Latitude namespaces all keys under `latitude:`**; Temporal `LAT_TEMPORAL_*`; Object storage `LAT_STORAGE_*`." Helm mirrors this: "Every bundled infrastructure dependency (postgres, clickhouse, redis, redisBullmq, seaweedfs, temporal) is an independent toggle".

Schema isolation: ClickHouse DDL is unqualified (`CREATE TABLE IF NOT EXISTS spans` in `migrations/unclustered/00001_create_spans.sql`) and goose connects to `${LAT_CLICKHOUSE_DB}`, so everything lands inside one named database — co-tenant-friendly. **Inference (unverified):** the database must be pre-created; no `CREATE DATABASE` appears in the migration SQL or the fetched scripts, and `LAT_CLICKHOUSE_DB` is described as the app's connection "database", so a `db-init` step (or manual `CREATE DATABASE IF NOT EXISTS latitude`) is likely required, exactly as openlit needs. Postgres is less isolated: `docker/init-db.sh` creates a database-level runtime user, and the migration tool is documented to need a schema-create admin, so Postgres co-tenancy means a dedicated database *plus* an extension install and two roles in the shared cluster.

## 4. Ports, ingest, auth surface

**Ingest is OTLP/HTTP-native — but HTTP only, and traces only.**

- Route surface (direct evidence, `apps/ingest/src/routes/index.ts`): `health` + **only** `traces`. There is exactly one ingest route, registered as `app.post("/v1/traces", …)` (`routes/traces.ts`). There is **no `/v1/logs` and no `/v1/metrics`** route, and no gRPC server: `server.ts` starts a single Hono/node HTTP server on `LAT_INGEST_PORT` (default 3002) with `@hono/otel` middleware. No `grpc`/`4317` listener appears in the ingest app or compose.
- Contract (docs `telemetry/otel-exporter.md`, fetched): `POST https://ingest.<host>/v1/traces`, `Authorization: Bearer <api-key>`, `X-Latitude-Project: <project-slug>`, `Content-Type: application/json | application/x-protobuf`, body = standard OTLP `ExportTraceServiceRequest`.
- Auth model (direct evidence, `apps/ingest/src/middleware/auth.ts`): `Authorization` **must** start with `Bearer ` else `401`; the key is validated against Postgres+Redis (`validateApiKey`, org/API-key scoped).
- Project routing (direct evidence, `middleware/project.ts`): `X-Latitude-Project` is **optional** — when absent, each span must carry a `latitude.project` attribute on the span or its OTEL resource, otherwise spans are `400`-rejected or counted as `partial_success` rejections. This means a plain OTLP exporter with one resource attribute works; it is not a strictly header-only endpoint.
- Response semantics (direct evidence, code comments in `routes/traces.ts`): all-valid → **200 OK** empty `ExportTraceServiceResponse`; mixed → 200 + `partialSuccess`; empty batch → **202**; all rejected → **400** with a `google.rpc.Status`-shaped body. **The docs say "returns 202 on success" — doc drift (see Contradictions).**
- Payload guards: 32 MiB max body (`LAT_INGEST_TRACE_MAX_PAYLOAD_BYTES`), 64 MiB in-flight budget, 16 concurrent payloads (`deployment/configuration.md`).
- SDKs, for completeness: `@latitude-data/telemetry` (TS) and `latitude-telemetry` (Python) exist, plus framework/provider instrumentation pages for ~40 stacks. **SDK-only is not the situation** — any OTel SDK can point at `/v1/traces`; the docs show Go/Java/etc. `otlptracehttp` examples with the custom endpoint + headers.

**Port map vs the taken set `{3000, 3100, 4317/4318, 5667, 6280, 7280, 7281, 7411, 8000, 8001, 8002}`:**

| Latitude surface | Default | Verdict |
|---|---|---|
| `web` UI | **3000** | **COLLIDES with langfuse-web.** Must be remapped (3100 is taken by openlit → pick e.g. 3110). Both `LAT_WEB_PORT` and `LAT_WEB_URL` must agree |
| `api` (+ MCP at `/v1/mcp`) | 3001 | free (nearest taken value is 3000) |
| `ingest` (OTLP/HTTP) | 3002 | free |
| `workers` health | 9090 | not published in `docker-stack.yml`; internal only |
| `workflows` health | 9091 | not published; internal only |
| bundled Postgres / ClickHouse / Redis / SeaweedFS ports | 5432 / 8123+9000 / 6379 / 8333 | **not published** in `docker-stack.yml` (the root `docker-compose.yml` dev file does publish them); omit those blocks when co-tenanting |
| Temporal | 7233 | not published in `docker-stack.yml` (published only in the dev compose) |

`docker-stack.yml` publishes **only** 3000/3001/3002 over plain HTTP; the docs tell you to put a TLS-terminating reverse proxy in front and to keep the three public URLs and origin allowlists (`LAT_TRUSTED_ORIGINS`, `LAT_CORS_ALLOWED_ORIGINS`) consistent, else "browser calls to the API are rejected and sign-in fails".

## 5. Auth (human sign-in vs the outer wall)

- **Sign-in is Better Auth with email magic links by default** ("By default users sign in with email magic links"). The single-host guide's last step: "Open the web UI (at your `LAT_WEB_URL`) and register. Latitude sends a magic link through the email transport you configured; click it to finish signing in and create your organization." Secrets: `LAT_BETTER_AUTH_SECRET` signs sessions and magic-link tokens.
- **Social login**: Google (`LAT_GOOGLE_*`) and GitHub (`LAT_GITHUB_*`) env vars. Domain restriction `LAT_ALLOWED_EMAIL_DOMAIN` exists but `.env.example` comments label it "staging only".
- **Generic OIDC/SAML SSO exists in the code but is an enterprise-gated path, not a documented OSS feature.** Evidence: `packages/domain/sso/src/entities/sso-provider.ts` models `saml | oidc` providers with an `issuer`, `domain`, `enforced`; migration `20260609091525_add-sso-providers/migration.sql` creates `latitude.sso_providers` with `oidc_config`/`saml_config`; the settings page `.../settings/sso.tsx` is titled "Single sign-on — Let your team sign in to Latitude through your identity provider (SAML or OIDC)" **but is wrapped in `useHasFeatureFlag("sso")` and renders an upsell card (`mailto:sales…?subject=Latitude%20Enterprise%20SSO`) when the flag is off**; the registry entry is `sso: { name: "Enterprise SSO" }` and flags are "enabled only when an explicit row in `feature_flags` (with `enabled_for_all = true`) or `organization_feature_flags` exists". **Interpretation:** a Kanidm OIDC connection is *reachable* — MIT code, complete schema, complete UI — but only by seeding a DB row (backoffice or SQL), i.e. an unsupported, upgrade-fragile configuration, not a supported self-host setting.
- **MCP clients** authenticate through OAuth against the web origin (`api` publishes `/.well-known/oauth-protected-resource`, RFC 9728; the authorization server is the web app's Better Auth `mcp` plugin). No API key on the MCP URL (401 by design).
- **Outer wall implication:** the docs describe first-user **self-registration** as the normal path, and I found **no documented self-host switch to disable public sign-up** (only the staging-labelled domain restriction). *Inference, not stated by any source:* on an Access-gated route that is fine, but the gate is load-bearing — an unauthenticated visitor who reaches the UI and completes a magic link creates an organization. Given the three separate surfaces (web/API/ingest), an Access-gated route per surface (or path routing with exactly matching `LAT_*_URL` values) is required, and **ingest cannot sit behind an interactive Access gate** for machine exporters — it would need a service token or network-level restriction to the tailnet, the same shape as our openlit OTLP exposure.

## 6. Feature axis vs Langfuse

**Test of the operator's hunch ("equally if not more interesting", prompt management as Latitude's strength): the prompt-management premise is false as of V2.** Direct evidence, `getting-started/migrate-from-v1.md` (fetched): "**Latitude V1 was a prompt engineering platform.** You wrote prompts in PromptL, published them, and your app called them through the Latitude gateway. **Latitude V2 is an observability and signal-discovery platform for agents you run yourself.**" The V1→V2 table states: prompts live "**Your codebase and your version control**"; version control becomes "Git, plus `metadata.prompt_version` and a release tag on every trace"; the playground becomes "Your local dev loop, plus a Sandbox project"; the AI gateway / `prompts.run()` / `prompts.chat()` are "**Removed. Nothing on the Latitude side replaces them**"; prompt suggestions become agent dispatch; batch evaluation over a dataset inside Latitude becomes local replay ("Your runner, your CI"). The V1 product "keeps running for existing customers, but new features ship only to V2". The repo-wide code search for prompt-management/playground code in `apps/web` returned no hits, and the docs index contains no prompt-manager pages.

| Axis | Latitude V2 | Support |
|---|---|---|
| Prompt management / versioning / playground | **Absent in V2** (V1-only legacy). This is the opposite of a Latitude strength for a new deployment | direct evidence (`migrate-from-v1.md`) |
| Traces / observability depth | **Strong and agent-shaped**: spans / traces / sessions / users / tools / memory; per-session detail; filters; semantic **Search**; **Behaviors**; **percentile cohorts** (duration, TTFT, cost, tokens vs similar tag sets); duration/log-level/environment/release metadata views; sampling notes; **Sandbox** projects for dev/staging traffic; Agent Score (one 0–100 score from 5 dimensions) | direct evidence (`llms.txt` page list + `observability/*` index entries) |
| Evaluations | **Strong, signal-centric**: signals are the unit; detection via condition sets, an LLM judge, or a **custom JavaScript detector**; evaluation triggers + sampling (default 10% for judge signals per the migration doc); **evaluation alignment** (agreement with human annotations); **flaggers** (built-in auto-annotators for frustration, refusal, jailbreaking, tool errors, empty responses) | direct evidence |
| Datasets | Present: input/output/expectedOutput/metadata/custom columns; add traces from list/search/signal; edit rows via API/SDK/MCP; **replay happens locally** (simulations + regression tests in your CI), not as a hosted batch-eval runner | direct evidence |
| Dashboards / experiments | **Experiments** = compare two or more *traffic slices* with every metric; score analytics; **Cost** view (cost per session, cache economics); Agent Score dashboard — **but Cost dashboard, Agent Score and custom behaviors are behind feature flags** (`costDashboard`, `agentScore`, `customBehaviors` in `packages/domain/feature-flags/src/registry.ts`), i.e. enabled by DB rows, not on by default | direct evidence |
| Cost tracking | Yes, as a first-class view — flag-gated, and it needs priced model references (a CHANGELOG entry notes Agent Score withholding dimensions for "unreferenced" models such as `gpt-5-mini`) | direct evidence |
| Collaboration / workflow | Annotations (human-in-the-loop), saved searches, monitors + Slack notifications, agent **dispatch** to Cursor / Claude Code / Linear / webhooks, MCP server + CLI, GitHub integration (auto-resolve a signal on PR merge), PostHog data destination, partner embedding | direct evidence |
| What it optimizes for | **Finding, tracking and fixing agent failures at scale** — signal discovery, semantic search, agent dispatch, self-healing loop. The repo description is now "Open-source observability for AI agents. Find where your agents fail, dispatch your coding agent to fix it, and verify the fix against real traces." | direct evidence + interpretation |
| Cloud-only / licensed-ish | Enterprise SSO (flag + sales email); `LAT_BILLING_ENABLED` credit plans (off for self-host, "ingestion is never capped"); Jev flagger pre-classifier needs a Typesafe API key; data destinations/partners; and **the differentiated AI features need external provider credentials** (Bedrock/Voyage/OpenAI/Google, or a custom OpenAI-compatible endpoint) | direct evidence |

**Additional self-host constraint that shapes the feature verdict (direct evidence, `.env.example`):** embeddings are global, must emit **2048-dimensional** vectors — the dimension is "hard-coded into the ClickHouse `message_embeddings` CHECK + HNSW index", switching dimensions requires a migration, and Latitude never re-embeds existing data. Embedding providers are `voyage | openai | google | custom`. *Interpretation:* a no-egress homelab deployment must run a local OpenAI-compatible embedding model with exactly 2048 dims, or accept sending trace-derived text to a third party; without it, semantic search, highlights and signal clustering stay off.

**Verdict (interpretation).** Latitude V2 is *not* "Langfuse plus prompt management"; it is an **agent-failure triage console**. Against Langfuse on the overlapping surface (traces, evals, datasets, cost) Langfuse remains broader (prompts, prompt versioning, logs, metrics, dashboards, self-host maturity). Latitude's marginal value is the signal/flaggers/agent-dispatch/agent-score workflow, which is genuinely different — but that value is realised for teams running many agent sessions they want triaged, and it depends on external LLM/embedding credentials. The operator's hunch is **half right: equally interesting, but on the agent-triage axis, not the prompt-management one.**

## 7. Migration shape on oci-melb-1 (NixOS + Podman aspect)

**Containers.** Up to **12**: `web`, `api`, `ingest`, `workers`, `workflows`, `migrations` (one-shot), plus Postgres(pgvector), ClickHouse, 2× Redis, Temporal, SeaweedFS. Reducible: drop bundled ClickHouse (co-tenant the native one in a dedicated `latitude` database), drop SeaweedFS (`LAT_STORAGE_DRIVER=fs` on a shared `/srv/data/latitude/storage` path), drop bundled Postgres only if a pgvector-capable cluster exists. Temporal is **not** reducible without an external Temporal. The second Redis likely is **not** shared with an eviction-tuned cache instance because BullMQ requires `appendonly yes` + `noeviction` (*inference*; docs only claim key namespacing under `latitude:`, which makes *one* shared policy-compatible Redis viable).

**Secrets (sops) — realistic minimum if co-tenanting ClickHouse and using the `fs` storage driver:** `LAT_MASTER_ENCRYPTION_KEY` (AES-256-GCM key for stored provider credentials/integration tokens), `LAT_BETTER_AUTH_SECRET` (session + magic-link signing), Postgres admin + runtime passwords, one Postgres/Temporal credential set (auto-setup reads `${POSTGRES_USER}/${POSTGRES_PASSWORD}`), email transport credentials (SMTP/SendGrid/Mailgun), and optionally an AI provider key + OAuth client pairs + S3 keys if not using `fs`. **≈6–8 secrets** versus Laminar's ~5 and openlit's 0. Docs: "Latitude needs two secrets, generated uniquely per deployment" + "remember to change the default infrastructure passwords".

**Datastore provisioning — does it need a ClickHouse `users.d` fragment or a Postgres consumer registration?**
- *ClickHouse:* it needs a **dedicated database** and a user able to reach HTTP 8123 (app) and native 9000 (goose migrations). So the host needs (a) a `latitude` user with a password in a users.d fragment — a variant of the fragment langfuse/openlit already use, but with credentials rather than openlit's passwordless loopback user — and (b) a `latitude-db-init` oneshot (`CREATE DATABASE IF NOT EXISTS latitude`) analogous to `openlit-db-init`, since the migrations assume the database exists (*inference* — see Missing evidence). It also installs its own CH `storage.xml` with a `tiered` policy (hot/cold disks) only for the bundled container; an external CH ignores it, so the tiered-policy XML must be **skipped** — meaning the app runs without a cold-tier policy on the shared instance.
- *Postgres:* the fleet's pattern (`modules/database/postgres/_consumer.nix`, read directly) declares consumer options `database` + `role` and lets the mechanism provision "the database, role, credential, and extensions it needs". Latitude needs **two roles** (schema-create admin + RLS runtime, see `docker/init-db.sh`) **plus the `vector` extension** plus `wal_level=logical`, and Temporal needs its own two databases (`temporal`, `temporal_visibility`) with admin rights, since "auto-setup creates the `temporal` + `temporal_visibility` databases". So Latitude is **two Postgres consumers**, and whether the current consumer fragment can express "extensions" and "two roles" needs checking — I only confirmed the `database`/`role` options before time ran out (see Missing evidence). This is the single biggest structural difference from Laminar (which needs one registered DB).
- *Object storage:* `fs` driver avoids a new S3 consumer; the path must be shared by all five stateless services.

**Other host-shape notes.**
- **Port remap required**: web 3000 → a free port (3100 is openlit's, so ~3110), keeping `LAT_WEB_PORT` and `LAT_WEB_URL` in agreement; api 3001 and ingest 3002 are free; workers/workflows health ports stay internal.
- **Three surfaces to publish**: web + api + ingest, each needing its own Access-gated route or path routing with exactly matching URLs and origin allowlists. Ingest must remain reachable by exporters (tailnet/token, not an interactive gate).
- **Email transport is a hard prerequisite for the first login.** The repo's SMTP references are `modules/hosts/la-admin-1/_nixos.nix` and `modules/apps/vaultwarden.nix`; I found no SMTP relay wired on oci-melb-1. *Inference:* without an SMTP path (or a Mailpit-style sink plus manual link extraction, which is a dev-only hack), **nobody can sign in**, and the OAuth path (Google/GitHub) requires a public redirect origin — awkward behind Access.
- **Upgrades**: the `migrations` container runs on every `up` and applies Postgres **and** ClickHouse migrations before the app services start, so bumping `LAT_IMAGE_TAG` + restart is the upgrade, with no separate migration step in the aspect.
- **Existing langfuse data**: Latitude documents a Langfuse importer, but it is scoped to **"a Langfuse Cloud project"** with `pk-lf-…`/`sk-lf-…` keys and region selection — a self-hosted Langfuse base URL is not documented (see Open questions). So unlike Laminar's official dual-export bridge, **the migration path off our self-hosted langfuse is not established**.

## Open questions

1. **Can a self-hosted Langfuse be imported?** `telemetry/imports/langfuse.md` says "Import historical traces and observations from Langfuse **Cloud**" and requires region selection; no self-host base-URL option is documented. Unverified whether the importer accepts a custom endpoint.
2. **Is the ClickHouse database auto-created?** My inference is no (goose DSN includes `/LAT_CLICKHOUSE_DB`, DDL is unqualified, no `CREATE DATABASE` found in migrations/scripts). Needs an empirical run or a look at the `migrations` image entrypoint.
3. **Can the `sso` / `costDashboard` / `agentScore` feature flags be enabled on self-host** without the internal backoffice? Flags require a `feature_flags` row with `enabled_for_all = true` or a per-org row; no documented self-host procedure.
4. **Which local embedding model** can serve 2048-dim vectors through the OpenAI-compatible endpoint (the CH CHECK + HNSW index hard-code 2048)?
5. **Can our OTLP producers speak OTLP/HTTP?** Latitude has no gRPC ingest and no `/v1/logs` or `/v1/metrics`; a gRPC-only or logs/metrics-exporting producer would need reconfiguration or would 404.
6. **Does the fleet's Postgres consumer fragment express extensions and a second role?** I read only the first ~70 lines of `_consumer.nix` (options `database`, `role`); extension support is unconfirmed.
7. **Is there any SMTP relay available to oci-melb-1?** Login is impossible without one.
8. **Real RAM/CPU under load** — no published benchmarks; only Helm requests (≈3.25 GiB app requests) are evidence.
9. **Storage growth** — Latitude ingests full span payloads into both ClickHouse and object storage; the docs say payloads, datasets and exports live in object storage. On a 4-OCPU/24 GiB Free Tier host already running langfuse, this is a capacity question, not just a container-count question.

## Contradictions (recorded, not resolved)

1. **Stale self-hosting doc vs current compose.** A search-indexed snapshot of `docs.latitude.so/guides/self-hosted/production` (fetched `.md` 404s — the page appears to have moved) describes services incl. **Traefik on :80**, a **WebSocket server** at `ws.latitude.localhost`, a "Migrations daemon", "PostgreSQL database on port 5432", "Redis on port 6379", and images "stored in our GitHub Container Registry". The current `docker-stack.yml` (development, 2026-09-23) has **no Traefik, no websockets service, no published DB ports**, and uses Docker Hub `latitudedata/*`. Sources conflict; the current guide (`deployment/single-host.md`) matches the compose file, so I treated the compose file + single-host guide as authoritative and the older page as stale. Recorded, not resolved (the old page may still be live in some form).
2. **Image registry.** README: "Pull the ready-to-go container images on **Docker Hub**"; single-host doc: `hub.docker.com/u/latitudedata`; older doc: "**GitHub Container Registry**". I verified **both** exist (`docker.io/latitudedata/web:latest` and `ghcr.io/latitude-dev/web:latest` both resolve; `ghcr.io/latitude-dev/latitude-web` does not). Official path = Docker Hub.
3. **OTLP success code.** `apps/ingest/src/routes/traces.ts` documents 200 for an all-valid batch (202 only for an empty batch, 400 for all-rejected); `docs.latitude.so/telemetry/otel-exporter.md` says the endpoint "returns **202** on success". Doc drift; code treated as authoritative.
4. **Repo description drift.** GH API description (fetched) = "Open-source observability for AI agents…"; a search-index snapshot showed "Latitude is the open-source AI monitoring platform." Also the V1 self-hosting/prompt docs coexist with V2 docs in the same docs site (`llms.txt` indexes V2 only). Product identity is mid-transition.
5. **`pushed_at` vs default-branch HEAD.** `pushed_at = 2026-09-25T13:26:54Z` but the newest commit on `development` is `93f0733d` @ 2026-09-23T13:15Z → the 09-25 push was to another branch. Minor; unresolved and not decision-relevant.

## Missing evidence (claims I could not verify)

- No empirical deployment was performed; resource footprint, RAM behaviour and the ClickHouse-database-precreation question are **not** verified.
- `docs.latitude.so/guides/self-hosted/production` could not be fetched (HTTP 404 via the fetch tool); my only evidence for its content is a search-engine snapshot of the page text. The `.md` docs variant of the current guide (`deployment/single-host.md`) **was** fetched directly.
- `docker-stack.yml` links `temporal` to Postgres but I did not read the migration entrypoint of the `migrations` image, so the exact DDL-execution ordering for ClickHouse (DB creation, storage policy) is unverified.
- The fleet-side Postgres consumer fragment was only partially read (time-boxed), so "can a consumer register `vector` and two roles" is open.
- No `source_check` run was used for the ARM64 and OTLP claims; those rest on direct manifest reads (`skopeo inspect --raw`) and fetched source files, which are stronger primary evidence than a search summary.

## Sources

**Kept (fetched originals)**
- `https://github.com/latitude-dev/latitude-llm` + GH API `repos/latitude-dev/latitude-llm`, `/releases`, `/commits`, `/contents/...` — identity, license, activity, branch layout, contributor/commit counts.
- `https://raw.githubusercontent.com/latitude-dev/latitude-llm/development/docker-stack.yml` — the production single-host stack: 6 app images, infra blocks, ports, migrations dependency.
- `https://raw.githubusercontent.com/latitude-dev/latitude-llm/development/.env.example` — every env var, the two required secrets, ClickHouse/Postgres/Redis/Temporal/storage config, OAuth, AI providers, **2048-dim embedding constraint**.
- `https://raw.githubusercontent.com/latitude-dev/latitude-llm/development/docker/init-db.sh` — RLS runtime user creation.
- `https://raw.githubusercontent.com/latitude-dev/latitude-llm/development/charts/latitude/values.yaml` — resource requests, dependency toggles, infra image tags.
- `…/apps/ingest/src/server.ts`, `routes/index.ts`, `routes/traces.ts`, `middleware/auth.ts`, `middleware/project.ts` — HTTP-only single-port ingest, `/v1/traces` only, Bearer API key, optional project header, response contract.
- `…/packages/platform/db-clickhouse/clickhouse/scripts/up.sh`, `create.sh`, `migrations/unclustered/00001_create_spans.sql` — goose DSN includes `LAT_CLICKHOUSE_DB`, unqualified DDL (schema isolation).
- `…/packages/domain/feature-flags/src/registry.ts` — `sso` = "Enterprise SSO", plus `costDashboard`, `agentScore`, `customBehaviors`, and the flags-are-DB-rows rule.
- `…/packages/domain/sso/src/entities/sso-provider.ts`, `…/drizzle/20260609091525_add-sso-providers/migration.sql`, `…/routes/_authenticated/projects/$projectSlug/settings/sso.tsx` — OIDC/SAML schema exists, gated behind the flag with a sales upsell.
- `…/apps/api/src/routes/well-known.ts` — MCP OAuth protected-resource metadata (RFC 9728).
- `https://docs.latitude.so/llms.txt` — full V2 docs index (no prompt-manager pages; signals/evaluations/datasets/experiments/monitors/agent-dispatch present).
- `https://docs.latitude.so/deployment/single-host.md` — official single-host guide, container table, secrets, AI-feature gating, BYO infrastructure table, TLS/custom-domain, retention/backups, upgrade flow.
- `https://docs.latitude.so/deployment/configuration.md` — env reference: two secrets, email required for login, magic-link default, OAuth vars, ports 3000/3001/3002 + 9090/9091, retention, storage drivers.
- `https://docs.latitude.so/telemetry/otel-exporter.md` — OTLP-over-HTTP endpoint, headers, JSON/protobuf, language examples (no gRPC).
- `https://docs.latitude.so/getting-started/migrate-from-v1.md` — the decisive V1→V2 pivot: prompt manager/gateway/playground removed.
- `https://docs.latitude.so/telemetry/imports/langfuse.md` — Langfuse **Cloud**-only importer.
- `https://raw.githubusercontent.com/latitude-dev/latitude-llm/development/CHANGELOG.md` — `v0.3.118` 2026-09-23 content; near-daily cadence.
- `skopeo inspect --raw docker://docker.io/<image>` for all 13 images (6 app + 7 infra), at `:latest` and `0.3.118` where applicable — ARM64 matrix.
- `https://hub.docker.com/v2/repositories/latitudedata/<service>/tags` — release tags and compressed sizes.
- Repo-local: `modules/database/postgres/_consumer.nix`, `modules/database/postgres.nix` (fleet consumer-registration pattern), `research/openlit-selfhost-eval.md` (sibling brief; **no Laminar brief exists in this working copy** — the structure below follows the task's explicit section list plus the OpenLIT brief's labelling style).

**Rejected**
- `https://git.xszz.org/latitude-dev/latitude-llm` — a mirror; superseded by the GitHub API.
- `https://latitude.so/blog/dockerizing-llm-workloads-checklist` — a generic Docker/GPU checklist that merely mentions Latitude; no product evidence.
- The search-index snapshot of `docs.latitude.so/guides/self-hosted/production` — kept only as a dated, contradicted source (Contradiction 1), not as the authoritative self-host doc.
