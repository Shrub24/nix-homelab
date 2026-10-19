# Optional features: Actual Budget, Memos, tududi

Read-only research for the three apps being deployed on `oci-melb-1`. No configuration, secrets or live hosts were touched. Reuses `docs/research/actual-memos-tududi-upstream-facts.md` for OIDC and image facts; this file does not repeat those.

## 0. Versions and sources

| App | Deployed version (source of pin) | Source tree read |
|---|---|---|
| Actual Budget | `actual-server` 26.10.0 (`nix eval` on nixpkgs `6510408d`) | tag `v26.10.0`, commit `2bebdbaa` |
| Memos | 0.31.0 (`nix eval` on nixpkgs `6510408d`) | tag `v0.31.0`, commit `2b2192d4` |
| tududi | image `1.9.1` (`policy/oci-images.nix:36`) | tag `v1.9.1`, commit `f270f38` |
| Bifrost | 2.2.6 (`pkgs/bifrost/default.nix:31`, nix-fleet `e5d74415`) | upstream `8b4fce4f` (`transports/v2.2.6`) |

Discrepancy in the upstream-facts brief: its §2 names tududi `v1.9.1` tag commit `2bebdbaa…`. That is Actual's commit. The tududi tag resolves to `f270f38` ("release: v1.9.1"). The brief should be corrected; no value in it depends on the wrong hash.

Labels: **[source]** = read in the pinned tree; **[doc]** = upstream documentation at the same tag; **[inf]** = inference, not tested; **[unverified]** = not confirmed.

## 1. Capability matrix

| Capability | Actual 26.10.0 | Memos 0.31.0 | tududi 1.9.1 |
|---|---|---|---|
| Database | SQLite only | SQLite (default), MySQL, **PostgreSQL** | SQLite (default), **PostgreSQL** (opt-in) |
| CalDAV | **None** | **None** | **Yes**: CalDAV server and remote-calendar sync client |
| AI | **None** | Speech-to-text only (`Transcribe`) via OpenAI-type or Gemini providers | Chat-completions assistant via any OpenAI-compatible base URL |
| Bifrost fit | n/a | Transcription only; no route configured for it (§4.2) | Chat completions: good fit, `LLM_BASE_URL` (§4.3) |
| Bank sync | Yes: GoCardless, SimpleFIN, Pluggy, Enable Banking, Akahu (external services, not LLM) | n/a | n/a |

## 2. Actual Budget (26.10.0)

### 2.1 PostgreSQL: not supported
- **[source]** `packages/sync-server/package.json:96` depends on `better-sqlite3`; `packages/sync-server/src/db.js:1` imports it. No `pg` or other Postgres driver appears in the sync-server dependencies. Actual stores server state in SQLite only.
- Not useful as a plan item: there is no knob to change this.

### 2.2 CalDAV: not supported
- **[source]** No `caldav`, `carddav` or `ical` code in `packages/` at this tag (searched all `*.ts`, `*.js`, `*.md`, `*.json`).

### 2.3 AI: not supported
- **[source]** No `openai`, `ollama`, `LLM` or chat-completion client code in `packages/sync-server/src`, `packages/loot-core/src` or `packages/desktop-client/src`.
- **[source]** `packages/sync-server/src/app-pluggyai/` is a bank-data aggregator (Pluggy), not a language model. The name is a false friend.
- The only AI mention in the docs is contributor policy (`packages/docs/docs/contributing/ai-usage-policy.md`) and a release-automation PR (`releases.md`, #5182). Neither is a runtime feature.

### 2.4 Optional integrations
- Bank sync providers (`app-gocardless`, `app-simplefin`, `app-pluggyai`, `app-enablebanking`, `app-akahu`) need external accounts and outbound HTTPS. None is required for a self-hosted budget. Out of scope for this homelab's first deployment.
- `ACTUAL_OPENID_*` and login methods: covered by the existing brief §1; not repeated here.

### 2.5 Mandatory vs optional
- Mandatory for this deployment: already in the placement (OIDC client, `server_hostname`, loopback listener, SQLite export).
- Optional: bank sync (external), none of the others exist.

## 3. Memos (0.31.0)

### 3.1 PostgreSQL: supported, not useful here
- **[source]** `internal/profile/profile.go:29`: driver is `sqlite, mysql, postgres, or d1`. `cmd/memos/main.go:63` exposes `--driver`, default `sqlite`. Env mapping is `MEMOS_DRIVER` / `MEMOS_DSN` (viper, `cmd/memos/main.go:95–97`).
- **[source]** `store/db/postgres/postgres.go:27` opens the DSN with `sql.Open("postgres", profile.DSN)`, using `lib/pq`. The DSN is a libpq-style connection string and contains the password.
- **[source]** `AGENTS.md:120`: schema changes must land in SQLite, MySQL and PostgreSQL migrations. PostgreSQL is a maintained backend, not a stub.
- **[inf]** Not useful for this deployment: a single-user instance with WAL-aware SQLite export already works. PostgreSQL would add a role, a secret DSN, a consumer registration and a different backup path (`pg_dump` replacing the `sqlite3 .backup` export in `modules/apps/memos.nix`). Only worth it if Memos should share the fleet's Postgres cluster.
- **[unverified]** No SQLite→PostgreSQL data-migration tool was found in the 0.31.0 tree (searched for `migrat` near `sqlite`/`postgres`; only changelog and ADR text matched). Treat switching drivers on an existing database as unsupported until checked.
- **[unverified]** Minimum PostgreSQL server version: not stated in the code or docs read.

### 3.2 CalDAV: not supported
- **[source]** No CalDAV or CardDAV server or client code in non-generated Go. The only matches are generated `*.pb.go` files.

### 3.3 AI: transcription only
- **[source]** The only AI RPC is `AIService.Transcribe` (`proto/api/v1/ai_service.proto`, `POST /api/v1/ai:transcribe`). No chat, summarisation or completion feature exists in 0.31.0.
- **[source]** `server/api/v1/ai_service.go:112–119`: provider type `OPENAI` → `stt/openai` (`/audio/transcriptions`); `GEMINI` → an audio-LLM path (`audiollm/gemini`, a generate-content request, not Bifrost's transcription route). Any other type is rejected.
- **[source]** `provider/ai/ai.go:7–10`: only `OPENAI` and `GEMINI` provider types exist. A "custom" endpoint is possible only through the `OPENAI` type's `endpoint` field.
- **[source]** `provider/ai/models.go:7`: default transcription model for `OPENAI` is `whisper-1`.
- **[source]** `provider/ai/stt/openai/openai.go:20,81–89`: default endpoint `https://api.openai.com/v1`; the endpoint is normalised by trimming the trailing slash only.
- **[source]** Endpoint validation: `store/deployment_config.go:300–330` and `server/api/v1/instance_service_validation.go:106–111` accept any string and only default an empty value. I found no scheme, host or private-address restriction on the AI endpoint in these paths. (Checked the validators; the SDK behaviour on a plain `http://` origin was not run.)

### 3.4 Configuration knob: file-provisioned AI
- **[doc]** `docs/configuration-provisioning.md:96`: `memos-instance-setting-ai.json` provisions the `AI` instance setting from `/etc/secrets` ("AI providers, API keys, and transcription defaults", line 239). The file name rule is at `store/deployment_config.go:33`.
- **[doc]** Only one file may declare a given setting key; a file replaces the whole setting group (lines 246–251). Once this file exists, the UI cannot change the AI settings.
- **[source]** Validator fields (`normalizeDeploymentAISetting`, `store/deployment_config.go:300–330`): `providers[]` with `id`, `title`, `type` (`OPENAI`/`GEMINI`), `endpoint`, `apiKey`; and `transcription` with `providerId`, `model`, `language`, `prompt`. The JSON names are protobuf-JSON camelCase of these fields (**[inf]**, from the proto accessors; not written out as a sample).
- The file holds `apiKey` in plaintext. Treat it as a secret file, like the IdP file.

### 3.5 Bifrost: not configured for transcription
- **[source, Bifrost 8b4fce4f]** `/v1/audio/transcriptions` is the OpenAI-compatible route (`core/providers/openai/openai.go:2957`), so a Memos `OPENAI`-type provider with `endpoint = http://<bifrost>:<port>/v1` would reach the right path (openai-go appends `/audio/transcriptions`) **[inf]**.
- **Providers with a transcription method at the pin:** a grep for `TranscriptionRequest` lists about 35 provider directories, but that counts type references, not implementations. Confirmed implementations among the fleet's providers: `gemini` (`core/providers/gemini/gemini.go:1678`) and `openrouter` (`openrouter.go:503`, via the OpenAI handler). **Not** `deepseek`: `core/providers/deepseek/deepseek.go:428–429` returns `NewUnsupportedOperationError`. `voyage` and `opencode-go` were not checked for their own implementations.
- **Fleet policy blocks the only voice-capable route:**
  - `voyage` is a custom provider with `allowed_requests` set to `{list_models: false, embedding: true}` (`policy/bifrost-config.json`). A non-nil `AllowedRequests` denies every operation not set `true` (`core/schemas/provider.go:334–335`), so transcription is denied on Voyage.
  - Routing aliases in `policy/bifrost-config.json` are `shrublab-text`, `shrublab-embedding`, `shrublab-image`, `shrublab-fallback`. None is a speech alias, and the `text` target is `opencode-go/deepseek-v4.1-flash`, which is chat-only.
- **Model naming:** `core/schemas/utils.go:99–110` splits a `provider/model` only when the prefix is a known provider; otherwise the default provider applies. Memos' default `whisper-1` would therefore need an explicit provider prefix in Bifrost **[inf]**, and the default provider for an unprefixed audio request is **[unverified]**.
- **Gemini via Bifrost:** Memos' `GEMINI` type uses a generate-content request to `generativelanguage.googleapis.com/v1beta`-style endpoints, not the OpenAI transcription route. Routing it through Bifrost would need Bifrost's `/genai/*` passthrough to match Memos' SDK path. **[unverified]**, not tested.
- **Conclusion:** Memos transcription via Bifrost is **not usable as configured**. It needs (a) a Bifrost transcription-capable route with an explicit speech model and (b) a policy entry, and it needs a live test. A chat alias such as `shrublab-text` cannot serve Memos, because Memos only calls `/audio/transcriptions`.

### 3.6 Other optional settings
- **[doc]** `docs/configuration-provisioning.md:91–96`: `ACCESS`, `GENERAL`, `STORAGE`, `MEMO_RELATED`, `NOTIFICATION` (SMTP) can also be file-provisioned. `BASIC` and `TAGS` cannot.
- **[doc]** `memos-instance-setting-general.json` with `disallowPasswordAuth` is needed for an SSO-only deployment (lines 117–118). Relevant to the IdP file already planned.
- **[inf]** `modules/apps/memos.nix` sets `MEMOS_DRIVER = "sqlite"` and the SQLite-specific backup. Enabling PostgreSQL or AI requires changing those, not just adding options.

## 4. tududi (1.9.1)

### 4.1 PostgreSQL: supported, opt-in, with a migration caveat
- **[source]** `backend/config/database-settings.js:3–5`: SQLite is the default; PostgreSQL is selected by `DATABASE_URL=postgres://…` or `DB_DIALECT=postgres`. Discrete `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_SSL`, `DB_SSL_REJECT_UNAUTHORIZED`, `DB_POOL_MAX` (default 10) are read at lines 36–50.
- **[source]** `package.json:174`: `pg` is a runtime dependency, so the image ships the driver.
- **[doc]** `docs/16-postgresql.md`: requires PostgreSQL 14 or newer, an existing database and a role that can create tables. First start runs `sequelize.sync()` on an empty database and records historical migrations as applied; the historical SQLite-only migrations are never replayed on PostgreSQL.
- **[doc]** "There is no built-in transfer of an existing SQLite database into PostgreSQL" (`docs/16-postgresql.md`, First Start). Only per-user JSON export/import works across engines. **This matters if the deployment ever moves an already-populated database.** For a fresh install it does not.
- **[doc]** Multi-process safety: schema and migrations take a PostgreSQL advisory lock; scheduled jobs and rate limits use the database (`docs/16-postgresql.md`, "Running More Than One Process"). A single container needs none of this.
- **[doc]** Backups: the SQLite file backup in `docs/backups.md` does not apply; use `pg_dump` (`docs/16-postgresql.md`, Backups). The fleet's `modules/apps/tududi.nix` backup is a SQLite export, so it would change.
- **Usefulness here:** single-user, single-container deployment. SQLite is the documented default and the right choice for a personal instance (`docs/16-postgresql.md`, Overview). PostgreSQL only pays off if tududi should join the fleet's Postgres substrate or run more than one process.
- **[inf]** A containerised tududi reaching the fleet's Postgres must use the service address (`host.services.internal`, `policy/globals.nix` `serviceNetwork`), and the `postgres` consumer's `allowedCIDRs` must include it. Not verified against `modules/database/postgres.nix`.
- **[inf]** `DATABASE_URL` includes the password, so it belongs in a secret env file, not `environment`.

### 4.2 CalDAV: supported in both directions; plan gate and private-host policy apply
- **[source] Server (tududi as CalDAV server):** routes are mounted unconditionally: `backend/app.js:245–247`. Discovery at `/.well-known/caldav`, calendar paths at `/caldav/<username>/` (`backend/modules/caldav/routes.js`).
- **[source] Auth, Basic:** `backend/modules/caldav/middleware/caldav-auth.js`: the Basic username is the account **email** (lowercased), and the password is checked with `bcrypt.compare` against `password_digest`. An account with no `password_digest` (an SSO-only account) always fails. Rate-limited per IP and username (`caldavAuthLimiter`).
- **[source] Auth, Bearer:** `Authorization: Bearer <token>` is accepted via `findValidTokenByValue` (`caldav-auth.js`). The token-creation path was not traced.
- **[source] Plan gate:** `backend/services/entitlementsService.js:326–330`: `hasFeature` returns `true` unless `TUDUDI_HOSTED_MODE=true`. Self-hosted instances are not gated by plan.
- **[source] Per-project calendars:** `CALDAV_PROJECTS_AS_CALENDARS` is read in `backend/modules/caldav/routes.js:17,109` (documented default `false`).
- **[source] Client (tududi syncs a remote CalDAV):** `backend/config/config.js:372–377` and `backend/modules/caldav/services/safe-request.js`. Remote calendars must use HTTPS and a public address, checked before every sync and on every redirect. `CALDAV_ALLOW_PRIVATE_HOSTS=true` lifts both rules and allows plain `http` **for LAN or loopback servers**.
- **[source] Credential encryption:** `backend/config/config.js:365–369` reads `ENCRYPTION_KEY`, falling back to `SECRET_KEY`. `docs/11-caldav-sync.md` says it falls back to `SECRET_KEY` as well; `.env.example` says `TUDUDI_SESSION_SECRET`. **These disagree.** Set `ENCRYPTION_KEY` explicitly to avoid depending on the fallback.
- **[source] Dead knob:** `CALDAV_ENABLED` appears only in `.env.example:186` and `.env.example:163`. No code reads it (searched the whole tree excluding `.env.example`). `docs/11-caldav-sync.md` says CalDAV "is enabled by default". **Setting `CALDAV_ENABLED=false` does nothing in 1.9.1.** Do not use it as an off switch.
- **[doc] Rate limits:** 60 requests/minute for CalDAV protocol, 5/minute for manual sync (`docs/11-caldav-sync.md`, Security).
- **[doc] Known limitations** (`docs/11-caldav-sync.md`): subtasks via `RELATED-TO` but not rendered by all clients; habit mode not visible externally; projects not shown externally unless `CALDAV_PROJECTS_AS_CALENDARS`; status collapsed from 7 to 4 values; large recurring sequences create many VTODOs.

**Deployment implications (inference, not tested):**
- The fleet places tududi on a `direct` route with Cloudflare Access off (`modules/apps/tududi.nix` header; D-091 in the upstream brief). CalDAV clients therefore reach the public origin with Basic or Bearer auth, which is the expected path for mobile clients.
- An OIDC-provisioned user (`OIDC_AUTO_PROVISION=true`) has no password, so **CalDAV Basic login will not work for SSO users**. They need a Bearer API token, or a bootstrap user with a password. The token-creation UI path was not verified.
- Remote sync to a Nextcloud or Radicale on the tailnet is blocked by default. It needs `CALDAV_ALLOW_PRIVATE_HOSTS=true`, which also allows plain `http` for every remote calendar. Enable it only if such a server is wanted.

### 4.3 AI assistant: OpenAI-compatible chat, configurable to a custom origin
- **[source] Client:** `backend/modules/ai-assistant/service.js:244` calls `client.chat.completions.create(...)`, using the `openai` npm package `^6.45.0` (`package.json:172`).
- **[source] Config resolution:** `service.js:57–67`. API key: per-user DB value, then `LLM_API_KEY`, then `OPENAI_API_KEY`. Base URL: per-user DB value, then `LLM_BASE_URL`, then `OPENAI_BASE_URL`. Model: per-user, then `LLM_MODEL`, then `TUDUDI_AI_MODEL`, default `gpt-4o-mini`.
- **[source] SSRF guard asymmetry:** `service.js:76–78,110–122`: a per-user `ai_base_url` is refused if it resolves to a private or internal address. An operator's `LLM_BASE_URL` is **not** guarded. This is what allows a tailnet or loopback Bifrost origin via `.env`/secret env.
- **[source] Token limits:** `service.js` sends `max_tokens` and retries once with `max_completion_tokens` on rejection; `docs/13-ai-assistant.md` confirms this. Per-feature caps via `LLM_MAX_TOKENS_*`.
- **[source] Structured output:** the requests use `response_format`; on rejection the call retries without it (`docs/13-ai-assistant.md`, Architecture/callWithFallback). Empty or invalid output falls back to empty-state defaults rather than erroring.
- **[doc] Base URL form:** `docs/13-ai-assistant.md` gives `LLM_BASE_URL=http://localhost:11434/v1` for Ollama; the `/v1` suffix is required because the SDK appends `/chat/completions`.
- **[doc] Hosted mode** (`TUDUDI_HOSTED_MODE=true`) disables per-user provider settings and requires `LLM_API_KEY`. Not applicable: this is a self-hosted deployment, so per-user and `.env` settings both apply.

**Bifrost compatibility (the question asked).** OpenAI-compatible *shape* is not the same as a working route. Checked against the pinned Bifrost source:
- **Route exists:** `/v1/chat/completions` is the OpenAI chat route (`core/providers/openai/openai.go:864`). The base URL should be `http://<bifrost-origin>/v1`.
- **Fleet route:** the tududi-relevant alias is `shrublab-text` (`policy/bifrost-config.json`, `summariser` rule), which targets `opencode-go/deepseek-v4.1-flash` with `gemini-flash-latest` and `deepseek-chat` as fallbacks. Set `LLM_MODEL=shrublab-text` **[inf]**; the alias name is the only model string Bifrost needs.
- **Not verified:** whether the routed providers honour `response_format` JSON schema. tududi retries without it, so a failure degrades rather than breaks, but output quality is untested.
- **Not verified:** whether Bifrost requires a virtual key for chat calls. The repo's ARCHITECTURE notes the gateway "authenticates no client" for docs-mcp (`ARCHITECTURE.md`, Documentation Index Flow, step 2), which would make a placeholder `LLM_API_KEY` sufficient. **[unverified]**, needs a live call.
- **Dialing:** from a container, the gateway is reached as a container-base URL (`host.services.internal`) per the repo's bifrost policy, or as `services.bifrost.localEndpoint` when co-located (D-087). `LLM_BASE_URL` is set through the secret env file because the API key is in the same file.

### 4.4 Mandatory vs optional (tududi)
- Mandatory: `OIDC_*`, `BASE_URL`, `TUDUDI_TRUST_PROXY`, `TUDUDI_ALLOWED_ORIGINS`, bootstrap admin, `TUDUDI_SESSION_SECRET` (all already planned; see the upstream brief §2).
- Optional, each independent: CalDAV (server works with no extra knob; set `ENCRYPTION_KEY` explicitly; `CALDAV_PROJECTS_AS_CALENDARS`; `CALDAV_ALLOW_PRIVATE_HOSTS` only for LAN servers); AI (`LLM_API_KEY`, `LLM_BASE_URL`, `LLM_MODEL`); PostgreSQL (`DATABASE_URL` in a secret file, changes backups).

## 5. Bifrost summary

| App | Uses Bifrost for | Works with the current fleet config? |
|---|---|---|
| Memos | Speech-to-text (`/v1/audio/transcriptions`) | **No.** No speech-capable route; Voyage denies it; DeepSeek does not implement it. Needs a new route and a live test. |
| tududi | Chat completions (`/v1/chat/completions`) | **Probably yes**, via `LLM_BASE_URL=http://<bifrost>/v1` and `LLM_MODEL=shrublab-text`. Not run live. |
| Actual | Nothing | n/a |

## 6. Open items and unverified claims

1. **[unverified]** Memos transcription through Bifrost: no live call; default provider for unprefixed audio model names; Gemini path via `/genai/*`.
2. **[unverified]** tududi chat through Bifrost: no live call; `response_format` acceptance on the routed providers; whether Bifrost needs a virtual key.
3. **[unverified]** Memos PostgreSQL minimum version and absence of a SQLite→PostgreSQL migration tool (searched, not exhaustive).
4. **[unverified]** tududi Bearer API token creation path, needed for SSO users' CalDAV access.
5. **[unverified]** tududi `ENCRYPTION_KEY` fallback: `config.js` says `SECRET_KEY`; docs say `TUDUDI_SESSION_SECRET`. Read the actual `secretKey` derivation before relying on either.
6. **[unverified]** The fleet's Postgres server major version (not read); tududi needs 14+, Memos PostgreSQL minimum unknown.
7. **[inf]** Memos file-provisioned AI blocks UI edits for the whole `AI` setting group (docs line 246–251).
8. **Not performed:** no live login, no container run, no Bifrost call, no edits to `policy/`, `modules/` or secrets.

## 7. Sources

Pinned source (shallow clones at the tags above, read-only):
- Actual `v26.10.0`: `packages/sync-server/package.json:96`, `packages/sync-server/src/db.js:1`, `packages/sync-server/src/app-{gocardless,simplefin,pluggyai,enablebanking,akahu}/`, `packages/docs/docs/contributing/ai-usage-policy.md`, `packages/docs/docs/releases.md`.
- Memos `v0.31.0`: `internal/profile/profile.go:29`, `cmd/memos/main.go:63,95–97`, `store/db/postgres/postgres.go:27`, `AGENTS.md:12,120`, `proto/api/v1/ai_service.proto`, `server/api/v1/ai_service.go:48–124`, `provider/ai/ai.go:7–10`, `provider/ai/models.go:7`, `provider/ai/stt/openai/openai.go:20,81–89`, `store/deployment_config.go:33,283–330`, `server/api/v1/instance_service_validation.go:95–135`, `docs/configuration-provisioning.md:74–96,117–118,239–251`.
- tududi `v1.9.1`: `backend/config/database-settings.js:1–50`, `package.json:172,174`, `docs/16-postgresql.md`, `backend/app.js:245–247`, `backend/modules/caldav/routes.js:17,109`, `backend/modules/caldav/middleware/caldav-auth.js`, `backend/services/entitlementsService.js:326–330`, `backend/config/config.js:365–377`, `backend/modules/caldav/services/safe-request.js`, `docs/11-caldav-sync.md`, `.env.example:163–194`, `backend/modules/ai-assistant/service.js:57–67,76–78,110–125,244`, `docs/13-ai-assistant.md`.
- Bifrost `8b4fce4f` (`transports/v2.2.6`): `core/providers/openai/openai.go:864,2957`, `core/providers/gemini/gemini.go:1678`, `core/providers/openrouter/openrouter.go:503`, `core/providers/deepseek/deepseek.go:428–429`, `core/schemas/provider.go:334–335,402`, `core/schemas/utils.go:99–110`.

Repository:
- `policy/oci-images.nix:36`, `policy/bifrost-config.json` (providers, `voyage.allowed_requests`, `shrublab-*` routing rules), `modules/apps/actual.nix`, `modules/apps/memos.nix`, `modules/apps/tududi.nix`, `pkgs/bifrost/default.nix:31–36` (nix-fleet `e5d74415`), `ARCHITECTURE.md` (Bifrost and Documentation Index flows).

Web search: used only to locate Bifrost's documented routes. Those results came from the `dev` branch, so they were not used as evidence; all Bifrost claims above come from the pinned source.
