# GeoPulse deployment seams: Kanidm OIDC, device ingest, state, and native build contract

Research only. No configuration, secrets, live hosts, builds, or OpenSpec artifacts were touched. Follows `docs/research/geopulse-inbox-zero.md`, which is not restated here.

## 1. Pinned sources

| Item | Revision | Evidence |
|---|---|---|
| GeoPulse | `v1.39.1`, commit `77e9c0eb071ac35674d40073b4b182e60bc3d176` | Unchanged from the previous research. Shallow clone at the tag, source read directly. |
| Kanidm | `v1.9.1`, commit `36055fecac24482107c7f9b1c8815fda06bf4a43` | Book (`book/src/integrations/oauth2.md`) and server source (`server/lib/src/idm/oauth2.rs`) at the tag. Pin unchanged from the earlier Kanidm research. |
| GeoPulse license | `LICENSE` at the same GeoPulse tag | Read from the tagged clone, not from a summary. |

No pin change was needed.

## 2. Corrections to the previous GeoPulse research

- **OIDC is not switched on by the environment.** `geopulse.oidc.enabled` (`GEOPULSE_OIDC_ENABLED`, default `false`) is read only in the startup hook `OidcAuthenticationService.onStart`. It does not gate provider listing or login. Login exists only when a provider row exists in `oidc_providers`, and that row is created through the admin REST API, not from configuration (section 3.1).
- **The BSL redistribution statement was too strong.** The license text grants redistribution rights (section 7). The conditions are the Personal Use grant and the license-inclusion requirement. Whether a binary cache falls inside those conditions is a legal question, not something the source settles.
- **Flyway runs at start.** `quarkus.flyway.migrate-at-start=true` with 108 migration files. Each start applies pending migrations, so a database backup is required before any upgrade.

## 3. OIDC: how native GeoPulse logs in, and whether Kanidm can serve it

### 3.1 Provider is database state, not configuration

- Table `oidc_providers`, entity `admin/model/OidcProviderEntity.java`. Created by the admin API (`admin/dto/CreateOidcProviderRequest.java`).
- Fields the admin supplies: `name` (regex `^[a-z0-9-]+$`, 2 to 50 characters), `displayName`, `enabled` (default `true`), `clientId`, `clientSecret`, `discoveryUrl`, `icon`, `scopes` (default `openid profile email`).
- Discovery metadata is fetched at create or test time and cached. `metadata_valid` and `metadata_cached_at` record the cache state.
- `clientSecret` is stored as `client_secret_encrypted`, encrypted by `AIEncryptionService` with the key in `/app/keys/ai-encryption-key.txt` (key ID `v1`). See section 5.3.
- Consequence: the provider cannot be declared in Nix. Provisioning needs a one-time admin API call, and the encrypted secret then lives in the database and in backups.

### 3.2 Login and callback flow (as coded)

1. SPA calls `POST /api/auth/oidc/login/{provider}`. The backend creates an `OidcSessionStateEntity` with a 32-character state and a 32-character nonce, valid 10 minutes.
2. The authorization URL is built by string concatenation with no URL encoding: `response_type=code`, `client_id`, `redirect_uri`, `scope` (spaces replaced by `%20`), `state`, `nonce`. **There are no `code_challenge` or `code_challenge_method` parameters.** A search of the backend found no PKCE code anywhere.
3. `redirect_uri` is `<callback base>/oidc/callback`. That is the SPA route (`frontend/src/router/index.js:186`), not an API path. The callback base is resolved in order:
   - `auth.oidc.callback-base-url` (database setting, falling back to env `GEOPULSE_OIDC_CALLBACK_BASE_URL`; the first comma-separated value is used);
   - `GEOPULSE_PUBLIC_BASE_URL`;
   - `GEOPULSE_UI_URL` (deprecated);
   - the hardcoded fallback `http://localhost:5555`.
   If none of the first three is set, the redirect silently points at localhost.
4. The SPA route `/oidc/callback` posts `{code, state}` to `POST /api/auth/oidc/callback`.
5. The backend looks up the state (expired states are rejected), then exchanges the code at the token endpoint with `grant_type`, `code`, `redirect_uri`, `client_id` and `client_secret` **as form parameters** (`client_secret_post`).
6. ID-token validation (`validateAndExtractUserInfo`):
   - Signature: `SignedJWT`, key looked up by `kid` in the JWKS from discovery (`jwks_uri`, cached by TTL). The verifier is `RSASSAVerifier` with an `RSAKey` cast. **RS256 only.** ES256 is not supported, and the code's own TODO says so.
   - `iss` must equal the discovered issuer.
   - `aud` must contain `client_id`.
   - `exp` must be in the future.
   - `nonce` must equal the stored nonce.
   - `email` must be present and non-blank.
7. Identity mapping (section 3.4).

### 3.3 Kanidm side (v1.9.1)

Confirmed against the Kanidm book and source at the pinned tag:

| Requirement | Kanidm behaviour | Source |
|---|---|---|
| PKCE | Basic (confidential) clients have `enable_pkce = true` by default. A missing challenge in enforced mode is rejected (`PKCE code verification failed - no code challenge present in PKCE enforced mode`). Public clients always enforce PKCE. | `oauth2.rs:660-672`, `:1447-1449`; book "Extended Options for Legacy Clients" |
| Disabling PKCE | `kanidm system oauth2 warning-insecure-client-disable-pkce <client>`. Kanidm documents this as insecure for confidential clients, mitigated only by TLS and a secret that does not leak. | Book; FAQ |
| Signing algorithm | Each client advertises exactly one algorithm: ES256 by default, RS256 with `warning-enable-legacy-crypto <client>`. In legacy mode ES256 is not offered at all. | `oauth2.rs:2960-2961`; book |
| Token auth | Discovery advertises both `client_secret_basic` and `client_secret_post`. GeoPulse's form-body secret matches the advertised method. The token handler was not exercised. | `oauth2.rs:2885-2888` |
| `sub` | Account UUID. The code paths read use `OidcSubject::U(account_uuid)`. The enum's other variants were not inspected. | `oauth2.rs:1940`, `:2847` |
| `email` / `email_verified` | `email` comes from `mail_primary`, and `email_verified` is always `true` when a primary mail exists. A user without a primary mail gets no `email` claim, and GeoPulse then rejects the login. | `oauth2.rs:3143-3160` |
| `name` | From the account displayname. | `oauth2.rs` (claim assembly) |
| `picture` | Not emitted by Kanidm (no `picture` in the server). GeoPulse reads it but does not require it. | Source search, no hit |
| Scope gating | All requested scopes must be in the user's granted scope set, so `openid`, `profile` and `email` must each be mapped. Without a mapped group a user gets no token at all. | Book, "Scope Relationships" |

### 3.4 Identity mapping

- Connection key: `(provider name, sub)`. A returning subject goes straight to its user.
- A new subject with an email matching an existing user:
  - `auth.oidc.auto-link-accounts` default `false`: the callback throws `OidcAccountLinkingRequiredException` and the user must verify with a password or an existing provider.
  - `true`: the Kanidm identity is silently linked to the existing account. Only enable this if Kanidm is the sole trusted identity source, which the code itself warns about.
- A new subject with no matching user creates a user with `emailVerified = true`. The role comes from `AdminBootstrapService.determineInitialRole` (section 4).

### 3.5 Required Kanidm and GeoPulse settings

**Kanidm (basic client):**
- Redirect URL: `https://<public origin>/oidc/callback`.
- Scope map for the access group: `openid profile email`.
- `allowInsecureClientDisablePkce = true`. **Required**, because GeoPulse sends no PKCE. This is the security trade-off the owner has to accept (section 6).
- `enableLegacyCrypto = true`. **Required**, because GeoPulse verifies RS256 only. Without it Kanidm advertises ES256 and the RSA verifier cannot validate the token.

**Repository mapping:** `policy/identity.json` already carries `allowInsecureClientDisablePkce` and `enableLegacyCrypto` for other clients (for example `termix`, `actual`, `tududi`), and `modules/identity/kanidm-runtime.nix:55-59` and `:121-122` render them. A GeoPulse entry would be a new client with `callbackPath: "/oidc/callback"` and those two flags. Nothing for GeoPulse exists in `policy/` or `modules/` today.

**GeoPulse:**
- `GEOPULSE_PUBLIC_BASE_URL` (or `GEOPULSE_OIDC_CALLBACK_BASE_URL`) set to the public origin. Do not rely on the localhost fallback.
- `GEOPULSE_OIDC_ENABLED=true` for the startup validation warnings. This does not enable login (section 2).
- Provider row created once through the admin API, with `scopes = "openid profile email"`.
- `GEOPULSE_AUTH_SECURE_COOKIES=true` behind HTTPS. Its default is `false`.
- `GEOPULSE_JWT_ISSUER` set explicitly to the public origin. Its default is `http://localhost:8080`.

### 3.6 Uncertainties (OIDC)

- Not exercised: a live Kanidm login. The `kid` in Kanidm's RS256 JWKS was not checked against GeoPulse's `getKeyByKeyId` lookup, and `aud` and `iss` values were taken from the standard, not from a test run.
- Not traced: how `browserAuthResponseMapper` places the session into cookies after a successful callback.
- The `sub` enum definition was not read (see section 3.3).
- A Kanidm user without a primary mail cannot log in. This is a provisioning requirement, not a code bug.

## 4. First user and open registration: risk and switches

### 4.1 Public registration surface

- `/api/users/register` and `/api/users/sign-up/status` are on the public permission list (`application.properties`, `quarkus.http.auth.permission.public.paths`). Anyone who reaches the origin can create a password account unless password registration is off.
- Defaults: `auth.registration.enabled`, `auth.password-registration.enabled`, `auth.oidc.registration.enabled` are all `true`.
- Switch precedence (`SystemSettingsService.getValue`): **database row first**, then the environment variable (`GEOPULSE_AUTH_REGISTRATION_ENABLED`, `GEOPULSE_AUTH_PASSWORD_REGISTRATION_ENABLED`, `GEOPULSE_AUTH_OIDC_REGISTRATION_ENABLED`), then the hardcoded default. Once an admin saves any of these in the admin UI, later environment changes are ignored.

### 4.2 OIDC registration

Kanidm's scope map is the real gate for OIDC: a user outside the mapped group gets no token. Inside that group, the first valid login with a primary mail creates a GeoPulse user.

### 4.3 First-user admin and the bootstrap trap

- `determineInitialRole` promotes a new user to ADMIN in two cases: the email matches `GEOPULSE_ADMIN_EMAIL` (environment only, `geopulse.admin.email`), or `GEOPULSE_FIRST_USER_ADMIN` is `true` (default), there are no users at all, and no admin exists. A bootstrap lock guards the check.
- `AdminBootstrapService.onStart` also promotes an existing user whose email matches `GEOPULSE_ADMIN_EMAIL`.
- Registration is checked before creation. Setting `auth.registration.enabled=false` therefore also blocks creation of the first user, so an operator who disables registration before the owner's account exists locks themselves out.

**Recommended ordering (for the proposal):**
1. Set `GEOPULSE_ADMIN_EMAIL` to the owner's Kanidm primary mail, and keep the origin unreachable by others until the owner has logged in once.
2. Log in as the owner (becomes ADMIN).
3. Through the admin UI or the database, set `auth.password-registration.enabled=false` and, if desired, `auth.oidc.registration.enabled=false`. Remember that the database row wins after this point.

### 4.4 Other public surfaces to address at the edge

Public permission list, by path (all reachable without a session):

- `/api/prometheus/metrics`: metrics. Do not expose publicly.
- `/api/health`, `/api/version`, `/api/version/status` (the version status calls GitHub).
- `/api/geocoding/*`: a geocoding proxy.
- `/api/shared/*`, `/api/home/content`.
- `/api/mobile/session/exchange`.
- `/api/auth/*` (includes OIDC and login).
- Device ingest paths (section 5).

`/mcp` is **not** on the public list, so it falls under the `authenticated` default. nginx proxies `/mcp` to the backend, so the MCP route is a second authenticated API surface on the public origin.

## 5. Device ingest: explicit paths and authentication

Browser SSO and device ingest are separate mechanisms. The browser session is a JWT in the `access_token` cookie (`mp.jwt.token.header=Cookie`) with CSRF protection. API clients may send a JWT as `Authorization: Bearer`. Device ingest uses **per-source credentials** stored in `gps_source_config`, not the user session or Kanidm, and the ingest resources are on the public permission list, so their auth lives in the resource code.

| Source | Endpoint (all POST unless noted) | Credential | Storage |
|---|---|---|---|
| OwnTracks | `/api/owntracks` (device ID in `X-Limit-D`) | HTTP Basic: source username and password | Password hashed (`SecurePasswordUtils`); username unique per user and type |
| GPSLogger | `/api/gpslogger` | HTTP Basic | Password hashed |
| Colota | `/api/colota` | HTTP Basic | Password hashed |
| Overland | `/api/overland` | `Authorization: Bearer <token>` | Token **plaintext** in `gps_source_config.token`, user-supplied, unique per user and type |
| Traccar | `/api/traccar` | Bearer token, plus device match on `deviceId` | Token plaintext; uniqueness is per user, per token and device |
| Home Assistant | `/api/homeassistant` and `/api/homeassistant/*` | Bearer token | Token plaintext, unique per user and type |
| Dawarich-compatible | `/api/dawarich/api/v1/{health,points,stats}` | Bearer token (API key) | Token plaintext |
| MQTT (OwnTracks) | broker topic | Username only; the code states broker-level security is assumed | Off by default (`GEOPULSE_MQTT_ENABLED=false`) |

Notes:
- The tokens and passwords are **entered by the user** in the UI (`CreateGpsSourceConfigDto.token` and `.password`). The server does not generate them. The frontend does not generate them either (`LocationSourceDialog.vue` takes free text).
- OwnTracks payload encryption is optional. A secret, when supplied, derives a secretbox key (`OwnTracksEncryptionKeyUtil`).
- `GpsSourceService` checks token uniqueness **per user and type** (`findByUserIdAndSourceType`). The ingest lookup is **global** (`findByTokenAndSourceType` uses `firstResultOptional()` with no ordering). Two users who choose the same Overland or Home Assistant token therefore pass validation and then ingest attributes data to whichever row the database returns first. Single-user homelab use is unaffected. Multi-user use needs a global uniqueness check.
- The MQTT password default in `application.properties` is `geopulse_mqtt_pass_123`. Override it if MQTT is ever enabled.

### 5.1 Open risk: bearer ingest on a `permit` path

`smallrye.jwt.always-check-authorization=true` makes SmallRye check the `Authorization` header even though `mp.jwt.token.header=Cookie`. The SmallRye docs describe this option as checking the Authorization header when no token cookie exists. The Overland, Traccar, Home Assistant and Dawarich tokens are opaque strings, not JWTs, and they arrive on a public `permit` path.

- The route tests (`GpsIntegrationRouteTest`) only post **without** an Authorization header and assert 401 from the resource. No test sends a valid or opaque bearer on the wire.
- Therefore it is **unverified** whether SmallRye rejects an opaque bearer before the resource runs. If it does, bearer-based sources fail at the framework layer.
- Acceptance check before any bearer source is relied on: an HTTP test with an opaque bearer against the built artifact, not a source reading.

### 5.2 Public exposure and Cloudflare Access

Device ingest must reach the origin from phones and routers that cannot pass an interactive Access gate. In this topology:
- UI, API and ingest share one origin, because the frontend nginx proxies `/api/` to the backend.
- A Cloudflare Access application on the hostname therefore also gates ingest.
- Options (decision for the parent, not chosen here): a separate ingest hostname with `requireCloudflareAccess = false` that only routes the ingest paths; a path-scoped Access bypass for the ingest paths; or an origin-side path allowlist. The repository already opts a machine route out with `requireCloudflareAccess = false` (the ntfy precedent recorded in the earlier research).

## 6. Security trade-offs the owner must accept

- **PKCE disabled on the Kanidm client** (section 3.5). Kanidm documents it as insecure for confidential clients, and the protection left is TLS plus a secret that does not leak. The alternative is an upstream GeoPulse change adding PKCE, which is not in scope here.
- **Auto-link** stays off unless Kanidm is the sole identity source.
- **Public metrics and version endpoints** need an edge block (section 4.4).
- **OIDC client secret encrypted with the AI key.** Losing or rotating `/app/keys/ai-encryption-key.txt` makes the stored OIDC secret and AI keys unreadable.

## 7. Licensing: reconciled against the original text

Source: `LICENSE` at `77e9c0eb`, read from the clone.

- **Grant.** "The Licensor hereby grants you the right to copy, modify, create derivative works, redistribute, and make use of the Licensed Work for any use, subject to the following conditions."
- **Condition 1 (Additional Use Grant).** "You may use the Licensed Work for 'Personal Use' only." Personal Use means "use by an individual for non-profit, private, or educational purposes."
- **Commercial Purpose** (not permitted) includes "(a) Using the Licensed Work to provide a service to third parties (including SaaS, PaaS, or Application Service Provider models)" and "(b) Using the Licensed Work in a production environment for any business enterprise or commercial entity."
- **Section 4 (Redistribution).** "If you redistribute the Licensed Work or any derivative works, you must include this License in full."
- **Change Date** 2075-01-01, Change License AGPL-3.0-only.

Reconciliation, without legal assurance:
- The text grants redistribution as part of "any use, subject to the following conditions." It does not carve out redistribution as prohibited. The restriction is the Personal Use condition and the license-inclusion requirement.
- The text does not mention binary caches. Whether a public cache that serves third parties counts as "providing a service to third parties" or as redistribution to people outside Personal Use is a legal question for the owner. The license names `kerriden1@gmail.com` for doubt.
- A private cache with no third-party readers, and a homelab run by one individual, sit closer to the Personal Use wording. That is still an interpretation, not a conclusion the license states.
- The earlier wording "may count as redistribution" is replaced by this: redistribution is granted, the conditions limit who may receive or use the work, and the owner decides whether the cache meets them.

## 8. Native derivation: the contract it must preserve

### 8.1 Backend (JVM first)

- Build: `mvn dependency:go-offline` then `mvn package -DskipTests -Dquarkus.profile=prod` (JDK 25, Quarkus fast-jar layout). The build output is `backend/target/quarkus-app/` (`lib/`, `app/`, `quarkus/`, `quarkus-run.jar`).
- Run: `java $JAVA_OPTS -jar quarkus-run.jar`, from `/app`. The image's default options are `-XX:+UseContainerSupport -XX:InitialRAMPercentage=25 -XX:MaxRAMPercentage=75 -XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/app/dumps/ -XX:+ExitOnOutOfMemoryError`.
- Port: 8080 (`quarkus.http.port`). Set the bind address explicitly in the unit.
- Native image (`backend/Dockerfile.native`, Mandrel 25) is a second step. The launcher supports `/work/application`, but native is not needed for the first deployment.
- Not verified: offline Maven completeness (no `mvnHash` computed), and whether the Quarkus build fully resolves without network access.

### 8.2 Frontend (static)

- Build: `npm ci` then `npm run build` on Node 20 (`frontend/Dockerfile`), output `dist/`. The lockfile has 770 entries, all from `registry.npmjs.org`, per the previous research. No `npmDepsHash` computed.
- Runtime config written at start by `docker-entrypoint.sh`:
  - `/app/config/config.js` with `window.VUE_APP_CONFIG = { API_BASE_URL: '/api' }`;
  - nginx placeholders replaced: `BACKEND_URL_PLACEHOLDER` from `GEOPULSE_BACKEND_URL` (default `http://geopulse-backend:8080`), `CLIENT_MAX_BODY_SIZE` (default 200M), `OSM_RESOLVER`, and `NGINX_PORT` (80 as root, 8080 otherwise).
- nginx routes that the native service must reproduce:
  - `location /api/` proxied to the backend, with `X-Forwarded-For` and `X-Forwarded-Proto`;
  - `location /mcp` proxied to the backend;
  - `location ^~ /osm/tiles/` proxied to OpenStreetMap tile servers, which is an outbound dependency outside the fleet;
  - `location /` with `try_files $uri $uri/ /index.html` (SPA fallback, which also serves `/oidc/callback`).
- The native equivalent is `services.nginx` with the same rules, the placeholders rendered at activation, and `config.js` written to the web root.

### 8.3 PostgreSQL

- Datasource: `GEOPULSE_POSTGRES_URL`, `GEOPULSE_POSTGRES_USERNAME`, `GEOPULSE_POSTGRES_PASSWORD`.
- Flyway: `migrate-at-start=true`, `baseline-on-migrate=true`, `out-of-order=true`, 108 migrations.
- Extensions created by migrations: `postgis` and `postgis_topology` only (`CREATE EXTENSION IF NOT EXISTS`). The PostGIS 3.5 versus 3.6.4 question from the previous research remains open, and so does whether the consumer role can create extensions.
- Backup and restore need `pg_dump` and `pg_restore` matching the server major (the image installs `postgresql17-client`). Point `GEOPULSE_BACKUP_BINARY_DIRECTORY` at them.

### 8.4 State paths and key generation

| Path | Contents | Created by | Notes |
|---|---|---|---|
| `/app/keys/jwt-private-key.pem` | RSA private key, signs access tokens | `generate-keys.sh` (`openssl genpkey -algorithm RSA`) on first start | Upstream chmods 644. The native unit should use owner-only permissions. |
| `/app/keys/jwt-public-key.pem` | RSA public key, verifies tokens | `generate-keys.sh` (`openssl rsa -pubout`) | Set via `GEOPULSE_JWT_PUBLIC_KEY_LOCATION` |
| `/app/keys/ai-encryption-key.txt` | Base64 AES key, 16, 24 or 32 bytes; key ID `v1` | **Not generated by the application.** `KeyCipher.load` throws when it is missing. Upstream creates it in the keygen step. | Encrypts AI keys and the OIDC provider client secret. Losing it makes both unreadable. |
| `/data/geopulse-backups` | Full backups; work path `…/.work` (`geopulse.backup.work-path`) | Image `mkdir` | Must survive restarts |
| `/data/geopulse-import` | Import drop folder (`geopulse.import.drop-folder.path`) | Operator | Upload timeouts and cleanup are configured |
| `/app/dumps` | Heap dumps (`-XX:HeapDumpPath`) | Image `mkdir` | Writable, not state |
| `/app/logs` | Not referenced in the source | Image `mkdir` | Not verified |

Key generation for the native build is a sops-managed decision, not an unmanaged keygen step. The repository's secret rule applies. The operator generates the keys once and stores them encrypted. The JWT key pair and the AI key must be stable, and the AI key must be backed up with the database.

### 8.5 Secret and environment inputs

- Required for start: the three PostgreSQL values, the JWT key pair, and the AI key file.
- In the database and encrypted: admin-entered API keys (geocoding, weather), `geopulse.backup.password`, the OIDC client secret, and AI keys. Any of these can also come from environment variables, which the database overrides.
- Per-source device credentials (section 5) are database state, entered in the UI.
- `GEOPULSE_JWT_ACCESS_TOKEN_LIFESPAN` (default 1800 s) and `GEOPULSE_JWT_REFRESH_TOKEN_LIFESPAN` (default 604800 s).

### 8.6 Ports and outbound dependencies

- Inbound: 8080 (backend, behind nginx), the frontend port (80 or 8080).
- Outbound: Nominatim at `nominatim.openstreetmap.org` (default geocoder), Photon at `photon.komoot.io` (enabled by default, configured as fallback), Open-Meteo (default weather), OpenStreetMap tile servers (browser map via nginx), GitHub (version check), and the Kanidm discovery and token endpoints.

## 9. AI: optional, and the custom-endpoint question

- AI is per-user. Each user's settings (`UserAISettings`) hold `enabled`, `openaiApiUrl`, `openaiApiKey` (encrypted), `openaiModel`, and `customSystemMessage`. There is no operator environment variable for the AI endpoint or key.
- Defaults: `openaiApiUrl` = `https://api.openai.com/v1`, model `gpt-3.5-turbo` (`UserAISettingsService`).
- The client builds `baseUri(openaiApiUrl)` with a Bearer key (`OpenAIChatClient`). A custom OpenAI-compatible endpoint is therefore possible, but only by a user entering it in the UI.
- No scheme, host or private-address validation was found in `AIResource` or `UserAISettingsService` in the paths read. This is not exhaustive. A user could point the server at an internal URL, so treat it as a risk to confirm before enabling AI.
- Whether the endpoint path and the structured-output shape are compatible with Bifrost is **not verified** here. The earlier research flagged the same question for other consumers.
- **Not added.** No AI configuration is proposed. The homelab should leave AI off until the owner decides the endpoint and the validation question.

## 10. Recommended first deployment (for the parent's proposal)

- Native JVM backend and static nginx frontend, on one host, with the `/api`, `/mcp` and SPA rules from section 8.2.
- PostgreSQL consumer with `postgis` and `postgis_topology`, and the backup export through the state-backups mechanism.
- Sops-managed JWT key pair and AI key, generated once, with backups.
- OIDC: a Kanidm basic client with `allowInsecureClientDisablePkce` and `enableLegacyCrypto`, a group scope map of `openid profile email`, and the redirect `https://<origin>/oidc/callback`. The GeoPulse provider row is created once through the admin API.
- Bootstrap: owner-first ordering from section 4.3, then registration switched off in the database.
- Device ingest: the separate-hostname or path-bypass decision (section 5.2), after the bearer-on-permit test (section 5.1).
- No AI, no MQTT, no Immich or Memos integrations, and no geocoder keys beyond the defaults.

## 11. Unverified claims and open items

1. Live Kanidm login against a GeoPulse build: not run.
2. Opaque bearer on a public `permit` path under `always-check-authorization=true`: not tested (section 5.1).
3. Kanidm RS256 `kid` matching in GeoPulse's JWKS lookup: not checked.
4. `sub` enum variants in Kanidm: the code paths read use the account UUID; the enum definition was not read.
5. Browser cookie placement after callback (`browserAuthResponseMapper`): not traced.
6. AI endpoint validation: not exhaustive (section 9).
7. Offline Maven and npm completeness, `mvnHash` and `npmDepsHash`: not computed. Native build not attempted.
8. PostGIS 3.6.4 against the migrations, and whether the consumer role can create extensions.
9. Legal status of a public binary cache under the BSL: not resolved, owner decision.

## 12. Decisions for the parent

1. Accept PKCE disabled on the Kanidm client, or require an upstream PKCE change first.
2. Choose the device-ingest exposure model (separate hostname, path bypass, or origin allowlist).
3. Confirm the owner-first bootstrap ordering.
4. Decide the cache policy under the BSL (private cache versus public).
5. Keep AI off, or define the endpoint and validation first.
6. Edge block for `/api/prometheus/metrics` and the version endpoints.
