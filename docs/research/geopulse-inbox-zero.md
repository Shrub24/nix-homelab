# GeoPulse and Inbox Zero: packaging and deployment feasibility

Research only. No configuration, secrets, deployment or OpenSpec artifacts were changed.

## 1. Pinned sources

| Item | Repository | Revision | Date | Notes |
|---|---|---|---|---|
| GeoPulse | https://github.com/tess1o/geopulse | tag `v1.39.1`, commit `77e9c0eb071ac35674d40073b4b182e60bc3d176` | 2026-10-08 (commit) | Highest semver tag at research time. |
| Inbox Zero | https://github.com/elie222/inbox-zero | tag `v2.30.0`, commit `c7a640d51944f2eec5f08bd72c6ed57f777647d4` | 2026-05-18 (commit) | Annotated tag object `b7d59f47…` peels to this commit. Use the peeled commit. |
| nixpkgs (locked) | NixOS/nixpkgs | `6510408d147d8c5e6d76043e899e9251756f6a75` (`flake.lock`) | — | Used for package-presence checks below. |

Tag listings were taken with `git ls-remote --tags` and sorted with `sort -V`. Both repositories were shallow-cloned at the tags above.

## 2. Licenses and redistributability

**GeoPulse: Business Source License 1.1, not an OSI license.**
- `LICENSE` (repo root). Additional Use Grant: "Personal Use" only, defined as use by an individual for non-profit, private, or educational purposes.
- Forbidden: any "Commercial Purpose", including providing a service to third parties and "using the Licensed Work in a production environment for any business enterprise or commercial entity".
- Change Date `2075-01-01`, Change License AGPL-3.0-only. Until then, BSL terms apply.
- nixpkgs records `bsl11` as `spdxId = "BUSL-1.1"`, `free = false`, `redistributable = true` (`lib/licenses/licenses.nix:289-294`). A package would need an unfree allowance for consumers.
- **Redistribution risk (inference):** a Nix expression that fetches upstream source at build time does not redistribute GeoPulse. Pushing built GeoPulse closures into a cache that other parties can read may be redistribution. The fleet cache (`cache.shrublab.xyz`, ARCHITECTURE.md) must be checked for public readability before any GeoPulse closure is published.

**Inbox Zero: AGPL-3.0 with additional restrictions, plus a commercial `ee/` tree.**
- `LICENSE` lines 14-31: "COMMERCIAL MONETIZATION RESTRICTION" (no paid service or commercial product without written permission); "ENTERPRISE USE LIMITATION" (organisations of five or more employees, contractors or users using it for business must obtain an enterprise license). Exemptions cover personal, educational and research use, and organisations with fewer than five business users.
- `apps/web/ee/LICENSE.md`: the Inbox Zero Commercial License. Production use requires a valid Enterprise Edition subscription. Development and testing copies are permitted without one.
- **Dependency on `ee/` (direct evidence):** 13 non-`ee` files under `apps/web` import `@/ee/` (for example `app/api/stripe/webhook/route.ts`, `app/api/apple/webhook/route.ts`, `app/api/stripe/success/route.ts`). The published image is built from the full tree (`docker/Dockerfile.prod`), so the upstream image includes `ee/` code.
- The `ee/` clause is stated to cover only the parts not distributed under AGPLv3. Which files fall under it is therefore a legal question, not a build question. Removing `ee/` requires patching at least those 13 import sites, which is not a supported configuration.

## 3. GeoPulse

### 3.1 Build graph

| Component | Source | Toolchain | Inputs |
|---|---|---|---|
| Backend | `backend/` (Maven, parent `pom.xml`) | JDK 25 (`maven.compiler.release` 25, `pom.xml:14`), Quarkus 3.35.1 (`pom.xml:19`) | Maven Central only. No custom `<repositories>` in `pom.xml` or `backend/pom.xml`. |
| Frontend | `frontend/` (Vite, Vue 3, PrimeVue, MapLibre, Leaflet) | Node 20 in the upstream Dockerfile (`frontend/Dockerfile`: `node:20-alpine`). Vite 7/Node floor not verified. | `frontend/package-lock.json`: 770 `resolved` entries, all `https://registry.npmjs.org/…`. No git or URL dependencies found. |
| Frontend runtime | `frontend/Dockerfile`, `frontend/nginx.conf` | `nginx:stable-alpine` | Serves the static build; proxies `/api/` to `BACKEND_URL_PLACEHOLDER` (`nginx.conf:98-99`, replaced by `docker-entrypoint.sh:35`, default `http://geopulse-backend:8080`). |
| Backend native image | `backend/Dockerfile.native` | Mandrel 25 builder (`quay.io/quarkus/ubi-quarkus-mandrel-builder-image:25.0-java25`) | Native profile is optional. |
| Backend JVM image | `backend/Dockerfile` | `maven:3.9.11-eclipse-temurin-25`, runtime `eclipse-temurin:25-jdk-alpine` + `postgresql17-client` | Runs `mvn dependency:go-offline` then `mvn package -DskipTests -Dquarkus.profile=prod`. |

Notes:
- The upstream JVM Dockerfile runs `mvn dependency:go-offline` before source copy. That is the same dependency-prefetch shape `buildMavenPackage` uses. Whether the Quarkus 3.35.1 build resolves fully offline has not been tested.
- The runtime image installs `postgresql17-client`, because the full-backup feature needs `pg_dump`/`pg_restore` matching the server (`backend/Dockerfile`, comment on the `apk add` line).

### 3.2 nixpkgs availability (locked revision `6510408d`)

| Need | Present | Source |
|---|---|---|
| Maven builder | Yes, `buildMavenPackage` with `fetchMavenArtifact` | `pkgs/by-name/ma/maven/build-maven-package.nix` |
| JDK 25 | Yes, `openjdk25`, `temurin-bin-25` | `pkgs/top-level/all-packages.nix:3015, 3694` |
| GraalVM (native profile) | Yes, `graalvmPackages` | `pkgs/top-level/all-packages.nix:3745` |
| Node 24 / pnpm 11 | Yes | `nodejs_24` (`:2310`), `pnpm_11` (`:2672`) |
| PostgreSQL 17 + PostGIS | PostgreSQL 17 (`postgresql_17_jit`, `:7399`); PostGIS **3.6.4** | `pkgs/servers/sql/postgresql/ext/postgis.nix:38` |

Version delta: upstream's compose uses `postgis/postgis:17-3.5` (`docker-compose.yml:70`). nixpkgs ships 3.6.4. The migrations only call `CREATE EXTENSION IF NOT EXISTS postgis` and `postgis_topology` (`backend/src/main/resources/db/migration/V1.0.0__Initial_schema.sql` and later migrations). Running 3.6.4 is untested.

### 3.3 Minimal derivation plan

1. **Backend (JVM first).** `buildMavenPackage` over `pom.xml` with `mvnHash` pinned, `mvn package -DskipTests -Dquarkus.profile=prod`, install `target/quarkus-app/`. Runtime needs `postgresql_17` client tools on `PATH` or `GEOPULSE_BACKUP_BINARY_DIRECTORY` set.
   - Native image (`-Pnative`) is a second step. Upstream documents an arm64 native path with `-march=armv8-a` (`Dockerfile.native`), but nixpkgs GraalVM on aarch64 has not been tested here.
2. **Frontend.** `buildNpmPackage` over `frontend/` with `npmDepsHash`, run `npm run build` (Vite), install `dist/`. Serve through the NixOS `services.nginx` module with the upstream `nginx.conf` proxy rules rewritten to the native backend port.
   - Runtime config: upstream writes `window.VUE_APP_CONFIG = { API_BASE_URL: '/api' }` at container start. The NixOS version writes the same file via `environment` or a tmpfile.
3. **Database.** Use the existing PostgreSQL consumer contract (`modules/database/postgres/_consumer.nix`): `extensions = ps: [ ps.postgis ]`, `setupSQL` with `CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS postgis_topology;`. Whether the consumer role can create these extensions has not been checked against `modules/database/postgres.nix`.
   - Upstream's arm64 PostGIS note (`docs-website/docs/getting-started/deployment/docker-compose.md:166-177`) applies only to the compose image. A native cluster from nixpkgs does not hit that issue.

### 3.4 Ports, state, secrets

| Item | Value | Source |
|---|---|---|
| Backend HTTP | 8080 | `backend/src/main/resources/application.properties` (`quarkus.http.port=8080`) |
| Frontend | 8080 (non-root) or 80 (root); compose publishes 5555 | `frontend/docker-entrypoint.sh`, `docker-compose.yml` |
| JWT keys | `/app/keys/jwt-private-key.pem`, `/app/keys/jwt-public-key.pem` (RSA, generated) | `application.properties` (`smallrye.jwt.sign.key.location`, `mp.jwt.verify.publickey.location`); `docker-compose.yml:2-25` |
| AI encryption key | `/app/keys/ai-encryption-key.txt` (base64 32 bytes, generated) | `GEOPULSE_AI_ENCRYPTION_KEY_LOCATION` default; `docker-compose.yml:20-25` |
| Backups | `/data/geopulse-backups` (volume), work path `…/.work` | `docker-compose.yml:43`; `geopulse.backup.work-path` |
| Import drop | `/data/geopulse-import` | `docker-compose.yml:42` |
| Database | `GEOPULSE_POSTGRES_URL`, `_USERNAME`, `_PASSWORD` | `application.properties` (`quarkus.datasource.*`) |

Homelab mapping (inference): state under `/srv/data/geopulse/{keys,backups,import}`; keys stored as sops secrets and materialised at activation, not in the Nix store and not generated by an unmanaged keygen step.

Secret-generation caveat: upstream generates the RSA and AI keys at first start (keygen container). The operator should generate and store them in sops, following the repository secret rule.

### 3.5 Runtime dependencies and external services

**Mandatory**
- PostgreSQL with PostGIS (Flyway migrations run at start).

**Default-on but external (configurable)**
- Geocoding: OSM Nominatim at `https://nominatim.openstreetmap.org` (`quarkus.rest-client.nominatim-api.url`). Forward search on the public host is off by default (`geocoding.nominatim.public-host-forward-search-enabled=false`).
- Weather: `geopulse.weather.primary-provider=OPEN_METEO` (default). Weather enrichment is on by default; historical backfill is admin opt-in (upstream README).
- Map tiles: the frontend nginx proxies OSM tile servers (`frontend/nginx.conf:65`). This is a runtime dependency of the browser map, and it goes outside the fleet.

**Optional**
- MQTT (OwnTracks): `geopulse.mqtt.enabled` default `false`; needs a broker (upstream uses Mosquitto in `docker-compose-complete.yml`).
- Immich and Memos integrations, additional geocoders (Google, Mapbox, Geoapify, ChibiGeo), and OIDC login (`geopulse.oidc.enabled` default `false`, `application.properties:555`). The OIDC provider keys beyond the flag were not enumerated in this pass.

**Ingest sources**: OwnTracks (HTTP or MQTT), Overland, Dawarich, GPSLogger, Home Assistant, Traccar, Colota. Phone clients need reachability to the backend ingest endpoint.

### 3.6 Architecture support (aarch64)

- Upstream documents native backend images for AMD64 and ARM64, including Raspberry Pi (`docs-website/.../docker-compose.md:126-131`). Compatibility variant: `armv8-a+nolse` for Raspberry Pi 3/4.
- Upstream frontend ARM64 build exists: `.github/workflows/dev-build.yml:45-73` (job `build-frontend-arm64`, `platforms: linux/arm64`). That workflow is the dev pipeline, not the release pipeline.
- Java 25 has arm64 builds (Temurin, `openjdk25`). Quarkus JVM output is architecture-neutral bytecode.
- Not verified on this host: the actual memory footprint on `oci-melb-1`. The README says "typically under 100MB RAM" (marketing claim, not measured here).

### 3.7 Blockers and open decisions (GeoPulse)

1. **License.** BSL "Personal Use" only. Confirm that the homelab use fits "private" or "non-profit" personal use. Confirm the fleet cache does not expose GeoPulse closures publicly.
2. **Packaging of a BSL package.** Needs `free = false` allowance. An upstream flake contribution would ship a Nix expression only, not binaries; nixpkgs inclusion is a separate policy question not checked here.
3. **Native vs OCI first deployment.** Native backend is practical in principle (dependencies resolve from Maven Central and npm registry), but the offline Maven/npm builds and PostGIS 3.6.4 behaviour are untested. The upstream arm64 digest-pinned OCI image is a lower-risk first step, following the tududi pattern (`modules/apps/tududi.nix:108-110`, `repo.ociImages`).
4. **Public ingress for OwnTracks and mobile clients.** The Tailscale-first baseline means phones need the tailnet, or a public route. Decision needed.

## 4. Inbox Zero

### 4.1 Build and image

- Production image: `docker/Dockerfile.prod`. Base `node:24-alpine`, pnpm 11.0.9, Next.js 16.2.6 standalone output (`apps/web/next.config.ts:52`, only when `DOCKER_BUILD=true`), Prisma 7.8.0 (`pnpm-lock.yaml`; the runner separately installs `prisma@7.3.0` globally, a version mismatch).
- Build uses `pnpm install --no-frozen-lockfile --prefer-offline --shamefully-hoist` (`Dockerfile.prod`). The non-frozen install means the lockfile is not enforced at build time, so a native Nix build would need a frozen lockfile and a verified sync first.
- Build-time placeholders: `NEXT_PUBLIC_*` values use `…_PLACEHOLDER` defaults. `docker/scripts/start.sh` runs `replace-next-public-placeholders.sh` at container start, so public env values are runtime-configurable in the official image.
- Entrypoint: `CMD ["/app/docker/scripts/start.sh"]`. Migrations run via `migrate.sh`; a migration failure logs a warning and startup continues (`start.sh`). `SKIP_DB_MIGRATIONS=true` disables migrations.
- Worker: `docker/scripts/start-worker.sh` runs `node /app/apps/worker/src/index.mjs`. Worker dependencies: `bullmq`, `ioredis` (`apps/worker/package.json`).
- Dev entrypoint `apps/web/entrypoint.sh` (`pnpm install`, `prisma migrate dev`, `pnpm run dev`) is not used by the production image.

### 4.2 Architecture support (aarch64)

- CI publishes multi-arch images: `.github/workflows/build_and_publish_docker.yml:70` `platforms: linux/amd64,linux/arm64`.
- Not verified here: that the `v2.30.0` tag has a published image in GHCR, and that the digest for `linux/arm64` runs on `oci-melb-1`. Pinning requires a registry lookup at implementation time.
- The README says formal releases use version tags and `latest` tracks `main`. Pin the digest, not `latest`.

### 4.3 Minimal runtime graph

**Required by the code (zod schema in `apps/web/env.ts`, non-optional fields)**

| Variable | Line | Notes |
|---|---|---|
| `DATABASE_URL` | 39 | PostgreSQL URL (`z.string().url()`). Schema: `provider = "postgresql"` (`apps/web/prisma/schema.prisma:2`). |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | 67-68 | Required by the schema even for a Microsoft-only setup. |
| `EMAIL_ENCRYPT_SECRET`, `EMAIL_ENCRYPT_SALT` | 81-82 | Required. Rotation likely invalidates stored encrypted values (inference; not tested). |
| `GOOGLE_PUBSUB_TOPIC_NAME` | 163 | Required by the schema (`min(1)`). |
| `INTERNAL_API_KEY` | 234 | Required. |
| `DEFAULT_LLM_PROVIDER` | ~84 | Enum; required by the schema. |

**Optional, with defined behaviour**
- `AUTH_SECRET` / `NEXTAUTH_SECRET` (`env.ts:47-48`): optional in the schema. Runtime requirement by Better Auth not verified.
- `CRON_SECRET` (`env.ts:224`): optional in the schema. Compose's cron sidecar calls `/api/cron/*` with it (`docker-compose.yml`, cron service).
- `QUEUE_BACKEND`, `QSTASH_*`, `REDIS_URL`: see §4.4.
- `UPSTASH_REDIS_URL` / `UPSTASH_REDIS_TOKEN` (`env.ts:145-152`): optional. Used for rate limiting; without them rate limiting returns "not limited" (`apps/web/utils/rate-limit.ts:32-38`).
- `REDIS_URL` (`env.ts:153`): used by BullMQ and subscriptions.

**Services**
- Mandatory: PostgreSQL (extensions `uuid-ossp` and `btree_gist`, `apps/web/prisma/migrations`, 214 migration directories).
- Web: `node apps/web/server.js` on port 3000 (`docker-compose.yml`, `web` service; `start.sh`).
- Worker: optional, see §4.4.
- Scheduler: the compose `cron` service is an alpine loop curling `/api/cron/scheduled-actions`, `/api/cron/automation-jobs` and `/api/follow-up-reminders` every 900 seconds. In NixOS this is a systemd timer (inference, matching the homelab's native patterns).

### 4.4 Queue and Redis

Queue backend selection (`apps/web/utils/queue/backend.ts:3-9`): `QUEUE_BACKEND` if set; else `qstash` if `QSTASH_TOKEN`; else `internal`.

- **`internal` (default):** no Redis, no worker. Work runs as internal API calls (`dispatch.ts:60-68`, result `internal-fallback`). Upstream says this "lacks built-in retries, deduping, and queue-level backpressure" (`docs/hosting/self-hosting.mdx`, "Optional: Background Job Backends").
- **`bullmq`:** requires `REDIS_URL` (`dispatch.ts:42-58`); without it the code logs a warning and falls back to the internal path. Requires the worker process.
- **`qstash`:** Upstash managed queue. Not self-hosted.

Redis is therefore optional for a minimal first deployment. A native Redis instance follows the Latitude precedent (`modules/observability/latitude.nix`, `services.redis.servers.latitude`), if BullMQ is chosen.

### 4.5 OAuth and webhook integrations

**Google (required by the schema even for a personal account)**
- OAuth client: "Web application"; authorized redirect `http://localhost:3000/api/auth/callback/google` (`docs/hosting/google-oauth.mdx`, line 27; replace with the public domain in production). Client type: External, with the operator added as a test user. Unverified apps show a warning screen and are limited to test users (`google-oauth.mdx`, step 5).
- Scopes in code (`apps/web/utils/gmail/*.ts`): `gmail.modify`, `gmail.settings.basic`, `calendar.*` (including `calendar.events`), `contacts`, `userinfo.email`, `userinfo.profile`.
- Google's scope table (`developers.google.com/gmail/api/auth/scopes`, fetched) lists `gmail.modify`, `gmail.settings.basic`, `gmail.readonly` and `gmail.compose` under **Restricted** scopes, which "require restricted scope OAuth App Verification". Production use for users outside the test list therefore needs Google verification. Whether a security assessment is also required was not confirmed from the page text (the fetched copy is truncated at that point).

**Gmail push (Pub/Sub)**
- Setup: a Pub/Sub topic, Gmail's publisher service account granted `Pub/Sub Publisher`, and a push subscription to `https://<domain>/api/google/webhook?token=<TOKEN>` (`docs/hosting/google-pubsub.mdx`, steps 1-4).
- `GOOGLE_PUBSUB_VERIFICATION_TOKEN` is checked as a query parameter. Setting it to an empty string disables that check, and the docs say this is intended only when upstream authentication already protects the route.
- Google's push documentation (`developers.google.com/gmail/api/guides/push`, fetched) describes two delivery modes: a webhook push (HTTP POST to your server) and a pull subscription that the app initiates. The Inbox Zero docs and the route in `apps/web/app/api/google/webhook` are webhook-only as far as was checked. A pull consumer was not found in this pass (not exhaustively searched).
- Watch renewal: Google requires a `watch` call at least every 7 days, and recommends daily (`guides/push`). Inbox Zero's renewal path was not inspected.

**Microsoft (optional)**
- `MICROSOFT_CLIENT_ID`, `MICROSOFT_CLIENT_SECRET`, `MICROSOFT_TENANT_ID` (default `common`), `MICROSOFT_BASE_URL` (`env.ts:72-75`), all optional.
- Outlook webhook: `apps/web/utils/outlook/watch.ts:12-14` builds `/api/outlook/webhook` and forces the scheme to `https:` when given `http:`. Microsoft Graph's public-endpoint requirement was taken from the code path and not checked against Microsoft's docs.

**Public exposure consequence**: both Gmail push and Outlook notifications POST to public HTTPS endpoints. Under the Tailscale-first baseline, the route cannot sit behind Cloudflare Access, because Google's POST would fail the Access gate. The precedent for a machine-facing route that opts out is `policy/web-services.nix:211` (`access.requireCloudflareAccess = false`, used by ntfy). Whether the webhook route is also covered by an origin-side token check is a policy decision.

### 4.6 LLM providers

- Provider enum (`apps/web/env.ts:6-19`): `anthropic`, `azure`, `vertex`, `google`, `openai`, `bedrock`, `openrouter`, `groq`, `aigateway`, `ollama`, `openai-compatible`, `codex-cli`, `claude-code`.
- `openai-compatible` (`apps/web/utils/llms/model.ts:249-262`): base URL from `OPENAI_COMPATIBLE_BASE_URL` (default `http://localhost:1234/v1`), model from `OPENAI_COMPATIBLE_MODEL` or `DEFAULT_LLM_MODEL` (missing model throws `DEFAULT_LLM_MODEL environment variable is not set`), key optional. The code sets `supportsStructuredOutputs: true`, so the endpoint must honour structured output requests.
- Fleet Bifrost (`policy/bifrost-config.json`) is OpenAI-compatible, so it is a candidate via `openai-compatible`. Whether Bifrost honours the structured-output request shape Inbox Zero sends is **not verified**. The GeoPulse AI feature and tududi both raised the same question; neither was tested here.
- Alternative: a hosted provider key (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, and so on), which avoids the untested Bifrost path.

### 4.7 Ports, state and backups

- Web port 3000 (`docker-compose.yml`; `docker/scripts/start.sh` `node apps/web/server.js`).
- State: PostgreSQL is the only stateful dependency found in the compose topology. The image mounts no volume. Local file state beyond the database was not searched for exhaustively.
- Backup contract: database export through the homelab PostgreSQL consumer and state-backups mechanism, following `modules/apps/tududi.nix:32` (state-backups consumer) and the export-first pattern from D-091.
- `NEXT_PUBLIC_BASE_URL` must match the public origin used by OAuth redirects.

### 4.8 Blockers and open decisions (Inbox Zero)

1. **`ee/` commercial license.** Production use of `ee/` code requires a subscription. Options: subscribe; strip `ee/` and patch the 13 import sites (unsupported); or do not run Inbox Zero. Owner decision.
2. **Enterprise limitation.** Organisations with five or more business users need an enterprise license. Confirm the homelab use case falls under the exemption.
3. **Google verification.** Restricted Gmail scopes. Test-user mode is sufficient for a single personal account (per upstream docs). Multi-user use needs verification.
4. **Public webhook endpoints.** Gmail push and Outlook notifications require public HTTPS POST routes, which conflicts with the no-public-ingress baseline. Decision needed on whether to expose one machine route with origin-side verification, or to find a pull-based design (not implemented upstream).
5. **LLM provider.** Hosted key versus Bifrost via `openai-compatible` (untested structured output support).
6. **Queue.** `internal` (no Redis, weaker durability; default) versus BullMQ with a native Redis (Latitude pattern).
7. **Placement.** Both apps run on `aarch64` upstream. Choice of host is a capacity decision not evaluated here.

## 5. Answers to the research questions

**Q1: How can GeoPulse be built as native Nix packages and operated as a NixOS service?**
- Feasible in principle, with no unsatisfiable source dependency found: Maven Central only, npm registry only, JDK 25 / Node / PostGIS available in the locked nixpkgs.
- Not proven: offline Maven and npm builds (no fixed-output hashes computed), PostGIS 3.6.4 against the upstream 3.5 schema path, and native image on aarch64.
- Licensing (BSL) is the most consequential blocker, ahead of build risk.
- Smallest maintainable first step: a spike of `buildMavenPackage` (JVM, not native) and `buildNpmPackage`, plus the PostgreSQL consumer. Alternatively, the upstream arm64 OCI images, digest-pinned, as an interim deployment.

**Q2: What minimal Inbox Zero container and native-service stack is required?**
- Web container (required) + PostgreSQL with `uuid-ossp`/`btree_gist` (required) + a scheduler (systemd timer replacing the compose cron sidecar).
- Worker container and Redis are optional; `internal` queue needs neither.
- Google OAuth client and Pub/Sub topic are required by the schema even when only one provider is used.

**Q3: Can both run on OCI aarch64, and what external OAuth and LLM services are necessary?**
- Yes for both at the upstream level: Inbox Zero's CI publishes `linux/arm64` (`build_and_publish_docker.yml:70`); GeoPulse documents ARM64 native images and has an arm64 frontend build (`dev-build.yml`). Not verified on `oci-melb-1` itself.
- External OAuth: Google (required by the schema), optionally Microsoft. Gmail push needs Google Pub/Sub; both providers' push paths need public HTTPS endpoints.
- External LLM: any provider, or an OpenAI-compatible endpoint (Bifrost candidate, untested).
- GeoPulse needs no OAuth to run. OIDC is optional.

**Q4: What is the smallest maintainable first deployment for each?**
- **GeoPulse:** PostgreSQL+PostGIS consumer, backend (JVM or digest-pinned arm64 OCI), nginx frontend, sops-managed JWT and AI keys, no MQTT, no OIDC, no geocoder keys. Ingest reachable on the tailnet only, with phones on Tailscale (decision §3.7.4).
- **Inbox Zero:** web container (digest pinned), PostgreSQL consumer, systemd timer for cron endpoints, `QUEUE_BACKEND` unset, Google OAuth test-user client, OpenAI-compatible or hosted LLM. No Pub/Sub until the public-endpoint decision is made, so the first deployment has no inbound mail sync. This is a functional limitation (inference from the Gmail push path).

## 6. Unverified claims and gaps

- GeoPulse native build offline completeness (Maven and npm fixed-output hashes): not computed.
- PostGIS 3.6.4 compatibility with GeoPulse migrations: not tested.
- GraalVM native image on aarch64 with nixpkgs: not tested.
- Whether Bifrost honours Inbox Zero's and GeoPulse's structured-output requests: not tested.
- Whether a single-user Google test-mode OAuth client can run without Pub/Sub: inferred from docs, not run.
- Inbox Zero `v2.30.0` arm64 image digest and presence in GHCR: not queried.
- Full set of OIDC keys for GeoPulse (`geopulse.oidc.*`) beyond the enable flag and callback base URL: not enumerated.
- Microsoft Graph's public-endpoint requirement for `notificationUrl`: taken from code, not checked against Microsoft's documentation.
- Whether the fleet cache is publicly readable (GeoPulse redistribution question).
- Memory footprint of either app on `oci-melb-1`.
- Whether the `consumer` role of the homelab PostgreSQL contract can create PostGIS extensions (`modules/database/postgres.nix` not inspected for the privilege model).

## 7. Reusable homelab patterns (no edits made)

- PostgreSQL consumer contract: `modules/database/postgres/_consumer.nix` (`password`, `allowedCIDRs`, `extensions`, `setupSQL`; lines 89, 112, 142, 153).
- Mixed native and container stack: `modules/observability/latitude.nix` (PostgreSQL consumer with `CREATEDB` at lines 356-381, native Redis at line 400, digest-pinned containers via `repo.ociImages`, Bifrost `localEndpoint` at line 63).
- Digest-pinned container: `modules/apps/tududi.nix:108-110`, with the state-backups consumer import at line 32.
- Machine-facing route opt-out: `policy/web-services.nix:211` (`access.requireCloudflareAccess = false`).
- Container environment invariant: `containers` aspect (ARCHITECTURE.md, D-077).
- Image policy: `policy/oci-images.nix`, consumed as `config.repo.ociImages.<name>`.

## 8. Decisions needed before proposing changes

1. Confirm GeoPulse BSL "Personal Use" fits the homelab, and whether a public flake or upstream contribution is wanted given BSL and the fleet cache.
2. Choose native backend (Nix derivation spike) or digest-pinned upstream arm64 OCI image for GeoPulse's first deployment.
3. Decide whether to accept the Inbox Zero `ee/` commercial terms, or to exclude Inbox Zero.
4. Decide the public-ingress policy for Gmail push and Outlook webhooks (single route opted out of Access with origin-side verification, or no inbound mail sync).
5. Choose the Inbox Zero LLM route: hosted key or the Bifrost `openai-compatible` path (requires a structured-output test).
6. Choose the Inbox Zero queue: `internal` (default) or BullMQ with native Redis.
7. Choose the placement host for each app.
8. Decide whether GeoPulse phones (OwnTracks) join the tailnet or a public ingest route is created.
