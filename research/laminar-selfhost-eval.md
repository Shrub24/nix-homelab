# Research: Laminar self-host evaluation (A/B vs Langfuse on oci-melb-1)

Mirrors `research/openlit-selfhost-eval.md`. Every claim labeled **evidence** (fetched original + URL), **interpretation**, or **inference**. All sources fetched live this session; repo state at fetch time: `pushed_at 2026-09-25`.

## Summary

Laminar (`github.com/lmnr-ai/lmnr`, site **laminar.sh** — *not* laminar.dev) is an actively maintained, Apache-2.0, trace/eval-first LLM-obs platform that is a much closer like-for-like rival to Langfuse than OpenLIT is, and it even ships an official Langfuse dual-export bridge for A/B trials. ARM64 is verified for every image in its stack. The costs vs OpenLIT: it needs **Postgres + ClickHouse + (optional) Quickwit** and ~5 secrets — not zero-secret; but its default ports (5667/8000/8001/8002) collide with nothing taken, and it does **not** use 4317/4318. The operator's hypothesis (Laminar = trace/eval-first, not ops/security/cost) is **supported**.

## 1. Identity

- **Evidence** — Product: **Laminar**, "open-source observability platform purpose-built for AI agents", YC S24. Repo `lmnr-ai/lmnr`, homepage `https://laminar.sh` (https://api.github.com/repos/lmnr-ai/lmnr — `homepage`, `description`; https://raw.githubusercontent.com/lmnr-ai/lmnr/main/README.md).
- **Evidence (disambiguation)** — `https://laminar.dev` is an **unrelated** product: "Simple, expressive, and safe UI library for Scala.js" (fetched https://laminar.dev). The task's guessed domain was wrong; correct site is laminar.sh.
- **Evidence** — License: **Apache-2.0** (GitHub API `license.spdx_id`; OpenAPI spec header `license: Apache 2.0`, https://laminar.sh/docs/api-reference/ingestion/ingest-opentelemetry-traces.md).
- **Evidence** — Activity: latest release **v0.2.5 published 2026-09-13**, preceded by v0.2.4 (09-06), v0.2.3 (08-30) — weekly cadence; `pushed_at 2026-09-25`; 3,281 stars; not archived (https://api.github.com/repos/lmnr-ai/lmnr, /releases). Actively maintained: **yes**.
- **Interpretation** — The v0.2.x release line is young semver-wise, but the product is mature-rewrite-adjacent: the repo history and docs describe a full platform (Rust app-server, Next.js frontend). Star count and weekly bot-assisted releases (release notes reference `laminar-coding-agent[bot]` PRs) indicate a well-funded full-time team, not a hobby project.

## 2. Self-host story

- **Evidence** — Official compose: `git clone https://github.com/lmnr-ai/lmnr && docker compose up -d` (https://laminar.sh/docs/self-hosting/docker-compose.md; README). Two files: `docker-compose.yml` (light: "frontend, clickhouse, postgres, and app-server", no RabbitMQ) and `docker-compose-full.yml` (adds RabbitMQ for queued span processing) — both fetched raw from `github.com/lmnr-ai/lmnr/main/`.
- **Evidence** — First-party images (compose): `ghcr.io/lmnr-ai/frontend` and `ghcr.io/lmnr-ai/app-server`, both `pull_policy: always`, untagged (= `latest`). Version tags exist: GHCR tag list for both repos contains `v0.2.0 … v0.2.5` plus digest tags (GHCR `/v2/lmnr-ai/{frontend,app-server}/tags/list`, anonymous pull token) → **Renovate-pinnable**, same as OpenLIT was. Note (**evidence**): the Helm chart pulls different images, `ghcr.io/lmnr-ai/*-ee` tagged e.g. `0.1.628` (https://laminar.sh/docs/self-hosting/configuration#container-images) — two tag streams; the OSS compose path uses the non-`-ee` images above.
- **Evidence (ARM64, verified manifests — not inferred from docs)** — `skopeo inspect --raw` at fetch time:

  | Image | linux/arm64? | arm64 digest (prefix) |
  |---|---|---|
  | `ghcr.io/lmnr-ai/frontend:latest` | **yes** | `sha256:c11a09822a07…` |
  | `ghcr.io/lmnr-ai/app-server:latest` | **yes** | `sha256:1219b25ccd27…` |
  | `docker.io/clickhouse/clickhouse-server:26.5` | **yes** | `sha256:f0bf50e13e29…` |
  | `docker.io/quickwit/quickwit:v0.8.2` | **yes** | `sha256:f0d42c5b99ad…` |
  | `docker.io/library/postgres:16` | **yes** (arm64/v8) | `sha256:1a43e6bb8872…` |

  Whole stack runs on aarch64-linux. (Also note: ClickHouse `26.5` major line is newer than whatever Langfuse's native CH runs — co-tenanting must use *our* server version, see §3.)
- **Evidence (footprint)** — No stated number in the compose docs. Helm `values.yaml` requests: app-server `0.5 cpu / 1Gi`, frontend `0.1 cpu / 1Gi`, nginx `100m / 128Mi`, Quickwit components `0.1 cpu / 100Mi` each (indexer comment: "needs at least ~1Gi resident" under realistic ingest), limits mostly ≤4Gi RAM; optional PII redactor requests `1 cpu / 2Gi` (disabled by default) — https://raw.githubusercontent.com/lmnr-ai/lmnr-helm/main/charts/laminar/values.yaml + https://laminar.sh/docs/self-hosting/configuration#pii-redaction.
- **Interpretation** — Light compose ≈ 4–6 containers (frontend, app-server, postgres, clickhouse, quickwit); heavier than OpenLIT's one container, comparable in kind to Langfuse's own multi-service shape but smaller (no S3/Redis/Kafka requirement on the compose path).

## 3. Stateful dependencies (co-tenancy cost)

- **Evidence** — **PostgreSQL is required, ClickHouse is required**; everything else degrades: "PostgreSQL and ClickHouse are required. Everything else degrades gracefully: RabbitMQ → in-memory queue, Redis → in-memory cache, Quickwit → search disabled, S3 → MockStorage" (repo `CLAUDE.md:55`, via code search). `app-server/src/main.rs:1244`: "Quickwit is optional - if unavailable, the server will start but search/indexing will be disabled" (`QUICKWIT_ENABLED=false`).
- **Evidence** — No Redis/SQLite/Kafka on the compose path (compose files fetched; SQLite appears nowhere). App metadata (projects, evals, datasets, users) → Postgres via Drizzle; telemetry spans → ClickHouse; full-text search index → Quickwit.
- **Evidence (Postgres co-tenancy is a first-class documented feature)** — "Custom Postgres schema … when deploying alongside other services in a shared Postgres instance, set `POSTGRES_SCHEMA` for both frontend and app-server … `POSTGRES_CREATE_SCHEMA=false` if the DB role lacks CREATE" (README, fetched raw). Caveat in same section: "running Laminar alongside another Drizzle-managed service in the same database may still require manual intervention, since Drizzle's migration journal is versioned per-schema."
- **Evidence (ClickHouse)** — Compose always ships its own CH but the app is configured purely by `CLICKHOUSE_URL/USER/PASSWORD/RO_USER/RO_PASSWORD` env (compose + `.env`, both fetched) — pointing it at an external CH is mechanically possible; **no doc describes external-ClickHouse for compose** (that story exists only for Helm/S3: configuration reference). Two upstream config fragments ship for its *own* server: `config.d/lmnr.xml` (removes ~16 system log tables server-wide, sets `query_log`/`error_log` TTL to 3 days) and `users.d/lmnr.xml` (patches the **`default` profile**: `date_time_input_format=best_effort`) — both fetched raw from repo root.
- **Interpretation** — Co-tenancy plan mirroring OpenLIT: run against the native CH with a `laminar` database + dedicated user (users.d fragment in langfuse's existing fragment file, as OpenLIT did), and **drop both upstream XML fragments** — `config.d` would mutate server-wide logging/TTL for Langfuse's CH, and `users.d` patches the shared `default` profile. The fragments are single-node tuning, not functional requirements (inference from their content: they only remove logs and set TTLs/profiles).
- **Inference (open question)** — Whether Laminar's migrations create their own database or require CREATE rights on an existing one is unverified; OpenLIT's receiver created tables but not the database. A fleet `CREATE DATABASE IF NOT EXISTS laminar` oneshot would likely cover it, but must be tested.
- **Interpretation vs OpenLIT** — OpenLIT = 1 container + CH + SQLite; Laminar = 2 first-party containers + Postgres **and** CH (+ optional Quickwit). If the fleet's existing Postgres substrate is reused (precedent: `openspec/changes/archive/2026-06-23-litellm-postgres-shared-access`), marginal cost is one Postgres database/schema + a CH database/user — still meaningfully heavier than OpenLIT but the same *kind* of co-tenancy Langfuse already tolerates.

## 4. Ports / OTLP / auth

- **Evidence (ports from compose, defaults overridable via `FRONTEND_HOST_PORT`, `APP_SERVER_HOST_PORT`, `APP_SERVER_GRPC_HOST_PORT`, `APP_SERVER_RT_HOST_PORT` in `.env`)**:

  | Purpose | Port | Collision vs taken {3000, 3100, 4317/4318, 6280, 7411} |
  |---|---|---|
  | UI (Next.js frontend) | **5667** | free |
  | app-server HTTP (also OTLP/HTTP ingest) | **8000** | free |
  | app-server gRPC (also OTLP/gRPC ingest) | **8001** | free |
  | app-server realtime (SSE) | **8002** | free |
  | Quickwit REST/UI + its OTLP gRPC (optional component) | 7280 / 7281 | free |
  | Postgres (light compose host mapping) | 5433 | free (would be dropped if reusing fleet Postgres) |

- **Evidence** — **Laminar does not use 4317/4318.** OTLP self-hosted defaults: gRPC `8001`, HTTP `8000`, path `/v1/traces`, all three wire variants (OTLP/gRPC, HTTP/proto, HTTP/JSON) supported; bearer auth with a **project API key** (`authorization: Bearer <LMNR_PROJECT_API_KEY>`, lowercase `authorization` key required for gRPC metadata) — https://laminar.sh/docs/tracing/otel.md (fetched) + ingestion OpenAPI (`projectApiKey` / `ingestApiKey` security schemes).
- **Evidence** — Native SDKs: Python (`pip install lmnr[all]`), TypeScript (`@lmnr-ai/lmnr`), plus a large instrumentor matrix (OpenAI/Anthropic/Gemini/LangChain/LlamaIndex/Vercel AI/Pydantic AI/OpenAI Agents/Claude Agent SDK/Browser Use/…, README + docs index). Non-SDK producers can point any OTel exporter at it (the otel.md page exists precisely for that).
- **Evidence (auth)** — OSS feature table lists "OAuth sign-in (GitHub, Google, Azure AD, Okta, Keycloak) ✓" for the OSS edition (https://laminar.sh/docs/self-hosting/overview). Compose doc: "**By default, any user can sign in** to your self-hosted instance. To restrict access … enable GitHub OAuth" (`AUTH_GITHUB_ID/SECRET`) plus an `allowed-emails.json` allow-list (https://laminar.sh/docs/self-hosting/docker-compose.md). Helm config shows `AUTH_OKTA_ISSUER` / `AUTH_KEYCLOAK_ISSUER` as **issuer-URL-based OIDC** (configuration reference §OAuth login), and the same env vars are honored by the frontend image itself — gated purely on env presence (`frontend/lib/features/features.ts:73`, `frontend/lib/auth.ts:169` via code search; also listed in `frontend/.env.local.example`), i.e. not Helm-only.
- **Inference** — Because `AUTH_KEYCLOAK_ISSUER` is a standard OIDC issuer URL consumed by the NextAuth Keycloak provider with PKCE, **Kanidm could plausibly back Laminar login** in the same way it backs other OIDC apps — but no doc mentions Kanidm/generic OIDC, and it is untested; the documented compose path is GitHub OAuth or open sign-in.
- **Interpretation** — Against OpenLIT (seeded local user + GitHub/Google, no generic OIDC in OSS): Laminar's OSS auth surface is broader (five providers, two of them issuer-configurable), though the *documented* compose story is narrower than the feature table suggests. With open sign-in by default, the Cloudflare Access gate (as used on langfuse's route) remains the practical outer wall regardless.

## 5. Feature axis vs Langfuse (testing the operator's hypothesis)

- **Evidence — OSS feature table** (https://laminar.sh/docs/self-hosting/overview): trace ingestion (OTLP), full-text trace search, custom dashboards, SQL editor, CLI, evaluations, datasets, labeling queues, browser session recording, agent debugger (record/replay), MCP access, chat-with-trace, SQL-with-AI — **all in OSS**. Licensed-only: Signals (plain-language outcome/failure extraction), signal clusters, email/Slack alerts.
- **Evidence — cost tracking exists**: `gen_ai.usage.cost/input_cost/output_cost` span attributes with Laminar-side estimation when absent (otel.md span reference); dedicated docs `tracing/cost-tracking.md` and `platform/custom-model-costs.md` in the docs index.
- **Evidence — agent-first UX**: transcript-view traces instead of span trees, LangGraph visualization, session replay for browser agents, record/replay debugger with cache ("prove the fix with an eval"), official integrations for coding agents (Claude Code, Codex, OpenCode, Pi) — docs index + README.
- **Evidence — prompt management**: **no** prompt-management feature page exists in the docs index (llms.txt, fetched — full page list). The **Playground** lets you experiment with prompts, open any span into it, and "Save versions to revisit later" (https://laminar.sh/docs/playground.md) — but there is no versioned prompt registry comparable to Langfuse's prompt management surfaced anywhere in the OSS docs.
- **Evidence — what it does NOT have** (vs OpenLIT's GenAI ops/security/cost emphasis): no security/vault/cost-optimization tooling in the feature table; PII redaction is optional (licensed? no — OSS ✓ but disabled by default and Helm-gated); no LLM gateway/proxy. Signals (its "ops" story) are enterprise-licensed out of OSS.
- **Verdict — interpretation**: **Hypothesis supported.** Laminar optimizes for the trace/eval/debug workflow (transcript traces, datasets, evals+comparison, labeling, replay, SQL/observability-of-traces), i.e. a genuine like-for-like rival to Langfuse on the trace/eval axis, whereas OpenLIT optimizes for GenAI ops/security/cost. Gaps vs Langfuse: no versioned prompt management (evidence: absence in docs index — moderate confidence), Signals/alerting paywalled, AI features need an LLM provider key on self-host. Extra beyond Langfuse: agent debugger/replay, browser session recording, SQL editor/MCP/CLI, and a differential feature (Langfuse bridge below).
- **Evidence — killer A/B enabler**: Laminar publishes an official **Langfuse dual-export bridge**: keep all Langfuse instrumentation, add `Laminar.initialize(instruments={Instruments.LANGFUSE})` + `LMNR_PROJECT_API_KEY`, and every Langfuse span (langfuse ≥3.0, Python-only, no TS equivalent) flows to both platforms for side-by-side comparison; removing one specifier reverses it (https://laminar.sh/docs/integrations/langfuse.md, fetched). It even documents self-hosted bridge config (`base_url`, `http_port 8000`, `grpc_port 8001`).

## 6. Migration shape if chosen (one NixOS aspect on oci-melb-1)

- **Evidence + interpretation, component by component:**
  - **Containers**: two first-party images (`frontend`, `app-server`) pinned `v0.2.5` + digest into `policy/oci-images.nix` (tags verified on GHCR; compose doesn't pin → we would). Quickwit: either run `quickwit/quickwit:v0.8.2` or set `QUICKWIT_ENABLED=false` and lose full-text search (verified graceful: `main.rs:1244`). Postgres: reuse fleet substrate with `POSTGRES_SCHEMA=laminar`, `POSTGRES_CREATE_SCHEMA=false` (documented), or ship `postgres:16` if the substrate can't grant a schema.
  - **ClickHouse**: co-tenant Langfuse's native CH like OpenLIT did — `laminar` database + user; **do not** mount upstream `config.d/lmnr.xml` (removes system logs, 3-day query_log/error_log TTLs server-wide) or `users.d/lmnr.xml` (patches shared `default` profile); write our own scoped users.d fragment instead. Uncertain: whether app-server migrations need CREATE rights (open question).
  - **Secrets (sops — this is *not* a zero-secret deployment like OpenLIT)**: `SHARED_SECRET_TOKEN`, `AEAD_SECRET_KEY` (exactly 64 hex chars/32 bytes, encrypts LLM-profile credentials; must match frontend+app-server), `NEXTAUTH_SECRET`, `POSTGRES_PASSWORD`, ClickHouse password(s) — all from the committed `.env` (fetched) which otherwise ships placeholder defaults. Optional: `LLM_API_KEY`/provider for chat-with-trace & SQL-with-AI (can stay off for a trial).
  - **Ports**: keep defaults — UI **5667** (Access-gated route; bind/publish carefully since default sign-in is open), ingest **8000/8001** (+8002 SSE). 4317/4318 stay with OpenLIT; no collision with langfuse:3000, openlit:3100, 6280, 7411.
  - **Ingest wiring for the A/B**: exporters dual-target — existing pipeline keeps sending to Langfuse/OpenLIT; add an OTLP exporter (HTTP→8000 or gRPC→8001, `Bearer <project API key>`) for Laminar; or use the Python bridge if the workload is Langfuse-SDK-instrumented.
  - **Auth**: outer gate via Cloudflare Access on the 5667 route (mirrors langfuse), optionally `AUTH_KEYCLOAK_*`→Kanidm as the in-app story (inference, untested).
- **Interpretation (delta vs OpenLIT aspect)**: roughly 2–3× the provisioning surface of `modules/observability/openlit.nix` — one more required datastore class (Postgres), a CH fragment to author (not reuse), ≥5 sops-managed secrets where OpenLIT had zero, and an optional third stateful component (Quickwit). No Kafka/S3/Redis required (evidence: compose + CLAUDE.md degradation list).

## 7. Open questions

1. Does app-server create its own CH database / what DDL rights does it need on an external CH? (untested; compose only shows env pointing at a server)
2. Does `AUTH_KEYCLOAK_ISSUER` work in the *compose* deployment against Kanidm? (env-gated in frontend code — strong signal, but undocumented for compose and untested; docs inconsistency below)
3. Postgres migration behavior on a shared instance — the README's own Drizzle-journal caveat with another Drizzle service sharing the *database* (schema isolation mitigates but is explicitly "may still require manual intervention").
4. Resource footprint on ARM64 in practice (only Helm requests/limits found; no real-world RAM/disk numbers, no stated ClickHouse disk amplification beyond "20x trace compression" marketing claim in README).
5. Whether eval runs / labeling / datasets in OSS have any hidden limits (feature table says ✓; no limits documented).

## Contradictions / inconsistencies (recorded, not resolved)

- **Docs vs docs on compose auth**: feature table says OAuth (5 providers) ✓ in OSS; the compose page documents only GitHub OAuth + `allowed-emails.json`, while Helm config + frontend code show Okta/Keycloak issuer env vars. (Sources: overview vs docker-compose vs `frontend/lib/auth.ts`.)
- **Two image tag streams**: OSS releases/tags are `v0.2.x`; Helm docs pin `*-ee` images at `0.1.628`. Not reconciled here — treat OSS and EE as different streams when pinning.
- **README says UI at `localhost:5667`** while one docs cross-reference still points to an older path (`/docs/hosting-options#self-hosted-docker-compose` referenced from README; page served at `/docs/self-hosting/docker-compose` today) — stale link, harmless.

## Sources

Kept (all fetched originals):
- https://github.com/lmnr-ai/lmnr + GitHub API (`/repos`, `/releases`, `/tags`) — identity, license, activity
- https://raw.githubusercontent.com/lmnr-ai/lmnr/main/{README.md,docker-compose.yml,docker-compose-full.yml,.env,clickhouse-server-config.xml,clickhouse-profiles-config.xml} — self-host stack, ports, secrets, CH fragments
- https://laminar.sh/docs/self-hosting/{overview,docker-compose,configuration}.md — feature tables, ports, OAuth, sizing, storage
- https://laminar.sh/docs/tracing/otel.md — OTLP endpoints/ports/auth for self-hosted
- https://laminar.sh/docs/integrations/langfuse.md — dual-export bridge for the A/B
- https://laminar.sh/docs/playground.md, https://laminar.sh/docs/llms.txt — feature axis, prompt-management absence
- https://laminar.sh/docs/api-reference/ingestion/ingest-opentelemetry-traces.md — /v1/traces API, key auth
- GHCR/Docker Hub registry manifests via `skopeo inspect --raw` (frontend, app-server, clickhouse, quickwit, postgres) — ARM64 verification
- Code search hits: `app-server/src/main.rs:1244` (Quickwit optional), `frontend/lib/features/features.ts:73`, `frontend/lib/auth.ts:169` (OIDC env gating), `CLAUDE.md:55` (required vs degradable deps)
- https://raw.githubusercontent.com/lmnr-ai/lmnr-helm/main/charts/laminar/values.yaml — resource requests
- https://laminar.dev — rejected as unrelated (Scala.js UI library)

Rejected: Tracxn/company-profile pages (secondary, used only as a search lead); ramsung/laminar fork (stale mirror).
