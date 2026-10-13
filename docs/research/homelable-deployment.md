# Research: Homelable deployment contracts

Read-only upstream investigation for an OpenSpec proposal. No configuration, secrets, live hosts, source builds or OpenSpec artifacts were touched.

## Pin

| Item | Value |
|---|---|
| Upstream | `https://github.com/Pouzor/homelable` |
| Release | `v3.6.0`, tag commit `56d113dc5b685ce61720dceebd48beb2d4f5c59b` (committed 2026-10-07T01:42:04+02:00) |
| `main` at investigation | `56d113dc` (same commit; the tag is at HEAD) |
| `VERSION` file | `3.6.0` |

Sources: the tagged tree, read directly (`git clone` + `git rev-list -n1 v3.6.0`).

## Purpose

Self-hosted network and homelab topology/inventory editor. A FastAPI backend stores canvas designs in SQLite and runs discovery (ARP/ping sweeps, nmap service detection, mDNS, and imports from Proxmox, UniFi, Zigbee2MQTT and Z-Wave JS UI). A Vite React SPA is served by nginx and proxies `/api/`. An optional MCP server exposes the backend to AI clients. (Direct evidence: `README.md`, `docker-compose.yml`, `backend/app/main.py`, `Dockerfile.frontend`.)

## License

**MIT**, `Copyright (c) 2026 Remy Jardinet` (`LICENSE` at `56d113dc`). Images carry `org.opencontainers.image.licenses=MIT`. Direct evidence; high confidence. No dual-licensing or commercial tier found in the tree.

## Dependency graph

```
browser ──► frontend (nginx :80)  ──/api/, /docs, /redoc, /openapi.json──►  backend (uvicorn :8000)
                                                                              │
mcp (uvicorn :8001) ──X-MCP-Service-Key──► backend  ◄── (optional) ── nginx /api/v1/status/ws/
                                                                              │
                            SQLite /app/data/homelab.db  +  /app/data/uploads │ scan_config.json
                                                                              │
              outbound (configured, optional): Kanidm/OIDC discovery+token, Proxmox REST :8006,
              UniFi controller, MQTT brokers (Zigbee2MQTT/Z-Wave JS UI), HTTP probes, LAN ARP/ping/nmap, mDNS
```

Direct evidence from compose, nginx config and backend code. Outbound list is from settings and service modules; I did not audit every outbound URL exhaustively, so no telemetry/update-check absence claim is made.

## Build and runtime

**Backend** (`Dockerfile.backend`): `python:3.13-slim`; apt installs `nmap`, `iputils-ping`, `curl`; `pip install -r backend/requirements.txt` (all versions pinned, e.g. `fastapi==0.135.1`, `sqlalchemy==2.0.35`, `authlib==1.7.2`, `joserfc==1.7.4`, `python-nmap==0.7.1`, `zeroconf==0.149.16`, `aiomqtt==2.3.0`); CMD `uvicorn app.main:app --port 8000`. Runs as root (no `USER`). Requires Python 3.13 (comment: 3.14 unsupported by pydantic-core).

**Frontend** (`Dockerfile.frontend`): multi-stage. Builder `node:20-slim` runs `npm ci` + `npm run build` (Vite; `VITE_BASE_PATH` is baked at build time, default `/`). Runtime `nginx:alpine`; the full config is an envsubst template rendering `BACKEND_UPSTREAM` (default `backend:8000`). `frontend/package.json` has 24 runtime and 23 dev dependencies with a committed `package-lock.json`.

**MCP** (`mcp/Dockerfile.mcp`): `python:3.13-slim`, pinned `requirements.txt`, uvicorn :8001.

## Published images and architecture

Registry evidence (anonymous GHCR manifest/config reads, 2026-10):

| Image | Tag `3.6.0` index digest | linux/arm64 manifest | Notes |
|---|---|---|---|
| `ghcr.io/pouzor/homelable-backend` | `sha256:1e501424e8c53989fcea1dc9311d46614ae159b2bfee4608a5c0cd5baee3e9dc` | `sha256:4876b37e9ab58631b70f4f423cefedd6d1b8f7540a45270f5b0dbc685f15eb91` | arm64 config: revision `56d113dc`, `User` unset, CMD uvicorn :8000 |
| `ghcr.io/pouzor/homelable-frontend` | `sha256:5950f4905da2ea92b2a3870066399e718987a4a23d16c368935b9ddb7901635a` | `sha256:8e7be1b17e0e25a1985f4b665ee3fc5f25e4116697ae1c34202fa7ec27132755` | nginx :80 |
| `ghcr.io/pouzor/homelable-frontend-standalone` | `sha256:3e70d196503ad6efaca97bc7a10b9d131df4a349796ad068519ac2e6a7dcb952` | `sha256:1ca2c044f1631e6ab6b1b3b634df2a492115b4c24c73b55f98d7b0bd362da9c6` | no backend proxy; for static/no-backend use |
| `ghcr.io/pouzor/homelable-mcp` | `sha256:42838c0733b6443bcb6aaa3310f39daa8e700817ddb1f4466ff58d5cc0013c85` | `sha256:39eae3765a4fd5e064867a39ead9a3863a799afe5eb2db921de7fa47f8dd7d87` | uvicorn :8001 |

- **ARM images are published.** Each `3.6.0` index includes `linux/amd64` and `linux/arm64`; the workflow `docker-publish.yml` builds `linux/amd64,linux/arm64` (QEMU) on `main` pushes and `v*` tags. Direct evidence.
- **Unknown:** `homelable-mcp:latest` (`sha256:cc401bd1…`) is a different index from `homelable-mcp:3.6.0` (`sha256:42838c07…`) although the backend and frontend `latest` equal their `3.6.0` digests. The arm64 `3.6.0` MCP label still says revision `56d113dc`; the cause of the `latest` divergence is not established. Pin the `3.6.0` digest and do not use `latest`.
- Published `:latest` is only pushed on the default branch, so it can drift; the `prebuilt` compose uses `:latest`. Do not use it.

Pins for the proposal (tag reference plus the index digest; the arm64 manifest digest is the per-architecture alternative):
`ghcr.io/pouzor/homelable-backend:3.6.0@sha256:1e501424e8c53989fcea1dc9311d46614ae159b2bfee4608a5c0cd5baee3e9dc`, and similarly for frontend.

## Native derivation feasibility

- **nixpkgs (locked tree `6510408d`, `legacyPackages.aarch64-linux`): no `homelable` attribute.** Direct evidence (`nix eval`).
- Backend: pure Python with pinned PyPI dependencies plus `nmap`, `iputils`, `curl`. Feasible as a `buildPythonApplication`/`uvicorn` service; I did not verify that each pinned version exists in nixpkgs (`apscheduler==3.10.4` and others may drift). **Unknown until checked per package.**
- Frontend: Vite SPA with `package-lock.json`; feasible via `buildNpmPackage` with Node 20 (the Dockerfile's builder). Not built here.
- Verdict: native packaging is feasible but would be a bespoke derivation with no upstream packaging to reuse. The published multi-arch images already exist with digests, so the image route is the lower-cost default.

## Authentication

Two modes, selected by `AUTH_MODE` (`backend/app/core/config.py`, `.env.example`):

1. **`local` (default)**: `POST /api/v1/auth/login` compares one username and a bcrypt hash (`AUTH_USERNAME`, `AUTH_PASSWORD_HASH`), then issues an HS256 JWT signed with `SECRET_KEY` (`create_access_token`, expiry from `access_token_expire_minutes`). No user table, no registration route, no password change route, and **no login rate limit or lockout** (`grep` for rate-limit found only unrelated vendor code).
   - `.env.example` ships `AUTH_PASSWORD_HASH` for the password `admin` and a placeholder `SECRET_KEY=change_me_in_production`. Copying the example unchanged is unsafe.
   - `SECRET_KEY` is a required field with no default in `Settings`, so the app fails to start without it; the risk is a copied placeholder, not a silent default. Direct evidence.

2. **`oidc`**: Authorization code with PKCE `S256`, built with **authlib** (`core/security.py` `_build_oidc_client`, `server_metadata_url=discovery`). `/api/v1/auth/oidc/login` redirects, and `/oidc/callback` calls `authorize_access_token`, requires an `userinfo` mapping, requires non-empty `sub` and `iss` claims, and sets an HttpOnly, SameSite=Lax session cookie (`__Host-homelable-session` when `OIDC_COOKIE_SECURE=true`, the default). The app session JWT lasts `OIDC_SESSION_EXPIRE_MINUTES` (default 480) and carries a per-session CSRF token. Validation rules: `SECRET_KEY` ≥ 32 bytes; `OIDC_SCOPES` must include `openid`; redirect and discovery must be HTTPS when the cookie is secure; no `*` CORS.
   - **No email, group or role allowlist exists in the app.** Any identity that the configured issuer authenticates and that presents a valid `sub`/`iss` receives a session. Access restriction must be enforced at the IdP (Kanidm group/scope binding) or by a proxy. Direct code reading.
   - **Kanidm compatibility is unverified.** Authlib performs ID-token handling itself; I did not check which signing algorithms authlib 1.7.2 accepts from Kanidm's discovery document (the ES256 vs RS256 question seen with openid-client). Treat as an acceptance check, not a fact.
   - The app does not ask the IdP for a `picture` or any avatar claim (not relevant to auth; noted for completeness).

3. **Machine credentials**:
   - `X-MCP-Service-Key` header (`get_auth_context`): if it matches `MCP_SERVICE_KEY`, the request is authenticated as `__mcp_service__` with `auth_method="mcp"`, which is then accepted by the normal auth dependency on every route that uses it. **This is a full-API credential, not a narrow one.** Treat `MCP_SERVICE_KEY` as admin-equivalent.
   - `HOMEPAGE_API_KEY` gates only `GET /api/v1/stats/summary` (`X-API-Key`, constant-time compare; disabled when unset).
   - `LIVEVIEW_KEY` and `DOCS_VIEW_KEY` gate read-only public pages (`/view`, `/docs?key=`); both are off by default and fail closed (403 when unset).

**Public surface behind the frontend:** nginx proxies `/docs`, `/redoc` and `/openapi.json` to the backend without an app-level gate, so the generated API schema is public in every deployment. Data endpoints still require auth. The status WebSocket (`/api/v1/status/ws/status`) requires a valid OIDC cookie in OIDC mode and, in local mode, a first message carrying a bearer token. Origin checks run before auth (`origin_is_allowed`).

**Signup:** none. There is no registration or invitation route anywhere in the backend. In OIDC mode, the IdP is the user directory; the app creates no account record.

## Persistent state

- SQLite at `SQLITE_PATH` (compose sets `/app/data/homelab.db`), created by `Base.metadata.create_all` plus hand-written migration DDL in `db/database.py` (`init_db` runs at lifespan start). Alembic is pinned but the app uses its own migration code path. Direct evidence.
- Uploads (floor plans, media): `UPLOAD_DIR`, default `<SQLITE_PATH dir>/uploads`, on the same volume.
- `scan_config.json` lives beside the DB (`Path(sqlite_path).parent`).
- Single writable volume `/app/data` in compose. The image runs as root, so ownership of a bind mount is not an issue for root but is for a non-root runtime.
- **Backup unknown:** I did not verify whether the SQLite database uses WAL mode or a checkpoint policy. Export via SQLite's online backup (`sqlite3 .backup`) before the restic job, as with the repo's other SQLite apps, instead of copying the live file.

## Privileges, Docker socket, and blast radius

- **No Docker socket or Docker SDK use** in the backend (grep for `docker.sock`, `docker.from_env`, `import docker`: none).
- **Not privileged.** Compose grants only `cap_add: NET_RAW` (for `ping`). The prebuilt compose adds the same. Direct evidence.
- Subprocess use: `nmap` (scanner, with `-sT` connect scan fallback when unprivileged), `ping`, and `arp -a` on macOS (`/proc/net/arp` on Linux). No shell-injection review was done; treat as a code-review item.
- **MAC collection requires `network_mode: host`** (documented in compose and `INSTALLATION.md`). That moves the backend into the host network namespace: it sees the LAN, binds port 8000 on every host address, and `NET_RAW` then applies to the host's interfaces. The app-level auth still protects the API; the exposure change is network reach, not privilege escalation. Caveat: the compose file says the bridge network cannot see MACs; Direct evidence.
- Blast radius of compromise (inference from the code): a compromised backend holds the SQLite data, the uploads, the Proxmox/UniFi/MQTT credentials it was given via env (kept in memory per `.env.example`), and the JWT signing key (so forged sessions for any user). In host-network mode it also reaches the LAN.
- The MCP container, if published (`ports: 8001:8001` in both compose files), exposes an AI-client gateway; combined with `MCP_SERVICE_KEY`, its compromise yields full backend access.

## Outbound integrations and secrets

- **Proxmox VE** (`PROXMOX_*`): REST to `:8006`, `verify=verify_tls` (default true; `false` for self-signed). Token kept in memory only.
- **UniFi controller**: login with credentials; rate-limit and MFA error paths handled.
- **MQTT** (Zigbee2MQTT, Z-Wave JS UI): `aiomqtt`, optional TLS and `TLS_INSECURE`; credentials in memory only.
- **HTTP probes** (`SCANNER_HTTP_PROBE_ENABLED`): `httpx` with `verify=verify_tls`, **default `SCANNER_HTTP_VERIFY_TLS=false`**.
- **LAN discovery**: ICMP/ARP/nmap against `SCANNER_RANGES` (default `192.168.1.0/24` in the example); mDNS via `zeroconf`.
- **Kanidm OIDC**: discovery and token exchange over HTTPS (required by the validator when the cookie is secure).
- Secrets are environment values only; nothing in the code writes them to disk per the `.env.example` contract. Not audited beyond that.

## Reverse proxy requirements

- Frontend nginx listens on `:80` and must be the only public entry; it proxies `/api/`, `/api/v1/status/ws/` (WebSocket upgrade), `/ws/`, `/docs`, `/redoc`, `/openapi.json` to `BACKEND_UPSTREAM`.
- If a path prefix is used, build with `VITE_BASE_PATH` (baked into the bundle; the prebuilt image cannot change it).
- Set `OIDC_REDIRECT_URI` to the exact public callback (`…/api/v1/auth/oidc/callback`) and `CORS_ORIGINS` to the browser origin. The app adds the redirect origin to the CSRF check, but browser CORS still needs it listed.
- The proxy must forward `Origin` (checked for WebSocket and CSRF). Nginx's upstream forwards `Host` and `X-Real-IP`; there is no trusted-proxy handling for client IPs in the app.

## Resource assumptions

- Single uvicorn worker process per backend container; APScheduler runs in-process (status checker interval default 60 s, `STATUS_CHECKER_ENABLED`).
- Memory and CPU are not documented. Scans (nmap deep scans over full TCP range in slices) are the heavy path. No numbers were measured; treat sizing as unknown.
- Frontend is static; negligible at runtime.

## Recommended minimal homelab deployment

- Images: backend and frontend, pinned by the `3.6.0` index digests above. Skip MCP unless an AI client is required. Skip the standalone frontend (it has no backend proxy).
- Auth: `AUTH_MODE=oidc` with Kanidm, restricted at the IdP to an explicit group; set `SECRET_KEY` (≥ 32 bytes, generated) and never copy the example hash or placeholder key. Keep `OIDC_COOKIE_SECURE=true`. Prove Kanidm id-token acceptance with authlib before go-live.
- State: one persistent `/srv/data/homelable` volume for SQLite and uploads, exported via `sqlite3 .backup` before restic. Use the repo's state-backups pattern.
- Network: Tailscale-only access to the frontend port (no public ingress); keep the backend unpublished. Do not publish MCP. Bridge network for the backend unless MAC matching on the LAN is required, and then accept the host-network reach explicitly.
- Caps: `NET_RAW` only, no privileged mode, no Docker socket.
- Placement: LAN discovery only sees the host's own network segment. A cloud host (`oci-melb-1`) can scan only its own VCN, not the home LAN, so placement on the LAN host (`home-forge`) is the inference; confirm the target network with the user.

## Unresolved user decisions

1. **Placement host**: `home-forge` (sees the home LAN) or `oci-melb-1` (cloud, scans only its own network). Inference from the scanner's CIDR model; confirm.
2. **Auth**: OIDC via Kanidm (recommended) or local single-admin; if OIDC, which Kanidm group is allowed.
3. **MAC collection**: accept `network_mode: host` (LAN reach, port 8000 on all host addresses) or keep the bridge and accept lost MAC matching.
4. **Discovery scope**: which CIDRs to scan (`SCANNER_RANGES`), and whether the deep scan and HTTP probes (TLS verification off by default) are enabled.
5. **Integrations**: Proxmox, UniFi, Zigbee2MQTT and Z-Wave are optional; each adds credentials and outbound reach.
6. **MCP**: skip, or publish only over Tailscale with its own key, given that `MCP_SERVICE_KEY` is admin-equivalent.
7. **Packaging**: official pinned images (recommended) or a bespoke native derivation (feasible, no upstream package, unbudgeted maintenance).

## Unknowns and missing evidence

- Authlib's acceptance of Kanidm's ID-token signing algorithm and whether Kanidm returns the `userinfo` shape the callback expects. Not run against a live IdP.
- Whether the SQLite database is WAL-mode, so the backup method is confirmed.
- Resource footprint, scan duration, and memory.
- Exact nixpkgs availability and versions for each pinned Python dependency.
- Causes of `homelable-mcp:latest` diverging from `3.6.0`.
- Exhaustive outbound audit (only the configured integrations were enumerated).
- Shell-injection review of nmap/ping argument construction.
- No live container, image pull, or runtime behavioural test was performed.

## Validation performed

- Cloned the repository and pinned `v3.6.0` to commit `56d113dc`.
- Read the full license, both Dockerfiles, all four compose variants, the publish workflow, `.env.example`, `requirements.txt`, nginx configs, auth/security/config/status/stats/liveview/docsview code, and the scanner's privilege use.
- Queried GHCR anonymously for all four images' `3.6.0` and `latest` indexes, the platform list, and arm64 config labels (revision, version, user, entrypoint, ports).
- Evaluated nixpkgs (`6510408d`, aarch64-linux) for a `homelable` attribute: absent.
- `source_check` was not used. Each material claim above rests on a direct read of the pinned source or registry data cited in its section; no web-search-only claim was relied on.
