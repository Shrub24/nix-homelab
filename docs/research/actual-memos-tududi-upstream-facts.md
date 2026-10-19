# Upstream facts: Actual Budget, Memos, tududi (Kanidm OIDC)

Research brief for `openspec/changes/add-actual-memos-tududi`. Values are grouped by topic so each can be copied directly. Each value carries its source; anything a primary source did not confirm is marked **UNVERIFIED**. Interpretation is kept in the separate section at the end.

Checkouts used: Actual at tag `v26.10.0` (GitHub API, file reads at that ref); tududi at tag `v1.9.1` (shallow clone, tag commit `2bebdbaa…`); Kanidm book at tag `v1.9.1` (clone, commit `36055fec…`); Memos at tag `v0.31.0` (clone, commit `2b2192d4…`); live Kanidm at `https://id.shrublab.xyz`.

---

## 1. Actual Budget

Release checked: `v26.10.0` (published 2026-10-02).

### Callback path

- **Redirect URI to register with the provider:** `https://<server_hostname>/openid/callback`
  - Source: `packages/sync-server/src/accounts/openid.ts` at `v26.10.0`, `setupOpenIdClient`, `redirect_uri: new URL('/openid/callback', configParameter.server_hostname).toString()`.
  - Also stated in `packages/docs/docs/config/oauth-auth.md` at `v26.10.0` ("register the following **redirect URI** … `https://<actual.myserver.com>/openid/callback`").
- Note: `/openid/callback` is a root path with no `/api` prefix. The `new URL(path, base)` form discards any path on `server_hostname`, so a path-prefixed hostname would not be honoured.

### `openId.server_hostname`

- **Required value:** the public origin of the Actual server, e.g. `https://actual.<domain>`. It is the base the redirect URI is built on.
  - Source: `packages/sync-server/src/load-config.js` at `v26.10.0`: `server_hostname: { doc: 'OpenID server hostname.', format: String, default: '', env: 'ACTUAL_OPENID_SERVER_HOSTNAME' }`.
  - Source: `packages/docs/docs/config/oauth-auth.md`: `"server_hostname": "your Actual Server URL (so the provider redirects you to this)"`.
  - Source: `packages/docs/docs/config/oauth-auth.md`, env section: "`ACTUAL_OPENID_SERVER_HOSTNAME`: Your Actual Server URL".
- Required by the code: `bootstrapOpenId` returns `error: 'missing-server-hostname'` when the key is absent (`packages/sync-server/src/accounts/openid.ts`, `v26.10.0`).
- Enforced at login: `isValidRedirectUrl` accepts only a redirect whose hostname equals `server_hostname`'s hostname, or `localhost` (`packages/sync-server/src/accounts/openid.ts`, `v26.10.0`).
- Env override: `ACTUAL_OPENID_SERVER_HOSTNAME`.

### `openId.authMethod`

- **Accepted values:** `openid`, `oauth2`. Default `openid`.
  - Source: `packages/sync-server/src/load-config.js` at `v26.10.0`: `format: ['openid', 'oauth2'], default: 'openid', env: 'ACTUAL_OPENID_AUTH_METHOD'`.
  - Source: `packages/docs/docs/config/oauth-auth.md` at `v26.10.0`: `"authMethod": "openid" // or "oauth2"`.
- Behavioural difference, from `packages/sync-server/src/accounts/openid.ts` at `v26.10.0`: when `authMethod` is absent or `openid`, the callback uses `client.callback(...)` (OIDC code exchange with `state`, `iss`, `code_verifier`). When it is `oauth2`, it uses `client.grant({ grant_type: 'authorization_code', … })` and does not validate an ID token.

### `loginMethod`

- **Accepted values:** `password` (default), `header`, `openid`.
  - Source: `packages/sync-server/src/load-config.js` at `v26.10.0`: `format: ['password', 'header', 'openid'], default: 'password', env: 'ACTUAL_LOGIN_METHOD'`.
  - Source: `packages/docs/docs/config/index.md` at `v26.10.0`: `"openid" - OpenId auth (in preview)`.
- **`allowedLoginMethods`** default: `['password','header','openid']`.

### Preview marking

- **Verified:** `packages/docs/docs/config/index.md` labels `openid` as "(in preview)" under `loginMethod`, at `v26.10.0`.
- **Not stated** in the OAuth page (`oauth-auth.md`) or in `load-config.js`. The preview label is therefore documented once, in the config index.
- **Ambiguity left open by the docs:** the docs do not say what "preview" covers, whether the API or config may change between releases, or whether it is supported. This brief does not resolve that.

### File-based secret

- `ACTUAL_OPENID_CLIENT_SECRET_FILE` is read after `config.json` and before validation, and beats both `config.json` and `ACTUAL_OPENID_CLIENT_SECRET` (`packages/sync-server/src/load-config.js` at `v26.10.0`, `applyFileEnv` block; `packages/docs/docs/config/index.md` line 18).

### Other values

- Discovery field: `openId.discoveryURL` (env `ACTUAL_OPENID_DISCOVERY_URL`), or manual `openId.issuer.{name,authorization_endpoint,token_endpoint,userinfo_endpoint}`.
- `openId.client_id` and `openId.client_secret` (env `ACTUAL_OPENID_CLIENT_ID`, `ACTUAL_OPENID_CLIENT_SECRET`).
- `token_expiration` default `never`; `enforceOpenId` default `false`.
- Setting the discovery URL: the Kanidm issuer template below applies (`discoveryURL` is the `…/.well-known/openid-configuration` URL, or the issuer, and the code appends nothing).

### Ambiguities in Actual's documentation (flagged, not resolved)

- The "(in preview)" label has no definition (see above).
- The docs say the first user to log in with OpenID "will be granted admin permissions and become the server owner" (`oauth-auth.md`, "After Setup"). The docs do not say whether this is per-instance or changes in multi-user mode.
- `ACTUAL_USER_CREATION_MODE=manual` (the default) means a Kanidm user must already exist as an Actual user with a matching username before the first OpenID login succeeds (`oauth-auth.md`, `ACTUAL_USER_CREATION_MODE`). The docs do not say how the username is matched against the OpenID claims. **UNVERIFIED.**

### Id-token algorithm (Actual) — inference from source, see §5

- Actual's client is built with `openid-client` `^5.7.1` (`packages/sync-server/package.json`, `v26.10.0`) and no `id_token_signed_response_alg` override (`packages/sync-server/src/accounts/openid.ts`, `v26.10.0`).
- `openid-client` 5.7.1 defaults `id_token_signed_response_alg` to `RS256` (`lib/client.js`, `v5.7.1`, line 190). Kanidm advertises only `ES256` for a standard client (live discovery, see §4). **This is an inference** from the library default and the discovery document, not a tested login; it is recorded in §5.

---

## 2. tududi application

Release checked: `v1.9.1` (published 2026-10-10). Source: shallow clone at tag `v1.9.1`.

### Callback path

- **Redirect URI to register:** `{BASE_URL}/api/oidc/callback/{slug}`
  - Source: `backend/modules/oidc/service.js` at `v1.9.1`, line 45–47: `getRedirectUri(providerSlug, baseUrl)` returns `` `${base}/api/oidc/callback/${providerSlug}` ``.
  - Source: `backend/modules/oidc/routes.js` at `v1.9.1`, line 14: `router.get('/callback/:slug', …)`, mounted by `backend/app.js` line 503 at `` `${basePath}/oidc` ``.
  - Source: `docs/10-oidc-sso.md` at `v1.9.1`, line 799–800 ("Callback URL format: `{BASE_URL}/api/oidc/callback/{slug}`").
- **Base path:** `basePath` resolves to `/api` (the `API_VERSION` env defaults to `v1`, `app.js` line 21); routes are also registered under `/api/v1` when the version differs. The redirect URI always uses `/api/oidc/callback/`, as the comment in `controller.js` lines 9–12 states.
- **Slug value for this deployment:** `kanidm` is an assumed slug. Any value works as long as `OIDC_PROVIDER_SLUG` matches the path registered (see §5).

### Required environment (`OIDC_*`, from `.env.example` at `v1.9.1`)

| Variable | Value for this deployment | Source |
|---|---|---|
| `OIDC_ENABLED` | `true` | `.env.example` line 125 (commented default `false`) |
| `OIDC_PROVIDER_NAME` | display name, e.g. `Kanidm` | `.env.example` lines 137 (single provider block) |
| `OIDC_PROVIDER_SLUG` | `kanidm` (any URL-safe slug; must match the registered callback) | `.env.example` line 138; `docs/10-oidc-sso.md` "Provider not found" |
| `OIDC_ISSUER_URL` | `https://id.shrublab.xyz/oauth2/openid/tududi` (see §2 note) | `docs/10-oidc-sso.md` Kanidm section, `OIDC_ISSUER_URL=https://kanidm.domain.tld/oauth2/openid/appname/` |
| `OIDC_CLIENT_ID` | `tududi` | `.env.example` line 140; `docs/10-oidc-sso.md` Kanidm step 2 |
| `OIDC_CLIENT_SECRET` | secret, from `kanidm system oauth2 show-basic-secret tududi` | `.env.example` line 141; `docs/10-oidc-sso.md` Kanidm step 1.2 |
| `OIDC_SCOPE` | `openid profile email` | `.env.example` line 142 |
| `OIDC_AUTO_PROVISION` | `true` | `.env.example` line 143 |
| `BASE_URL` | `https://tududi.<primary-domain>` (public origin) | `.env.example` lines 50–55 ("Required for OIDC callback URLs") |
| `TUDUDI_TRUST_PROXY` | `true` | `.env.example` line 37–40; `docs/10-oidc-sso.md` Troubleshooting |
| `TUDUDI_USER_EMAIL` | bootstrap admin email | `.env.example` line 18 |
| `TUDUDI_USER_PASSWORD` | bootstrap admin password (**secret**) | `.env.example` line 19 |
| `TUDUDI_SESSION_SECRET` | session secret (**secret**), `openssl rand -hex 64` | `.env.example` line 22 |
| `TUDUDI_ALLOWED_ORIGINS` | the public origin | `.env.example` line 29 |
| `TUDUDI_OIDC_SECRET_ENCRYPTION_KEY` | unset (derived from session secret) | `.env.example` lines 128–131 |

Note: `.env.example` at `v1.9.1` names the variable `TUDUDI_USER_PASSWORD`, not `TUDUDI_ADMIN_PASSWORD`, and `TUDUDI_USER_EMAIL` for the admin email.

### Issuer URL (trailing slash)

- The docs example is `https://kanidm.domain.tld/oauth2/openid/appname/`, with a trailing slash. Kanidm's issuer has no trailing slash (see §4).
- Discovery in tududi is `openid-client`'s `Issuer.discover` (`service.js` `discoverProvider`). `openid-client` 5.7.1 appends `/.well-known/openid-configuration` for both forms (`lib/issuer.js`, `v5.7.1`, lines 183–186). Both forms therefore resolve to the same document. The value without the trailing slash matches Kanidm's advertised issuer exactly, which is the form the id-token `iss` check compares against.

### Application-level facts

- The app uses PKCE `S256` in its own requests (`backend/modules/oidc/service.js` `v1.9.1`, lines 80–81: `code_challenge_method: 'S256'`; callback passes `code_verifier`, lines 127–128).
- Client construction: `new issuer.Client({ client_id, client_secret, redirect_uris, response_types: ['code'] })` (`service.js` `v1.9.1`, lines 114–118). No `id_token_signed_response_alg` override.

---

## 3. tududi image

Image reference in use: `chrisvel/tududi`. The repo's `docker-compose.yml` uses `:latest`; the project pins nothing.

- **Newest stable tag:** `1.9.1`. Published `2026-10-10T20:10:49Z`. `latest` was published one second later (`2026-10-10T20:10:50Z`) and points to the same manifest index as `1.9.1`.
  - Source: Docker Hub tags API, `https://hub.docker.com/v2/repositories/chrisvel/tududi/tags` (queried in this session, 2026-10-12).
  - Source: GitHub releases API, `repos/chrisvel/tududi/releases/latest` → `v1.9.1`, `published_at 2026-10-10T20:11:07Z`.
- **Tag form:** the registry tag is `1.9.1` (no `v`). `v1.9.1` returns 404 on the registry (verified).

### Manifest digest (ready to paste)

```
docker.io/chrisvel/tududi:1.9.1@sha256:e3496f2d68c6cfb69e85bd779ae30da2f3e81b78a8b0e7595e6dc97ef9cb71ef
```

- Method: `GET https://registry-1.docker.io/v2/chrisvel/tududi/manifests/1.9.1` with `Accept: application/vnd.oci.image.index.v1+json`. Response header `docker-content-digest: sha256:e3496f2d…71ef`. The digest was recomputed as the SHA-256 of the response body and matched.
- Platforms in the index (verified from the index body): `linux/amd64` `sha256:984d9dc8…65a0`, `linux/arm64` `sha256:9beff252…7bb03`, plus two `unknown/unknown` entries (attestation manifests, `sha256:e80fd5c4…80ef` and `sha256:feb11424…acb0`). Both `linux/amd64` and `linux/arm64` are present, which covers oci-melb-1 (aarch64).
- `latest` resolves to the same index digest, so `latest` and `1.9.1` are the same image.

### ghcr.io copy

- The release workflow pushes the same tags to `ghcr.io/chrisvel/tududi` (`.github/workflows/docker-publish.yml` at `v1.9.1`, lines 7–11, 211). An anonymous manifest request to `ghcr.io/v2/chrisvel/tududi/manifests/1.9.1` returned `403` in this session, so **the ghcr digest is UNVERIFIED** and was not compared. Use the Docker Hub reference above.

### Runtime user

- Dockerfile `ENV APP_UID=1001`, `APP_GID=1001`; `adduser -u ${APP_UID}` creates user `app` (`Dockerfile` at `v1.9.1`, lines 53–69).
- The image has **no `USER` directive**. `scripts/docker-entrypoint.sh` runs as root, sets ownership of `/app/db`, `/app/uploads`, `/app/backups`, then drops to `$PUID`/`$PGID` (defaults `APP_UID`/`APP_GID`, i.e. 1001:1001) with `su-exec` (`scripts/docker-entrypoint.sh` at `v1.9.1`, lines 8–9, 79–88).
- Consequence for a Nix-managed container: the container starts as root and the entrypoint drops to uid/gid 1001 unless `PUID`/`PGID` override it. A host directory owned by 1001:1001 is therefore the matching ownership. (Inference: the entrypoint performs `chown -R` on those paths at every start, so ownership is corrected regardless.)

---

## 4. Memos and Kanidm

### Kanidm endpoint template (verified against the live provider)

Issuer: `https://id.shrublab.xyz`. Live discovery was read from grafana, paperless and termix (`https://id.shrublab.xyz/oauth2/openid/<client>/.well-known/openid-configuration`, queried 2026-10-12). For each client the shape is identical:

- `issuer`: `https://id.shrublab.xyz/oauth2/openid/<client>`
- `authorization_endpoint`: `https://id.shrublab.xyz/ui/oauth2` (shared by all clients)
- `token_endpoint`: `https://id.shrublab.xyz/oauth2/token` (shared by all clients)
- `userinfo_endpoint`: `https://id.shrublab.xyz/oauth2/openid/<client>/userinfo`
- `jwks_uri`: `https://id.shrublab.xyz/oauth2/openid/<client>/public_key.jwk`
- `code_challenge_methods_supported`: `['S256']` for grafana and paperless; `[]` for termix (client has PKCE disabled).
- `id_token_signing_alg_values_supported`: `['ES256']` for all three.

Template source: Kanidm book `book/src/integrations/oauth2.md` at `v1.9.1`, endpoint list (lines 52–183).

### Memos client `memos` — live discovery NOT available

- `GET https://id.shrublab.xyz/oauth2/openid/memos/.well-known/openid-configuration` returns `HTTP 404` with body `"nomatchingentries"` (queried twice, 2026-10-12). **The `memos` client is not registered on the live Kanidm yet**, so its discovery document cannot be read. The endpoint paths below are therefore taken from the template above, not from a `memos` document. They are the same paths every live client returns, so they are reliable as a template, but the `memos` client itself is UNVERIFIED until it exists.

Values for a Memos OAuth2 provider (`config.oauth2Config`):

- `authUrl`: `https://id.shrublab.xyz/ui/oauth2`
- `tokenUrl`: `https://id.shrublab.xyz/oauth2/token`
- `userInfoUrl`: `https://id.shrublab.xyz/oauth2/openid/memos/userinfo`
- `scopes`: `["openid", "profile", "email"]` — the minimum Kanidm requires `openid` in the scope map (Kanidm book `oauth2.md`, "MUST provide a scope map containing `openid`").
- `fieldMapping.identifier`: `sub`
- `fieldMapping.displayName`: `name`
- `fieldMapping.email`: `email`
- `fieldMapping.avatarUrl`: `picture` (**not a Kanidm claim listed in its `profile` scope set**; see Kanidm claims below).

### Stable identifier claim

- **`sub`** is the stable user identifier. Source: Kanidm book `book/src/integrations/oauth2/examples.md` at `v1.9.1`, line 748: "When using Kanidm, `sub` is the user's UUID, and is stable even if their Kanidm account is renamed or changes email". The same file's Memos-style table (the Gitea/GitLab examples, lines 425–432) maps `User ID` to `sub`.
- Memos reads that claim: `provider/idp/oauth2/oauth2.go` at `v0.31.0` line 115: `claims[p.config.FieldMapping.Identifier].(string)`. The value is taken from the **userinfo** response (`UserInfo` in the same file, lines 83–110 region, `Authorization: Bearer`).
- Memos' own docs say: "Choose a stable provider field such as a subject ID, username, or email address depending on how your provider guarantees identity stability" (`usememos.com/docs/configuration/authentication`). Kanidm's `sub` is the UUID.

### Kanidm claims returned by scope

- `profile` → `name`, `preferred_username`, … (Kanidm book `oauth2.md`, line 226). `preferred_username` is the short or SPN name depending on `prefer-short-username`/`prefer-spn-username` (lines 388–389).
- `email` → `email`, `email_verified` (line 228).
- `groups_name` → group names only (line 232 region).
- `picture` is **not** listed under `profile` in the Kanidm book. Its presence in a userinfo response is **UNVERIFIED**; the Memos `avatarUrl` mapping may therefore resolve to nothing, which Memos tolerates (`avatarUrl` is optional in the Memos field list).
- Kanidm sets `email_verified = true` whenever the account has a primary mail address (`server/lib/src/idm/oauth2.rs` at `v1.9.1`, lines 3143–3150). An account without a mail address returns no `email` and no `email_verified`.

### Memos PKCE

- Memos' frontend sends `code_challenge` and `code_challenge_method=S256` on the authorization request (`web/src/components/IdentityProviderButtons.tsx` at `v0.31.0`, lines 29–43; `web/src/components/Settings/LinkedIdentitySection.tsx` line 113).
- The token exchange forwards `code_verifier` when present (`provider/idp/oauth2/oauth2.go` at `v0.31.0`, lines 63–65).
- Kanidm requires PKCE `S256` for a standard client (Kanidm book `oauth2.md`, lines 22–24). This is compatible with Memos' flow.

### Memos callback

- `https://<your-instance>/auth/callback` (Memos docs, `usememos.com/docs/configuration/authentication`, and `…/deployment-configuration`). The frontend builds it with `absolutifyLink("/auth/callback")` (`web/src/pages/AuthCallback.tsx` line 80, `v0.31.0`), so it is the origin of `MEMOS_INSTANCE_URL` plus `/auth/callback`.

### Memos file-backed identity provider (new since the design)

Memos 0.30 and later load one OAuth2 provider from a file, not only from the admin UI or API.

- Filename: `/etc/secrets/memos-idp-<label>.json`, label in lowercase kebab case (e.g. `kanidm`).
- Stable key: `uid` (required, must be unique, must not contain a database `id`).
- Source: `usememos.com/docs/configuration/deployment-configuration` (fetched 2026-10-12); the Memos docs state the file loader is for "Memos 0.30 and later".
- Mount: the directory is mounted read-only at `/etc/secrets`. Files are read once at process start; "restart every Memos replica" after any change.
- Startup failure cases: an unreadable file, unknown or misspelled fields, duplicate `uid`, or "disabling password login without an identity provider" stop Memos from starting.
- Sensitive: the file contains `clientSecret`. Treat as a secret file.

**This changes the design premise.** The design states that "Memos reads its SSO provider from instance settings stored in its own database, so no environment or Nix surface exists" and that a runbook paste is needed. Memos 0.30+ does offer a file surface (above), so the provider can be declared through Nix, with the client secret supplied from a sops file. The design's runbook step may be unnecessary on 0.30+. This is recorded, not decided here.

### Memos release and packaging

- Latest upstream release: `v0.31.0`, published `2026-09-19T16:50:57Z` (GitHub releases API, `usememos/memos`). The file-backed loader is documented against 0.31 examples.
- nixpkgs on `master` ships `memos` `0.31.0` (`pkgs/by-name/me/memos/package.nix`, line 17). nixpkgs on `nixos-25.11` ships `0.25.3` (line 13), **which predates the file-backed loader**.
- The repo's nixpkgs input follows `nix-fleet/nixpkgs`, and its branch was **not confirmed** in this session (the `flake.nix` grep returned no branch). **UNVERIFIED** which package version the repo's pinned nixpkgs carries. Check `nix eval nixpkgs#memos.version` on the pinned input before relying on the file loader.

---

## 5. Secret or plain configuration

Classification of every value in §1–§4 that the parent will write.

| Value | Class | Note |
|---|---|---|
| Actual `openId.client_secret` | **secret** | from Kanidm `show-basic-secret actual` |
| Actual `openId.client_id` | plain | the Kanidm client name, e.g. `actual` |
| Actual `openId.server_hostname` | plain | public origin |
| Actual `openId.issuer.*` / `discoveryURL` | plain | Kanidm issuer template (§4) |
| Actual `loginMethod`, `allowedLoginMethods`, `authMethod` | plain | |
| tududi `OIDC_CLIENT_SECRET` | **secret** | from Kanidm `show-basic-secret tududi` |
| tududi `OIDC_CLIENT_ID`, `OIDC_ISSUER_URL`, `OIDC_PROVIDER_SLUG`, `OIDC_PROVIDER_NAME`, `OIDC_SCOPE`, `OIDC_AUTO_PROVISION`, `OIDC_ENABLED` | plain | |
| tududi `BASE_URL`, `TUDUDI_ALLOWED_ORIGINS`, `TUDUDI_TRUST_PROXY`, `TUDUDI_USER_EMAIL` | plain | |
| tududi `TUDUDI_USER_PASSWORD` | **secret** | bootstrap admin |
| tududi `TUDUDI_SESSION_SECRET` | **secret** | |
| tududi image ref `docker.io/chrisvel/tududi:1.9.1@sha256:…` | plain | pinned in `policy/oci-images.nix` |
| Memos `clientSecret` (in the file-backed IdP JSON) | **secret** | the whole `memos-idp-*.json` is sensitive |
| Memos `clientId`, `authUrl`, `tokenUrl`, `userInfoUrl`, `scopes`, `fieldMapping.*`, `uid`, `name` | plain | |
| Kanidm client secrets (actual, memos, tududi) | **secret** | never in policy; the repo's pattern is `secrets/hosts/oci-melb-1/oidc.yaml` |

---

## Findings for the parent (interpretation, labelled)

These are inferences and disagreements with the design, kept separate from the values above.

1. **Actual callback** (value, §1): `https://<server_hostname>/openid/callback`. The design's "callback from upstream's OpenID guide" is satisfied by `oauth-auth.md`. **Verified.**
2. **Actual preview** (value, §1): the "(in preview)" label is only on `loginMethod` in `config/index.md`. The design keeps `password` as a fallback. That remains a reasonable choice; the docs do not define "preview".
3. **tududi callback** (value, §2): `{BASE_URL}/api/oidc/callback/{slug}`. The design's slug choice is free. **Verified.**
4. **tududi PKCE contradiction** (inference): `docs/10-oidc-sso.md` (Kanidm section, step 1.3, `v1.9.1`) instructs `kanidm system oauth2 warning-insecure-client-disable-pkce tududi` on the grounds that tududi "doesn't support PKCE". The source at `v1.9.1` (`service.js` lines 80–81, 127–128) **does** send an S256 challenge and a `code_verifier`. If the docs are right about the client, disabling PKCE is needed; if the source is right, it is not. The documented step is therefore **not confirmed by the source**. Recommend a live test before disabling PKCE. Labelled inference.
5. **tududi RS256 contradiction** (inference): `docs/10-oidc-sso.md` (step 1.3) says tududi "only supports RS256, not ES256" and instructs `warning-enable-legacy-crypto tududi`. The source's ID-token validation uses `openid-client` 5.7.1 with the default `id_token_signed_response_alg: 'RS256'` (`lib/client.js`, `v5.7.1`, line 190). Kanidm advertises `ES256` only. **So the RS256 default in the library and the ES256-only Kanidm metadata are a real mismatch**, and `warning-enable-legacy-crypto` is what makes the login work. The docs' instruction is consistent with the source. Labelled inference, since no live login was run.
6. **Actual RS256 by the same logic** (inference): the same library default applies to Actual (§1). Actual's docs do not mention Kanidm, so the `warning-enable-legacy-crypto actual` requirement is **inferred, not verified**. A live login test is the only way to confirm it.
7. **Memos file loader** (contradiction with the design): see §4. The design's runbook paste may not be required on 0.30+. Also, the repo's nixpkgs version is unconfirmed, and nixpkgs `nixos-25.11` carries 0.25.3, before the loader.
8. **`memos` client does not exist yet** on live Kanidm, so the Memos endpoints are template-derived, not read from a `memos` document. Create the client, then re-read its discovery to confirm.
9. **Memos `avatarUrl` = `picture`**: Kanidm's `profile` scope list does not name `picture` (§4). Treat it as optional.
10. **tududi issuer trailing slash**: harmless to discovery (§2), but the form without a slash matches Kanidm's advertised issuer. Use the form without the slash.
11. **tududi image**: `1.9.1` (not `latest`) is the stable pin. The ghcr copy is unverified.

---

## Missing evidence (unverified, unresolved)

- Actual login against Kanidm: never run. The RS256/ES256 mismatch (finding 6) is unconfirmed.
- tududi login against Kanidm: never run. The PKCE and RS256 findings (4, 5) need a live test.
- The `memos` discovery document: unavailable until the Kanidm client exists.
- Kanidm's `picture` claim presence (finding 9).
- The pinned nixpkgs `memos` version on this repo's input (finding 7).
- The ghcr.io digest for tududi `1.9.1` (anonymous pull returned 403).
- The meaning of Actual's "(in preview)" (finding 2).
- Actual's username matching under `ACTUAL_USER_CREATION_MODE=manual`: how the OpenID claim maps to the Actual username. The docs do not say.

## Sources

Kept:
- Actual `packages/sync-server/src/load-config.js` @ `v26.10.0` — `openId` schema, `loginMethod`, `authMethod`, `_FILE` secret (https://github.com/actualbudget/actual/blob/v26.10.0/packages/sync-server/src/load-config.js). Preferred over the grep.app copies, which were from `master`.
- Actual `packages/sync-server/src/accounts/openid.ts` @ `v26.10.0` — redirect URI construction, `missing-server-hostname`, `isValidRedirectUrl`, the `client.callback` vs `client.grant` split.
- Actual `packages/docs/docs/config/oauth-auth.md` @ `v26.10.0` — redirect URI and `server_hostname` wording.
- Actual `packages/docs/docs/config/index.md` @ `v26.10.0` — "(in preview)" label on `loginMethod`.
- tududi `backend/modules/oidc/service.js`, `routes.js`, `controller.js`, `backend/app.js` @ `v1.9.1` — callback path, PKCE S256, client construction, base path.
- tududi `docs/10-oidc-sso.md` @ `v1.9.1` — callback format, Kanidm section (contradicted in part, see findings 4–5).
- tududi `.env.example` @ `v1.9.1` — environment names and defaults.
- tududi `Dockerfile` and `scripts/docker-entrypoint.sh` @ `v1.9.1` — uid/gid and entrypoint behaviour.
- Docker Hub registry, `chrisvel/tududi:1.9.1` manifest index (fetched 2026-10-12) — digest.
- Kanidm book `book/src/integrations/oauth2.md` and `oauth2/examples.md` @ `v1.9.1` — endpoint template, `sub`, PKCE, legacy crypto, scope-map requirement.
- Kanidm `server/lib/src/idm/oauth2.rs` @ `v1.9.1` — `email_verified` source.
- Live Kanidm discovery at `https://id.shrublab.xyz` for grafana, paperless, termix — endpoint shape and algorithms; `memos` returned 404.
- Memos `provider/idp/oauth2/oauth2.go`, `web/src/components/IdentityProviderButtons.tsx`, `web/src/pages/AuthCallback.tsx` @ `v0.31.0` — identifier source, PKCE, callback.
- Memos docs `usememos.com/docs/configuration/deployment-configuration` and `…/authentication` — file loader and callback URL (fetched 2026-10-12).
- openid-client `lib/client.js` and `lib/issuer.js` @ `v5.7.1` — default `RS256` and discovery URL construction.

Kept as corroboration only (labelled):
- `gh`/grep.app search snippets for Actual `server_hostname` — used only to locate the file, every value cited from the tag.
- Web search snippets quoting Kanidm documentation — superseded by the Kanidm book at `v1.9.1`.

Rejected:
- Actual `master`-branch copies (grep.app and the `raw.githubusercontent.com/.../master/...` paths): 404 for the docs path on `master`, and the grep.app snippets are from an unpinned branch. Replaced by the `v26.10.0` tag.
- The `actualbudget/actual-server` repository snippets: a superseded layout, not the current `packages/sync-server`.
- Kanidm issue #603 and third-party posts on userinfo and Vouch: not used for any value here.

## Next steps

1. Create the Kanidm `memos` client, then read its live discovery and confirm §4 values.
2. Run one live login each for Actual and tududi before committing `warning-enable-legacy-crypto` or `warning-insecure-client-disable-pkce` to the runbook.
3. Confirm the pinned nixpkgs `memos` version (`nix eval`) before choosing between the file loader and the runbook paste.
4. Record the ghcr.io digest only after an authenticated pull, or drop the ghcr claim.

---

## 6. Memos file loader, Kanidm signing algorithm, and userinfo-only consumers

Pins used in this section:

- nix-homelab nixpkgs: `nixos-unstable` at `6510408d147d8c5e6d76043e899e9251756f6a75` (`flake.lock`; the root `nixpkgs` follows `nix-fleet/nixpkgs`).
- Memos: `v0.31.0` at `2b2192d4e153bd04f1d325b60fd880cf00d68b01`.
- Kanidm: `v1.11.2` (the repo pins `kanidm_1_11`, `modules/identity/_kanidm-packages.nix:6`, which nixpkgs at the pin resolves to `version = "1.11.2"`, `pkgs/servers/kanidm/1_11.nix`). The `v1.9.1` source read in §4 agrees on every point below and is cited where it differs.
- kanidm-provision: `v1.3.0` (`pkgs/by-name/ka/kanidm-provision/package.nix` at the pin, `version = "1.3.0"`).
- sops-nix: `a8be3b14935d3532604c51c8dfe3021c73d1a885` (the locked `sops-nix` node).
- openid-client: `5.7.1` (npm tarball and the `v5.7.1` tag).

### 6.1 Memos: what selects the identity-provider file (0.31.0)

- **Directory, fixed.** `DefaultDeploymentConfigurationDir = "/etc/secrets"` (`store/deployment_config.go:24`). The startup loader takes no argument: `LoadDeploymentConfiguration` calls `LoadDeploymentConfigurationDir` with that constant (`store/deployment_config.go:38–39`), and `cmd/memos/main.go:158` calls the no-argument form at startup. **Verified.**
- **Not configurable from outside.** No flag in `cmd/memos/main.go:58–103` names a configuration directory. Viper's environment mapping (`cmd/memos/main.go:95–97`, `SetEnvPrefix("memos")`, `AutomaticEnv`) maps only declared flags, so there is no `MEMOS_*` variable for it. `LoadDeploymentConfigurationDir(ctx, dir)` accepts a directory, but its only caller passes the default. **Verified.**
- **Filename.** `memos-idp-<label>.json`. The canonical pattern is `^memos-idp-[a-z0-9]+(?:-[a-z0-9]+)*\.json$` (`store/deployment_config.go:32`). Names that match only the older `memos-idp-*.json` pattern still load, with a deprecation warning (`store/deployment_config.go`, `isIdentityProviderDeploymentFilename`; `docs/configuration-provisioning.md`, "File discovery" and "Transition"). **Verified.**
- **The label is not authoritative.** The Memos provisioning doc states: "The filename label remains descriptive rather than authoritative. The `uid` or `key` inside the message is the resource identity" (`docs/configuration-provisioning.md`, "File discovery"). **Verified.**
- **Symlinks are accepted.** The doc says a matching entry "may be a regular file or a platform-managed symlink that resolves to a regular file, as used by Kubernetes Secret volumes" (`docs/configuration-provisioning.md`, "File discovery"). The reader calls `os.Stat` and `os.Open` on the path (`readDeploymentProtoJSON`), and both follow symlinks. **Verified** for the code path; whether a sops-nix symlink qualifies as "platform-managed" is inference (see 6.4).
- **Read once, at process start.** "The snapshot is loaded once. Files changed after startup have no effect until the process restart" (`docs/configuration-provisioning.md`, "Startup"). The code runs the loader once at startup (`cmd/memos/main.go:158`). **Verified.**
- **Missing directory is a no-op; a bad file is fatal.** A missing `/etc/secrets` publishes an empty configuration (`store/deployment_config.go`, `os.IsNotExist` branch). An invalid matching file aborts startup (`docs/configuration-provisioning.md`, "File discovery"). **Verified.**
- **Size and environment.** Maximum file size is 1 MiB (`docs/configuration-provisioning.md`; constant `maxDeploymentConfigurationSize`, `store/deployment_config.go:25`). The loader does not expand environment variables: a grep for `ExpandEnv`, `Getenv` and `os.Getenv` in `store/deployment_config.go` returns nothing. **Verified.**

**Answer to the question:** no Memos option or flag selects the file. The file must be in `/etc/secrets`. The only way for a sops-rendered secret to be read is to put a regular file, or a symlink to one, into that directory. The decrypted content can then live outside `/etc`. Mechanism in 6.4.

### 6.2 Memos: the identity-provider JSON shape

Shape, from the Memos doc example (`docs/configuration-provisioning.md`, "Identity-provider files") and the store proto (`proto/store/idp.proto`):

```json
{
  "uid": "kanidm",
  "name": "Kanidm",
  "type": "OAUTH2",
  "identifierFilter": "",
  "config": {
    "oauth2Config": {
      "clientId": "memos",
      "clientSecret": "<secret>",
      "authUrl": "https://id.shrublab.xyz/ui/oauth2",
      "tokenUrl": "https://id.shrublab.xyz/oauth2/token",
      "userInfoUrl": "https://id.shrublab.xyz/oauth2/openid/memos/userinfo",
      "scopes": ["openid", "profile", "email"],
      "fieldMapping": {
        "identifier": "sub",
        "displayName": "name",
        "email": "email",
        "avatarUrl": "picture"
      }
    }
  }
}
```

The example values for `uid`, `name` and the URLs are this repository's choices, not Memos'. The JSON structure and key names are from the Memos sources.

Field rules, from `store/deployment_config.go` (`validateDeploymentIdentityProvider`) unless noted:

- **`uid`**: required, must match `^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,34}[a-zA-Z0-9])?$` (`internal/identifier/resource_name.go:6`). It is the stable key (`docs/configuration-provisioning.md`). **Verified.**
- **`id`**: must be omitted (`validateDeploymentIdentityProvider`). **Verified.**
- **`name`**: required, non-empty after trimming (`store/deployment_config.go:165`). The loader does not constrain its value; the doc example uses it as a display name ("Company SSO"). **Verified** for the rule; the display use is from the doc example only.
- **`type`**: must be `OAUTH2` (proto enum `IdentityProvider.Type`, `proto/store/idp.proto`; check in `validateDeploymentIdentityProvider`). **Verified.**
- **`identifierFilter`**: optional; compiled as a regular expression if set. **Verified.**
- **`config.oauth2Config`**: required; the `config` oneof has one member (`proto/store/idp.proto`, `IdentityProviderConfig`). **Verified.**
- **`clientId`, `clientSecret`, `authUrl`, `tokenUrl`, `userInfoUrl`**: required and non-empty (`validateDeploymentIdentityProvider`). `authUrl`, `tokenUrl` and `userInfoUrl` must be absolute `http` or `https` URLs. **Verified.**
- **`clientSecret`** is at `config.oauth2Config.clientSecret` (`proto/store/idp.proto`, `OAuth2Config`, field 2; checked in `validateDeploymentIdentityProvider`). It is plaintext in the file. The doc says the containing directory "is treated as sensitive" (`docs/configuration-provisioning.md`, "File discovery"). **Verified.**
- **`scopes`**: required, non-empty, no blank entries (`validateDeploymentIdentityProvider`). **Verified.**
- **`fieldMapping`** (`identifier`, `displayName`, `email`, `avatarUrl`): **not validated at startup.** The validator has no `fieldMapping` check. Inference: an empty `identifier` would fail at login, not at startup. **Unverified** at runtime.
- **Unknown fields are fatal** ("Unknown fields remain startup errors because this catches misspellings", `docs/configuration-provisioning.md`). **Verified** from the doc; the reader's `unknown field` matcher is at `store/deployment_config.go:34`.

**Provider label.** The file has no separate label. Identity is `uid`; `name` is a required display string; the filename label is cosmetic.

### 6.3 Memos: the nixpkgs module at the pinned revision

- **Module.** `nixos/modules/services/misc/memos.nix` at `6510408d`. **Verified** (read in full).
- **Package.** `pkgs/by-name/me/memos/package.nix`: `version = "0.31.0"` (line 17). **Verified.**
- **Options.** `enable`, `package`, `openFirewall` (line 20), `user` (default `"memos"`), `group`, `dataDir` (default `/var/lib/memos/`), `settings` (an environment-variable attrset), `environmentFile` (defaults to a file generated from `settings`). **Verified.**
- **No option for the identity-provider file or the configuration directory.** **Verified.** The module's only secret channel is `EnvironmentFile = cfg.environmentFile` (systemd environment file). Memos does not read identity providers from environment variables (6.1), so `environmentFile` cannot carry the provider.
- **`openFirewall` is broken at this pin.** Lines 119–120 reference `cfg.port`, which the module does not define. This confirms memory #5104. **Verified.**
- **Unit hardening.** `ProtectSystem = "strict"`, `PrivateTmp`, `PrivateUsers = true`, `ReadWritePaths = [ dataDir ]`, `User = cfg.user`, and no `BindReadOnlyPaths`. **Verified.** A repository module can add `systemd.services.memos.serviceConfig` entries, because the module does not own them.

**Answer:** the pinned module has no equivalent option. The file has to reach `/etc/secrets` by a NixOS-side mechanism, such as sops-nix (6.4).

### 6.4 Memos: putting a sops-rendered file into `/etc/secrets`

From the sops-nix source at `a8be3b14935d3532604c51c8dfe3021c73d1a885`:

- **`path` option.** Each secret's target path defaults to `/run/secrets/<name>` (`/run/secrets-for-users/<name>` with `neededForUsers`) and is a plain string option (`modules/sops/default.nix`, the `path` option around line 73). It can be set to any absolute path. **Verified.**
- **Parent directory is created.** The installer calls `os.MkdirAll(parent, os.ModePerm)` before placing a secret (`pkgs/sops-install-secrets/main.go:260–261`), and the same for templates (`main.go:274–275`). **Verified.**
- **Targets are symlinks.** The installer places each secret at its target with `createSymlink(targetFile, secret.Path, ...)` (`main.go:264`, `main.go:223–231`), so `/etc/secrets/memos-idp-kanidm.json` would be a symlink to the decrypted file that the installer writes. The exact directory is not read here. **Verified** for the symlink call only.
- **Owner.** The unit runs as `cfg.user` (`memos`), so the secret's `owner` and `group` must match, or the reader cannot open the file. **Inference** from `User = cfg.user` and the file mode. Not tested.

**Answer to the question:** yes, with one qualification. The directory entry must be in `/etc/secrets`. Its content can come from anywhere sops-nix writes, because the entry is a symlink. Setting `sops.secrets.<name>.path = "/etc/secrets/memos-idp-kanidm.json"` (with `owner` and `group` set to the Memos user) is the mechanism the code supports. Whether the doc's "platform-managed symlink" wording covers a sops-nix symlink is **inference**; it must be tested on a host.

Two points stay **unverified**:

- A `sops.templates` entry at `/etc/secrets/memos-idp-kanidm.json` would let the JSON embed the secret placeholder with the other fields in one file. The installer creates its parent directory (6.4 above), but I did not confirm whether the template target is a symlink or a regular file.
- Whether the unit can open a symlink target under `/run` with `ProtectSystem = "strict"` and `PrivateUsers = true`. The target is outside `/etc`, so the reader must see `/run` inside the unit's namespace. **Unverified**; test on the host.

### 6.5 Kanidm: the setting that permits a non-default ID-token signing algorithm

- **Attribute.** `oauth2_jwt_legacy_crypto_enable`, a boolean per OAuth2 client. Schema description: "Allows enabling legacy JWT cryptograhpy for clients" (`server/lib/src/migration_data/dl15/schema.rs:506`; the misspelling is in the source). **Verified.**
- **Selection.** `server/lib/src/idm/oauth2.rs:918`: when the attribute is true, `sign_alg` is `Rs256`; otherwise `Es256`. The read is `get_ava_single_bool(...).unwrap_or(false)`, so an unset attribute means ES256. **Verified** at 1.11.2 and at 1.9.1 (`oauth2.rs:852–858`).
- **Scope of effect.** `sign_alg` controls more than the ID token. At 1.11.2 it selects the signer for the ID token (`oauth2.rs:2069–2070`), the access token (`oauth2.rs:2112–2113`), the discovery value `id_token_signing_alg_values_supported` (`oauth2.rs:3158–3161`) and the JWKS (`oauth2.rs:3284–3285`). Turning the attribute on changes every token signature for that client. **Verified.**
- **CLI.** `kanidm system oauth2 warning-enable-legacy-crypto <client>` (`tools/cli/src/opt/kanidm.rs:1119–1125`). Help text: "Enable legacy signing crypto on this oauth2 client. This defaults to being disabled. You only need to enable this for openid clients that do not support modern cryptographic operations." **Verified.**
- **Book.** "Extended Options for Legacy Clients" (`book/src/integrations/oauth2.md`, lines 392–412): enabling gives "the legacy RSA PKCS1-5 SHA256 cryptographic algorithm (`id_token_signing_alg_values_supported` = `RS256`)". Line 28: "If your service doesn't support PKCE or only supports `RS256` token signatures, see extended options for legacy clients." **Verified.**
- **Repository mapping.** `policy/identity.json` sets `enableLegacyCrypto: true` on `karakeep` (line 31), `actual` (line 75) and `tududi` (line 98); `memos` (lines 81–91) has no entry. `modules/identity/kanidm-runtime.nix:58–59` copies the flag into the OAuth2 client policy and `:122` defaults it to `false`. The provisioning block (`modules/identity/kanidm-runtime.nix:424–436`) passes that map to `services.kanidm.provision.systems.oauth2`. **Verified.**
- **nixpkgs option.** `services.kanidm.provision.systems.oauth2.<name>.enableLegacyCrypto` (`nixos/modules/services/security/kanidm.nix:687–691` at `6510408d`): "Enable legacy crypto on this client. Allows JWT signing algorthms like RS256." Default `false`. **Verified.**
- **Writer.** kanidm-provision v1.3.0 writes the attribute on create and update: `src/main.rs:232` and `:249` (`"oauth2_jwt_legacy_crypto_enable": Some(oauth2.enable_legacy_crypto.to_string())`). Its README documents `"enableLegacyCrypto": false`, "Defaults to false. Allows legacy jwt crypto like RS256" (`README.md:187–188`). **Verified.**

**Answer:** the Kanidm client setting is `oauth2_jwt_legacy_crypto_enable`, which the repo writes from `enableLegacyCrypto` in `policy/identity.json` through nixpkgs' `services.kanidm.provision` and kanidm-provision. The repository's `enableLegacyCrypto` entry corresponds to that attribute.

### 6.6 Do Actual and tududi need it?

Both repository entries already set `enableLegacyCrypto: true`. The question is whether each consumer requires it.

**Actual (v26.10.0), default path: yes, source-derived.**

- The repo sets `loginMethod = "openid"` and an `openId` block with no `authMethod` (`modules/apps/actual.nix:79–96`). In Actual's handler, `if (!configFromDb.authMethod || configFromDb.authMethod === 'openid')` selects `client.callback(...)` (`packages/sync-server/src/accounts/openid.ts`, around line 221–223). **Verified.**
- `client.callback` validates the ID token (openid-client `lib/client.js`: `validateIdToken` at line 506 for the authorization response and line 532 for the token response). `validateIdToken` calls `validateJWT(idToken, expectedAlg)` with `expectedAlg = this.id_token_signed_response_alg` (line 779, line 793). **Verified.**
- The default is `RS256` (`lib/client.js:190`). `validateJWT` throws "unexpected JWT alg received, expected %s, got: %s" when `header.alg !== expectedAlg` (`lib/client.js:939`). An ES256 ID token from a default Kanidm client therefore fails this check. **Source-derived; not run live.**
- The client constructor spreads caller `metadata` last, so a caller can override the algorithm (`lib/client.js` constructor `properties`). Actual passes no such key (`openid.ts`, `new issuer.Client({...})`, lines 88–96). The repository's Actual settings expose no field for it, so the only configuration-side fix is Kanidm's legacy flag. **Verified.**
- Actual passes `validate_id_token: true` (`openid.ts:95`). That is not an openid-client 5.7.1 option: the npm 5.7.1 package contains no file with that string. The setting does nothing. **Verified.**

**Actual with `authMethod = "oauth2"`: no, ES256 is enough, source-derived.**

- The alternate branch calls `client.grant({...})` (`openid.ts`, around line 228). `grant()` returns `new TokenSet(responseBody)` and never calls `validateIdToken` (`lib/client.js`, `grant`, lines 1368–1393). **Verified.**
- It then calls `client.userinfo(access_token)` (`openid.ts`, around line 235). Userinfo is plain JSON unless `userinfo_signed_response_alg` is set, and Kanidm does not sign userinfo (`userinfo_signing_alg_values_supported = None`, `oauth2.rs:3163` at 1.11.2). **Verified.**
- Kanidm verifies its own access token on userinfo: `oauth2_openid_userinfo` calls `jws_verify` with the client's key object (`oauth2.rs`, `oauth2_openid_userinfo`, at 1.9.1 around line 2785). That verification is server-side and works with ES256. **Verified.**
- **Consequence for identity.** Actual's identity is `preferred_username` first, then other fields (`openid.ts`, around line 236). Kanidm's `preferred_username` is the SPN unless `preferShortUsername` is set (`s_claims_for_account`, 1.11.2). An `oauth2` switch would therefore change the usernames Actual matches. **Inference**; not tested.

**tududi (v1.9.1): yes, source-derived, and no client-side workaround in source.**

- `backend/modules/oidc/service.js` calls `client.callback(...)` unconditionally (around line 121), then `tokenSet.claims()`. So the ID token is always validated against the library default, RS256. **Verified.**
- The constructor passes no `id_token_signed_response_alg` (`service.js`, `new issuer.Client({...})`, around lines 114–118). **Verified.**
- The userinfo call is best-effort: a failure is caught and the ID token claims are used (`service.js`, the try/catch around `client.userinfo`, around lines 136–146). A userinfo failure does not block login; an ID token failure does. **Verified.**
- **Source-derived; not run live.** This matches the tududi docs' instruction to enable legacy crypto (`docs/10-oidc-sso.md`, §2 of this brief), which the source now supports.

### 6.7 Userinfo-only consumer: is anything beyond the standard settings needed?

**Memos (0.31.0) does not need legacy crypto, source-derived.**

- Memos reads only userinfo: `GET` on `UserInfoUrl` with `Authorization: Bearer <token>` (`provider/idp/oauth2/oauth2.go:85–90`). It sets no `Accept` header. **Verified.**
- No reference to `id_token` or `IDToken` appears in `provider/` or `server/` outside tests and generated code. Memos never validates a JWS. **Verified** by grep; this matches §4, finding "Memos parses no ID token".
- Kanidm's userinfo is plain JSON (`oauth2.rs:3163`, 1.11.2). **Verified.**
- The repository's `memos` entry (`policy/identity.json:81–91`) correctly omits `enableLegacyCrypto`. **Source-derived; not run live.**

**Beyond client id, secret, endpoints and scopes, a userinfo-only consumer needs these Kanidm-side items** (all at 1.11.2 unless marked):

1. **`openid` in the scope map.** The book says: "If you are creating an OpenID Connect (OIDC) client you **MUST** provide a scope map containing `openid`. Without this, OpenID Connect clients **WILL NOT WORK**!" (`book/src/integrations/oauth2.md`, lines 243–244). **Verified** as a book statement. The userinfo handler (`oauth2_openid_userinfo`, `oauth2.rs` around lines 2963–3053) contains no openid check, so the requirement is documentary and not enforced at userinfo. **Verified** by reading the handler.
2. **PKCE with S256.** Kanidm gates the code-challenge check on `require_pkce()` (`oauth2.rs:2416`, 1.11.2), and the book lists "PKCE `S256` code verification" as supported (`book/src/integrations/oauth2.md:24`). Memos sends S256 (§4). Unless a client is set to allow insecure PKCE disable (the repository key `allowInsecureClientDisablePkce`, `policy/identity.json:20`), PKCE is required. **Verified** from the gate. Whether it is on by default for a confidential client is **inference** from the gate and the existence of the disable option; not run live.
3. **Token endpoint authentication.** `client_secret_basic` and `client_secret_post` are both advertised (`oauth2.rs:3090–3093`, 1.11.2). **Verified.**
4. **Claims.** `sub` is the account UUID (`oauth2.rs:3052`, 1.11.2). `s_claims_for_account` sets `name` and `preferred_username` unconditionally and `email` and `email_verified` only under the `email` scope. The struct has no `picture` field, so `picture` is not returned. **Verified**; this resolves §4 finding 9.

Nothing else is required. Legacy crypto is not needed, and no redirect-URL option is needed beyond the defaults.

### 6.8 Corrections and resolutions for sections 1–5

Nothing above has been rewritten. These points supersede the earlier text.

- **§4, "nixpkgs `nixos-25.11` ships 0.25.3" and the open pin question** are resolved for this repository. The repository's nixpkgs is `nixos-unstable` at `6510408d`, and its `pkgs/by-name/me/memos/package.nix` is `0.31.0` (6.3). The 25.11 figure applies to a different branch and does not affect this repository.
- **§4, finding 9 (`picture`)** is resolved: Kanidm 1.11.2 does not emit `picture` (6.7). Memos' `avatarUrl = picture` maps to nothing.
- **§4, finding 5 (RS256)** is source-verified on the library side (6.6). The live login has not been run.
- **§4, finding 4 (tududi PKCE)** is not changed by this section. The tududi source sends S256 (§2). Whether the docs' PKCE-disable step is needed is still unresolved, and this section does not decide it.
- **§4, "the design premise" about a Memos file-backed provider** is confirmed as a real path. Whether this repository uses it is a decision for the owner, subject to 6.4.

### 6.9 Summary and labelled open items

**Verified**

- Memos reads `/etc/secrets/memos-idp-<label>.json` at startup. The path is fixed, has no flag or environment override, and symlinks to regular files are accepted (6.1).
- The nixpkgs `services.memos` module at the pin has no option for the file, and its `openFirewall` is broken (6.3).
- The Kanidm setting for a non-default ID-token algorithm is `oauth2_jwt_legacy_crypto_enable`. It is the attribute the repository's `enableLegacyCrypto` writes, and it switches all of the client's JWS signing, not only the ID token (6.5).
- The openid-client 5.7.1 default is RS256, and `validateJWT` rejects any other algorithm (6.6).
- Actual's default path validates the ID token, so it needs legacy crypto. Its `oauth2` path does not validate the ID token, so it does not. tududi always validates, so it needs legacy crypto (6.6).
- Memos reads only userinfo, so it does not need legacy crypto (6.7).

**Inference**

- A sops-nix symlink at `/etc/secrets/memos-idp-<label>.json` satisfies Memos' "platform-managed symlink" wording (6.4).
- An Actual `authMethod = "oauth2"` change would alter which usernames match (6.6).
- Kanidm enables PKCE by default for a confidential client (6.7, item 2).

**Unverified**

- Every live login: Memos, Actual and tududi. The ES256-versus-RS256 failure is established from source and has not been seen against a running Kanidm.
- Whether the Memos unit reads a symlink target under `/run` with the module's hardening (6.4).
- Whether a `sops.templates` target is a symlink or a regular file (6.4).
- Whether Memos validates `fieldMapping` at login (6.2).
- Whether the userinfo handler should enforce `openid`, which the book requires (6.7, item 1).

**Decisions not made here**

- Whether this repository declares the Memos provider in Nix through sops-nix (6.4), or documents an operator step. The file mechanism is confirmed; the choice is for the owner.
- Whether Actual moves to `authMethod = "oauth2"` to drop legacy crypto. That changes its auth flow and identity matching, so it needs a test first.

### Sources for section 6

Memos `v0.31.0`:
- `store/deployment_config.go` (lines 24, 32–34, 38–39, 43–48, 118–119, `readDeploymentProtoJSON`, `validateDeploymentIdentityProvider`): https://github.com/usememos/memos/blob/v0.31.0/store/deployment_config.go
- `cmd/memos/main.go` (lines 58–103, 95–97, 158): https://github.com/usememos/memos/blob/v0.31.0/cmd/memos/main.go
- `docs/configuration-provisioning.md` ("File discovery", "Identity-provider files", "Startup", "Transition"): https://github.com/usememos/memos/blob/v0.31.0/docs/configuration-provisioning.md
- `proto/store/idp.proto` (`IdentityProvider`, `IdentityProviderConfig`, `FieldMapping`, `OAuth2Config`): https://github.com/usememos/memos/blob/v0.31.0/proto/store/idp.proto
- `internal/identifier/resource_name.go:6` (`UIDMatcher`)
- `provider/idp/oauth2/oauth2.go` (lines 85–90, userinfo request)

nixpkgs at `6510408d147d8c5e6d76043e899e9251756f6a75`:
- `nixos/modules/services/misc/memos.nix`: https://github.com/NixOS/nixpkgs/blob/6510408d147d8c5e6d76043e899e9251756f6a75/nixos/modules/services/misc/memos.nix
- `pkgs/by-name/me/memos/package.nix` (line 17): https://github.com/NixOS/nixpkgs/blob/6510408d147d8c5e6d76043e899e9251756f6a75/pkgs/by-name/me/memos/package.nix
- `nixos/modules/services/security/kanidm.nix` (lines 687–691): https://github.com/NixOS/nixpkgs/blob/6510408d147d8c5e6d76043e899e9251756f6a75/nixos/modules/services/security/kanidm.nix
- `pkgs/servers/kanidm/1_11.nix` (version `1.11.2`)
- `pkgs/by-name/ka/kanidm-provision/package.nix` (version `1.3.0`)

sops-nix at `a8be3b14935d3532604c51c8dfe3021c73d1a885`:
- `modules/sops/default.nix` (`path` option, around line 73)
- `pkgs/sops-install-secrets/main.go` (lines 223–231, 260–261, 264, 274–275)

Kanidm `v1.11.2`:
- `server/lib/src/idm/oauth2.rs` (lines 918, 2069–2070, 2112–2113, 2416, 2963–3053, 3052, 3090–3093, 3158–3161, 3163, 3284–3285), `s_claims_for_account`
- `server/lib/src/migration_data/dl15/schema.rs:506`
- `tools/cli/src/opt/kanidm.rs:1119–1125`
- `book/src/integrations/oauth2.md` (lines 24, 28, 243–244, 392–412)

Kanidm `v1.9.1` (cross-check only):
- `server/lib/src/idm/oauth2.rs` (lines 852–858, 1982, 2785 area, 2847, 2964)

kanidm-provision `v1.3.0`:
- `src/main.rs` (lines 232, 249), `src/state.rs:72`, `README.md:187–188`

openid-client `v5.7.1` (`lib/client.js` and the npm tarball):
- Constructor `properties` (`id_token_signed_response_alg` default, line 190), `validateIdToken` (line 779, 793), `validateJWT` (line 923, 939), `callback` (lines 506, 532), `grant` (lines 1368–1393), `userinfo`
- `validate_id_token` absent from the npm tarball (checked with `npm pack openid-client@5.7.1`)

Actual `v26.10.0`:
- `packages/sync-server/src/accounts/openid.ts` (lines 88–96, 221–236)
- `modules/apps/actual.nix` (this repository, lines 79–96)

tududi `v1.9.1`:
- `backend/modules/oidc/service.js` (around lines 114–146)

Repository:
- `policy/identity.json` (lines 20, 31, 75, 81–91, 98)
- `modules/identity/kanidm-runtime.nix` (lines 58–59, 122, 424–436)
- `modules/identity/_kanidm-packages.nix` (line 6)
