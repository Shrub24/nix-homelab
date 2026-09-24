# Research: Configuration semantics — degoog, hindsight, docs-mcp (knowledge fleet)

## Summary

All three services are configured almost entirely correctly, with one clear inversion: **degoog's `DEGOOG_DISTRUST_PROXY = true` is the opposite of what a Caddy-fronted deployment wants** — upstream source shows `true` (or any value except `"false"`/`"0"`) makes degoog *ignore* `X-Forwarded-For`/`X-Forwarded-Proto`, so the Caddy edge becomes "untrusted" (real client IPs are lost, honeypot bans against private addresses are skipped, and settings-session cookies never get the `Secure` flag). Both hindsight and docs-mcp leave upstream-blessed auth surfaces off (hindsight MCP bearer token, docs-mcp OAuth2), which is defensible for a tailnet-only posture but is a decision the operator should make explicitly, not by omission.

Versions checked: **degoog** at flake-lock rev `e4e110b` (source: `/nix/store/3y32wmngi516h3lm2ydhzi54a6m2kv2q-source`), **hindsight 0.10.0** (tag `v0.10.0`, image `ghcr.io/vectorize-io/hindsight:0.10.0@sha256:3edcb6…`), **docs-mcp-server 3.1.0** (tag `v3.1.0`, image `ghcr.io/arabold/docs-mcp-server:3.1.0@sha256:5bf224…`). Repo pins: `policy/oci-images.nix` (docs-mcp line 36, hindsight line 38); degoog pinned in `flake.lock` node `degoog`.

---

## Chosen settings (decisions applied in this repo)

Recorded after the review above; every deviation is deliberate.

| Service | Decision |
|---|---|
| degoog | `DEGOOG_PUBLIC_INSTANCE=false` (admin surface gated by the settings password, not anonymous-public mode); `DEGOOG_DISTRUST_PROXY=false` (proxy trust requires the literal `"false"`, and the module's default is `true`); `DEGOOG_WIZARD` unset (declared by the module, never read by the app). Store stays SQLite — upstream scopes Postgres to a “busy public instance with a large indexer” and Valkey to multi-replica/shared-cache, neither of which one replica with a few users is. State stays `/var/lib/degoog`: the upstream unit is a DynamicUser under `ProtectSystem=strict`, the whole state set (`plugin-settings.json`, `autocomplete/`, `indexer/`, `searx/engines`) lives in that one dir, and `state-backups` covers it. |
| hindsight | No MCP bearer token: the control plane and the REST API are unauthenticated upstream, so a token on MCP alone would be cosmetic — the service is host-networked with no published port on a trusted tailnet. `HINDSIGHT_API_WORKER_ID=hindsight` so a restart recognises its own claimed tasks (the default is the container hostname, which changes every restart and orphans them). PostgreSQL + pgvector via the fleet substrate; model cache excluded from backup. |
| docs-mcp | Left at upstream defaults: the store stays writable because indexing arbitrary documentation is the point; OAuth2 is unusable here (turnstile-based DCR, which Kanidm has none of) so bearer-token auth carries it. Store and config under `/srv/data/docs-mcp`, exported with `sqlite3 .backup`. |

Container DNS search is fleet-wide (`virtualisation.containers.containersConf.settings.containers.dns_searches`), which is why container dials use short MagicDNS names.

---

## 1. degoog (private search front end; Nix module `services.degoog`, upstream NixOS module in-tree)

### Config surface (grouped)

| Group | Vars (upstream module + app) |
|---|---|
| Networking/proxy | `DEGOOG_PORT` (4444), `DEGOOG_UNIX_SOCKET`, `DEGOOG_BASE_URL`, `DEGOOG_DISTRUST_PROXY` |
| Auth | `DEGOOG_SETTINGS_PASSWORDS`, `DEGOOG_DANGEROUSLY_NO_PASSWORD`, `DEGOOG_SETTINGS_PATH`, `DEGOOG_PUBLIC_INSTANCE` (also shapes auth) |
| Onboarding | `DEGOOG_WIZARD` |
| Storage/index | `DEGOOG_DATA_DIR` (module-managed `/var/lib/degoog`), `DEGOOG_POSTGRES*` (SQLite default; Postgres/Valkey for busy instances) |

Marked as set by us: `DEGOOG_PUBLIC_INSTANCE=false`, `DEGOOG_WIZARD=false`, `DEGOOG_DISTRUST_PROXY=true`, `DEGOOG_SETTINGS_PASSWORDS` (via sops template `degoog.environment`) — `modules/knowledge/degoog.nix`.

### Verdict table

| Setting | Meaning (verified from source) | Our value | Verdict |
|---|---|---|---|
| `DEGOOG_PUBLIC_INSTANCE` | `src/server/utils/public-instance.ts:1-4`: `true`/`1` ⇒ public. Public mode: settings UI replaced by `settings-public.html` (`pages.ts:159`), admin endpoints 404 unless password set (`pages.ts:197,207`), `/api/server-settings` always reports wizard (`setup.ts:14`). `=false` ⇒ **private instance**: full settings/admin UI, gated by `DEGOOG_SETTINGS_PASSWORDS`. Not a discovery/listing flag — the `PUBLIC_INSTANCES.md` list is human-curated, not machine-published. | `false` | ✅ **Correct.** "Private instance" is exactly what `false` means. |
| `DEGOOG_WIZARD` | `src/server/utils/server-settings.ts:138-142` (`isWizardActive`): env `= "false"` (any case) forces the setup wizard off regardless of stored server settings; otherwise wizard shows until `settings.wizard === true`. | `false` | ✅ **Correct** (guarantees the wizard never reappears; slightly redundant once wizard was completed once). |
| `DEGOOG_DISTRUST_PROXY` | `src/server/utils/request.ts:8-12` (`isProxyTrusted`): env `undefined` ⇒ **not trusted**; env `"false"` **or** `"0"` ⇒ **trusted**; anything else (incl. `"true"`) ⇒ not trusted. Trusted ⇒ `getClientIp` reads `X-Forwarded-For`/`X-Real-IP` (`request.ts:14-21`), `isHttpsRequest` reads `X-Forwarded-Proto` (`request.ts:25-29`), `getPublicUrl` uses `x-forwarded-proto`/`x-forwarded-host` (`public-url.ts:41-47`). Consequence of untrusted: `bot-trap.ts:53-59` skips honeypot bans for private/loopback IPs with the literal hint *"If your proxy does not forward X-Forwarded-For, set DEGOOG_DISTRUST_PROXY=0"*; settings session cookie omits `Secure` (`settings-auth.ts:100-109`, secure = `isHttpsRequest`). Upstream repo `AGENTS.md:68`: *"getClientIp ignores X-Forwarded-For unless DEGOOG_DISTRUST_PROXY says otherwise"*. Note the naming is a double negative: **`true` = distrust = proxy headers ignored**. The upstream Nix module's *option* default is `false` (trust) — `third-party/nix/module.nix:101-106,199`. | `true` | ⚠️ **Wrong (inverted) for a Caddy-fronted deployment.** `true` makes Caddy untrusted: rate-limit/honeypot keyed on Caddy's own address, bans behind the proxy are skipped, HTTPS detection falls back to URL protocol (`http`) so no `Secure` cookie. Should be `false` (trust the proxy) — safe here because Caddy is ours and sets the headers. Only keep `true` if the service were exposed without a trusted proxy in front. |
| `DEGOOG_SETTINGS_PASSWORDS` | `src/server/routes/settings-auth.ts:34-41`: comma-separated password list gating the settings/admin area ("settings gate"). Without it a one-off random password is printed per run (`settings-auth.ts:88-101`). README: *"an unlocked instance lets anyone install extensions, which runs code on the server"* (RCE-equivalent). | Set via sops template | ✅ **Correct and important** — keep. |
| `DEGOOG_BASE_URL` (unset) | `src/server/utils/base-url.ts:3-20`: fixed origin or base *path* (e.g. `/degoog`) used for link/URL building; `getPublicUrl` (`public-url.ts:39-47`) otherwise derives proto/host from the request (honoring `X-Forwarded-*` only when the proxy is trusted). | unset | ✅ Acceptable. **Optional improvement** (inferred): pin `DEGOOG_BASE_URL = https://degoog.<tailnet/edge-name>` so generated links (e.g. the `!ip` command callback in `src/server/extensions/commands/builtins/ip/index.ts:39`) are stable instead of request-derived. |

**Direct answer to the critical question:** `DISTRUST_PROXY=true` **does** disable trusted-proxy handling — it is *not* the "required when a proxy is in front" setting. With a trusted Caddy in front, upstream semantics want `DEGOOG_DISTRUST_PROXY=false` (or `0`). Verified from `src/server/utils/request.ts:8-12` and the env-var name's plain reading confirmed by `AGENTS.md:68`.

---

## 2. hindsight 0.10.0 (agent memory; full/standalone image, container + co-located PostgreSQL)

### Config surface (grouped) — verified against `hindsight-api-slim/hindsight_api/config.py` (env constants lines 153-169, 626-760), `docker/standalone/Dockerfile:240-245,299-301,427-429`, `docker/standalone/start-all.sh:163-164,335,347`, `hindsight-control-plane/src/lib/hindsight-client.ts:14-23`, and `hindsight-docs/docs/developer/configuration.md`

| Group | Vars |
|---|---|
| API server | `HINDSIGHT_API_HOST/PORT/LOG_LEVEL/LOG_FORMAT/WORKERS`, `HINDSIGHT_ENABLE_API` (start-all), `HINDSIGHT_API_BASE_PATH` |
| Control plane | `HINDSIGHT_ENABLE_CP`, `HINDSIGHT_CP_PORT`, `HINDSIGHT_CP_HOSTNAME`, `HINDSIGHT_CP_DATAPLANE_API_URL`, `HINDSIGHT_CP_DATAPLANE_API_KEY` |
| Storage/index | `HINDSIGHT_API_DATABASE_URL`, `HINDSIGHT_API_VECTOR_EXTENSION`, `HINDSIGHT_API_ANN_*`, `HINDSIGHT_API_TEXT_SEARCH_EXTENSION` |
| LLM / embeddings | `HINDSIGHT_API_LLM_PROVIDER/API_KEY/MODEL/BASE_URL` (+ per-op overrides retain/reflect/consolidation), `HINDSIGHT_API_EMBEDDINGS_PROVIDER` + family |
| Auth | `HINDSIGHT_API_MCP_AUTH_TOKEN` (MCP bearer), TenantExtension pluggable auth (`HINDSIGHT_API_TENANT_EXTENSION`) |
| Telemetry/retention | `HINDSIGHT_API_OTEL_*`, `HINDSIGHT_API_OPERATION_RETENTION_DAYS`, `HINDSIGHT_API_AUDIT_LOG_RETENTION_DAYS`, `HINDSIGHT_API_LLM_TRACE_RETENTION_DAYS`, worker id `HINDSIGHT_API_WORKER_ID` |

Set by us (`modules/knowledge/hindsight.nix`): HOST, PORT, LOG_LEVEL, VECTOR_EXTENSION, ENABLE_API, ENABLE_CP, CP_PORT, CP_DATAPLANE_API_URL, LLM_PROVIDER, LLM_MODEL, LLM_BASE_URL, plus sops-injected `HINDSIGHT_API_DATABASE_URL` and `HINDSIGHT_API_LLM_API_KEY`; `--network=host`, `--shm-size=1g`, cache volume.

### Verdict table

| Setting | Meaning (verified) | Our value | Verdict |
|---|---|---|---|
| `HINDSIGHT_API_HOST` | Bind address; image default `0.0.0.0` (`Dockerfile:240`, `config.py:1450`). | `0.0.0.0` | ✅ Matches default; needed with `--network=host`. |
| `HINDSIGHT_API_PORT` | API port; default `8888` (`Dockerfile:241`, `config.py:1451`). | `8888` | ✅ Default. |
| `HINDSIGHT_API_LOG_LEVEL` | Default `info` (`Dockerfile:242`, `config.py:1453`). | `info` | ✅ Default (explicit is fine). |
| `HINDSIGHT_API_VECTOR_EXTENSION` | Vector index backend: `pgvector` (default), `vchord`, `pgvectorscale`, `scann` (`config.py:1388`, configuration.md:118). Docs: pgvector is right for *"<10M vectors, simple nearest-neighbor, standard PostgreSQL"* (configuration.md:121-125,159-163). | `pgvector` | ✅ Correct — idiomatic default for a homelab-scale single-bank deployment. |
| `HINDSIGHT_ENABLE_API` / `HINDSIGHT_ENABLE_CP` | Consumed only by `start-all.sh` (`start-all.sh:163-164`); both default `true` in the standalone (all-in-one) image stage (`Dockerfile:428-429`). | `true`/`true` | ✅ Correct; matches the standalone stage's defaults (redundant-but-explicit, not no-ops). |
| `HINDSIGHT_CP_PORT` | Control-plane (Next.js UI) port; default `9999` (`start-all.sh:335`, Dockerfile `EXPOSE 9999`). | `9999` | ✅ Default. |
| `HINDSIGHT_CP_DATAPLANE_API_URL` | URL the CP UI uses to reach the API; default `http://localhost:8888` (`hindsight-client.ts:14`, `Dockerfile:427`). Optional `HINDSIGHT_CP_DATAPLANE_API_KEY` adds a Bearer to those calls (`hindsight-client.ts:15,22-23`) — only useful if the API itself validates a key (TenantExtension). | `http://127.0.0.1:8888` | ✅ Correct with `--network=host`. |
| `HINDSIGHT_API_LLM_PROVIDER` | Provider list incl. `openai` for "any OpenAI-compatible API" (models.mdx:22-25: *"Set `HINDSIGHT_API_LLM_PROVIDER=openai` and point `HINDSIGHT_API_LLM_BASE_URL` at the endpoint that serves `/chat/completions`"*). Default `openai` (`config.py:1051`). | `openai` | ✅ Correct for the host-local OpenAI-compatible router. |
| `HINDSIGHT_API_LLM_BASE_URL` | Custom OpenAI-compatible endpoint; unset = provider default (`configuration.md:274`). | `http://127.0.0.1:20128/v1` | ✅ Correct shape (`…/v1` per models.mdx:24-25). |
| `HINDSIGHT_API_LLM_MODEL` | Model name; if unset falls back to a per-provider default (`config.py:3949-3950`, configuration.md:273). We assert non-empty because the router's catalog is imperative. | `hindsight` (host sets) | ✅ Correct; required given a custom router. |
| `HINDSIGHT_API_LLM_API_KEY` | *"API key for providers that require one"* (configuration.md:272). Injected via sops. | set | ✅ Correct. |
| `HINDSIGHT_API_DATABASE_URL` | Postgres URL; default `pg0` = **embedded** database (`config.py:1049`, configuration.md:22). We point at the host's own cluster with `CREATE EXTENSION vector` + scram auth. | set (sops) | ✅ Correct — external co-located Postgres replaces pg0 cleanly (start-all skips pg0 checks when this is set, `start-all.sh:89-92`). |

**Required vs optional:** with our external-DB, external-LLM shape, the effective requirements are `DATABASE_URL`, `LLM_PROVIDER`+`LLM_BASE_URL`+`LLM_MODEL`(+`LLM_API_KEY`). Everything else we set is a default restated. Embeddings require nothing from us on the full image (see below).

**Auth for API/CP — direct answer:** the **REST API has no built-in auth**. `Authorization` is parsed into `RequestContext.api_key` (`api/http.py:5068-5088`) but nothing validates it unless a `TenantExtension` is configured (`docs/developer/extensions.md:11-32` — API-key auth is an extension capability). The **MCP endpoint is open by default** with an optional bearer: *"By default, the MCP endpoint is open. For production deployments, set `HINDSIGHT_API_MCP_AUTH_TOKEN`"* (configuration.md:2250, 2281-2284). The **control plane has no login/auth at all** — it is a Next.js UI whose only credential is the optional dataplane bearer it *sends* upstream (`hindsight-client.ts:15-23`). So today both API (8888) and CP (9999) are unauthenticated surfaces reachable from loopback/whatever the host firewall allows; protection is purely network-level.

**Upstream-recommended choices:**
- **Embedding model/dimension:** default embeddings provider is `local` with `BAAI/bge-small-en-v1.5` (384-dim) — bundled and preloaded in the *full* image (`configuration.md:798-802`, `Dockerfile:226-244`). Since we run the full image and set no `EMBEDDINGS_*`, we get exactly that — the upstream-blessed zero-config choice. No dimension pinning needed.
- **Vector backend:** `pgvector` (default) per the "<10M vectors" guidance above.
- **Retention/compaction:** operation rows are kept **forever** by default (`HINDSIGHT_API_OPERATION_RETENTION_DAYS=0`, configuration.md:2310); LLM trace rows default to 1 day (`configuration.md:2419`); audit log `-1` forever (`configuration.md:2405`). Consolidation of mental models is automatic; nothing retention-wise is required for correctness.

### Gaps (should consider setting)

| Gap | Why | Citation |
|---|---|---|
| `HINDSIGHT_API_WORKER_ID` (stable value) | Worker identity defaults to container hostname, which changes each restart; interrupted tasks stay parked under the dead ID. *"recommended even for single-container deployments."* | configuration.md via installation.md tip (docs/developer/installation.md:120-123) |
| `HINDSIGHT_API_MCP_AUTH_TOKEN` | MCP endpoint open by default; one env var turns on bearer auth. Low-cost hardening even on a tailnet. | configuration.md:2250, 2281-2284 |
| Retention window (`HINDSIGHT_API_OPERATION_RETENTION_DAYS`) | Only if the operations table grows; default is keep-forever. Optional. | configuration.md:2310 |

**No-ops found:** none — every var we set is consumed. Several (`HOST/PORT/LOG_LEVEL/VECTOR_EXTENSION/ENABLE_*`/`CP_PORT`/`CP_DATAPLANE_API_URL`) merely restate image defaults.

---

## 3. docs-mcp-server 3.1.0 (grounded documentation index; standalone single-port mode)

### Config surface (grouped) — verified against `src/utils/config.ts:433-482` (env mappings), `docs/infrastructure/{authentication,deployment-modes,security,telemetry}.md`, `docs/guides/embedding-models.md`, `docs/concepts/refresh-architecture.md`, `src/services/mcpService.ts:8,162`, `src/store/embeddings/EmbeddingFactory.ts:108-165`

| Group | Vars |
|---|---|
| Transport/server | `DOCS_MCP_PROTOCOL` (`auto`/`stdio`/`http`), `DOCS_MCP_HOST`, `DOCS_MCP_PORT`, `DOCS_MCP_WEB_PORT`, `DOCS_MCP_SERVER_PUBLIC_ORIGIN`, `DOCS_MCP_MCP_TRANSPORT` (`sse`/`streamable`) |
| Storage | `DOCS_MCP_STORE_PATH` (default `~/.docs-mcp-server`) |
| Auth | `DOCS_MCP_AUTH_ENABLED`, `DOCS_MCP_AUTH_ISSUER_URL`, `DOCS_MCP_AUTH_AUDIENCE` (OAuth2/OIDC JWT) |
| Embeddings/LLM | `DOCS_MCP_EMBEDDING_MODEL`, `OPENAI_API_KEY`, `OPENAI_API_BASE` (+ Gemini/Vertex/Azure/AWS variants) |
| Scraper/security | `DOCS_MCP_SCRAPER_*` incl. `scraper.security.network.mode` (`open`/`allowlist`), `allowedHosts`, `allowedCidrs`, `allowPrivateNetworks`; `DOCS_MCP_READ_ONLY` |
| Telemetry | `DOCS_MCP_TELEMETRY` (PostHog opt-out) |
| Refresh | ETag-based conditional re-crawl via the `refresh_docs` operation (no scheduler; operator/tool-invoked) |

Set by us (`modules/knowledge/docs-mcp.nix`): PROTOCOL, STORE_PATH, TELEMETRY, EMBEDDING_MODEL, OPENAI_API_BASE, OPENAI_API_KEY (placeholder `bifrost-local`), `/data` + `/config` volumes, host networking.

### Verdict table

| Setting | Meaning (verified) | Our value | Verdict |
|---|---|---|---|
| `DOCS_MCP_PROTOCOL=http` | `http` mode = HTTP server with **Streamable HTTP** MCP transport (`mcpService.ts:8,162` — `StreamableHTTPServerTransport`), web UI and tRPC API on one port (deployment-modes.md "Standalone Server Mode"). Critical detail: `auto` detection picks **stdio when stdin/stdout are not TTYs** (deployment-modes.md:66-72) — i.e. a plain container would default to stdio and never serve HTTP. | `http` | ✅ **Correct and actually required** for a headless HTTP deployment. |
| `DOCS_MCP_STORE_PATH` | Storage dir for the SQLite document store + logs (configuration.md:157). | `/data` | ✅ Correct; matches our `/data` volume. |
| `DOCS_MCP_TELEMETRY` | PostHog telemetry opt-out; privacy-first, metadata-only (telemetry.md). | `false` | ✅ Correct for a private deployment. |
| `DOCS_MCP_EMBEDDING_MODEL` | Model sent to the embeddings endpoint; must stay consistent with what's recorded in the store (embedding-models.md; any OpenAI-compatible name accepted). | gateway alias | ✅ Correct, provided the alias's dimensions never change for an existing store (inferred risk: model swap invalidates stored vectors — re-index required). |
| `OPENAI_API_BASE` | *"Custom OpenAI-compatible API endpoint (e.g., Ollama)"* (embedding-models.md:34); consumed as `baseURL` in `EmbeddingFactory.ts:165`. | cross-host gateway | ✅ Correct. |
| `OPENAI_API_KEY` | Required credential for the `openai` provider: `MissingCredentialsError` if absent (`EmbeddingFactory.ts:147-148`); truthy-ness alone unlocks the openai path (`config.ts:561`). | `bifrost-local` placeholder | ✅ Correct — same pattern as upstream's Ollama example (`OPENAI_API_KEY="ollama"`, embedding-models.md). Not a secret; fine in plain env. |

**Auth — direct answer:** there **is** an auth mode we leave off, but it is OAuth2-only, not static bearer: `DOCS_MCP_AUTH_ENABLED` (+ `DOCS_MCP_AUTH_ISSUER_URL`/`DOCS_MCP_AUTH_AUDIENCE`) makes the server an OAuth2 *protected resource* validating JWTs from an external IdP (Cloudflare Access is a valid issuer shape) — authentication.md:5-9, config.ts:469-481. Two caveats, quoted: *"OAuth2 authentication only protects MCP endpoints (`/mcp`, `/sse`). The tRPC API endpoints (`/api`) … are not protected"* and *"tRPC API endpoints must be secured through network-level controls"* (authentication.md:15-21). No static-token/bearer mode exists. Given our host-network + host-firewall (tailnet-only) deployment, leaving it off is a coherent posture; if we ever publish it through the edge, enabling OAuth2 against Cloudflare Access's JWT issuer is the idiomatic move.

**Index/refresh strategy (verified):** refresh is ETag-based — pages stored with ETags, refresh sends `If-None-Match`, 304 = skip, 200 = re-process, 404 = delete (`refresh-architecture.md:31-58`); it is a full re-crawl with conditional fetches (line 164) and is invoked via tool/operation, not scheduled. There is no upstream "auto-refresh" flag; scheduled refresh would be ours to add (inferred). Scraper defaults already block private-network targets (`security.md:26-32`), which is the right default; `DOCS_MCP_SCRAPER_*` overrides are only needed for internal-host scraping.

### Gaps

| Gap | Why | Citation |
|---|---|---|
| None required. | All set vars are effective; defaults (scraper security, refresh) are already the safe/idiomatic ones. | security.md:26-32, refresh-architecture.md |
| Optional: `DOCS_MCP_READ_ONLY=true` | If the tailnet consumers should never trigger scrapes, read-only mode exists (`config.ts:436`). Operator choice, not a defect. | config.ts:436 |

**No-ops found:** none.

---

## 4. Idiomatic defaults for this deployment (private single-operator tailnet + Caddy edge + Cloudflare Access)

*(inference from the verified facts above)*

1. **degoog:** set `DEGOOG_DISTRUST_PROXY = false` (trust Caddy), keep `PUBLIC_INSTANCE=false`, keep the settings password in sops. Optionally pin `DEGOOG_BASE_URL` to the canonical tailnet URL.
2. **hindsight:** keep `pgvector` + local BGE embeddings (full image default), external LLM via the OpenAI-compatible router; add `HINDSIGHT_API_WORKER_ID` and consider `HINDSIGHT_API_MCP_AUTH_TOKEN`. Rely on network-level protection for the REST API and control plane, since neither has native auth.
3. **docs-mcp:** keep `http` protocol, `/data` store, telemetry off, gateway embeddings; keep OAuth2 off while tailnet-only, and remember `/api` is never OAuth-protected so it must never leave the network boundary.

---

## Contradictions

- The upstream Nix module's option default is `DEGOOG_DISTRUST_PROXY = false` (trust proxies, `module.nix:199`) while the *application* env default (var unset) is distrust (`request.ts:9-10`). Not a source conflict — different layers — but it is exactly the trap our config fell into: our `true` matches neither default's intent for a proxied deployment.
- Upstream bot-trap's hint message (`bot-trap.ts:57`) says *"set DEGOOG_DISTRUST_PROXY=0 to enable real IP detection"*, which is consistent with `request.ts` (`"0"` ⇒ trusted) but reads as if the var were normally enabling distrust — consistent once the double-negative is understood.

## Missing evidence / unverified

- Whether Caddy in `modules/web/ingress-runtime.nix` sets `X-Forwarded-For`/`-Proto` for these routes (it is a Caddy edge, which does by default — inferred, not verified against the rendered Caddyfile).
- Exact behavior of hindsight's `HINDSIGHT_ENABLE_*` inside the published image entrypoint for digest `3edcb6…` was read from the tag's `start-all.sh`/`Dockerfile`, not from the image itself (same tag, so high confidence).
- docs-mcp embedding-model change semantics for an existing store (re-index required) is inferred from "must match the name recorded in the store", not tested.

## Sources

**Kept (primary):**
- degoog source at pin: `src/server/utils/request.ts`, `public-instance.ts`, `public-url.ts`, `base-url.ts`, `bot-trap.ts`, `server-settings.ts`, `routes/settings-auth.ts`, `routes/pages.ts`, `routes/setup.ts`, repo `AGENTS.md:68`, `README.md`, `third-party/nix/module.nix`
- hindsight v0.10.0: `hindsight-api-slim/hindsight_api/config.py`, `api/http.py`, `docker/standalone/{Dockerfile,start-all.sh}`, `hindsight-control-plane/src/lib/hindsight-client.ts`, `hindsight-docs/docs/developer/{installation,configuration,models,extensions,storage}.{md,mdx}`
- docs-mcp-server v3.1.0: `src/utils/config.ts`, `src/services/mcpService.ts`, `src/store/embeddings/EmbeddingFactory.ts`, `docs/infrastructure/{authentication,deployment-modes,security,telemetry}.md`, `docs/guides/embedding-models.md`, `docs/setup/configuration.md`, `docs/concepts/refresh-architecture.md`
- Repo: `modules/knowledge/{degoog,hindsight,docs-mcp}.nix`, `policy/oci-images.nix`, `flake.lock`, `modules/hosts/home-forge/_nixos.nix`

**Rejected:** none — no secondary/blog sources were needed; all claims trace to the pinned source trees.

## Next steps

- Verify the rendered Caddyfile forwards `X-Forwarded-*` to the degoog origin before flipping `DEGOOG_DISTRUST_PROXY`.
- If hindsight's API/CP will ever be reachable beyond loopback-plus-firewall, decide between `HINDSIGHT_API_MCP_AUTH_TOKEN` (MCP only) and a TenantExtension (full API-key auth) — there is no native REST bearer option.
