# Design

## PL-1 — All three land on `oci-melb-1`

The operator asked for the two native services directly on the OCI host, and tududi with them. All three are published services, `oci-melb-1` is the edge, and each app's state is small: nothing here needs `home-forge`'s bulk storage.

Placement is declared once, in the host record's aspect selection, and once more as `origin.provider` in the route. Nothing about the apps is host-specific beyond that, so a later move is one aspect selection and one `origin.provider` edit.

Ports, chosen for freedom on `oci-melb-1` rather than for convention, are recorded in the route and must equal the listener the service binds: Actual `5006`, Memos `5230`, tududi `3002`. The implementation confirms each against the host's existing listeners before the route is written.

## EX-1 — Published, Access off, application OIDC as the gate

Each route is published: `declarePublic = true`, `access.requireCloudflareAccess = false`, `access.oidc.enabled = true`, `category = "app"`. This is the existing shape for applications whose clients cannot traverse an Access gate (termix, karakeep, paperless).

`exposureMode` follows the socket rather than the host:

- Actual and Memos bind loopback (`127.0.0.1`), and the edge runs on the same machine, so both use `direct` — the mode the policy reserves for an edge-local loopback upstream.
- tududi publishes its port to loopback (`127.0.0.1:3002:3002`) rather than sharing the host network, so its socket is edge-local like the other two and its mode is `direct`. The fallback, if the ingress module's `direct` handling does not accept a published container, is the host-networking shape the other published containers use (`tailscale-upstream`); the route task states that check.

The alternative — Cloudflare Access with the app's own login disabled — was rejected: it breaks Actual's sync clients and Memos' mobile app and API tokens, which is the whole reason those two need their own identity. Tailnet-only was rejected for these two by the operator decision; it remains the tighter option per app and is worth revisiting for anything that does not need to reach a phone.

## ID-1 — Kanidm clients through the identity contract, never literal URIs

Each app's OIDC configuration is derived from `services.identity.oidc.clients.<id>`, the intrinsic contract that already projects `wellknownUrl`, `issuer` and `clientId` from `policy/identity.json` plus the route, following `provider-owned-oidc-uris`. Assertions fail closed with named messages when the client, the route or the secret is missing, so a client removed from the policy cannot silently degrade into a literal URL.

Client registrations: `actual` (callback from upstream's OpenID guide), `memos` (`/auth/callback`), `tududi` (callback from its `docs/10-oidc-sso.md`). Each client's secret is read from `secrets/hosts/oci-melb-1/oidc.yaml`, the host that consumes it, and the key names follow the existing `secretKeyPrefix` convention.

## AC-1 — `actual` is a native service with its state on `/srv/data`

`services.actual` with `settings.dataDir = "/srv/data/actual"` and a static `actual` user and group: the module's default `DynamicUser` cannot own a pre-created path on a separate mount. `hostname = "127.0.0.1"` keeps the socket loopback so the route can be `direct`.

Identity is `loginMethod = "openid"` with `allowedLoginMethods = [ "password" "openid" ]` — the header method is dropped as unused, and `password` is kept deliberately because upstream marks OpenID **"(in preview)"**. `server_hostname` carries the public host, and the `openId` block is filled from the contract with the client secret bound through `settings.openId.client_secret._secret`, which the module renders into `config.json` at start.

Verified against Actual `v26.10.0`: the redirect it registers is `https://<server_hostname>/openid/callback`, a root path, so a path-prefixed `server_hostname` would not be honoured, and `server_hostname` must be the server's public origin including its scheme — `bootstrapOpenId` refuses to start without it and login accepts only a redirect whose hostname matches. `authMethod` is set to `openid` explicitly rather than left to its default, because the `oauth2` alternative exchanges the code without validating an ID token. Two caveats are carried rather than resolved. The docs do not define what the "(in preview)" label on `loginMethod` covers, and under the default `ACTUAL_USER_CREATION_MODE=manual` an Actual user has to exist before the first OpenID login can match — the docs do not say how that username is matched against the provider's claims. The Kanidm client sets `enableLegacyCrypto`, because Actual's `openid-client` 5.7.1 defaults the ID token algorithm to RS256 while Kanidm advertises only ES256, and because Actual's default `authMethod` takes the path that validates an ID token. The Kanidm setting that permits it is `oauth2_jwt_legacy_crypto_enable`, which applies to every JWS that client receives, and it is verified on the library side rather than by a login. The alternative that would avoid the allowance — `authMethod = "oauth2"`, which exchanges the code without validating an ID token — changes the authentication flow and therefore stays untaken until a login can be tested; upstream's `validate_id_token` option does not exist in `openid-client` 5.7.1 and does nothing.

## ME-1 — `memos` is a native service; its provider configuration is rendered, with a documented fallback

`services.memos` with `dataDir = "/srv/data/memos"`, loopback `MEMOS_ADDR`, `MEMOS_PORT = 5230`, sqlite, and `MEMOS_INSTANCE_URL` set to the public route so generated links are correct. `openFirewall` stays off: the module's firewall branch references a `cfg.port` it never defines, so setting it would fail evaluation, and a loopback listener behind the edge needs no firewall entry.

Memos loads its identity-provider configuration from `/etc/secrets/memos-idp-<label>.json` — 0.31.0 hardcodes that directory and offers no flag or environment variable for it — so the provider is declared rather than pasted: one rendered file, readable by the memos account, holding a single OAuth2 provider whose endpoints come from the identity contract and whose `fieldMapping` keys on Kanidm's `sub` (the user's UUID, which survives a rename; Kanidm emits no `picture`, so `avatarUrl` maps to nothing). The earlier reading that Memos could not be declared at all came from its documentation describing instance settings; its loader has accepted a provider file since 0.30, and the pinned nixpkgs ships 0.31.0.

The provider is delivered as a systemd credential, not rendered into the shared `/etc/secrets` directory. sops-nix renders it root-owned under its default `/run/secrets/rendered`, the unit loads it with `LoadCredential=`, and `BindReadOnlyPaths=/run/credentials/memos.service:/etc/secrets` exposes only that credential directory at Memos' fixed path. The first live deployment showed why the direct render failed: `/run/secrets.d/2/rendered` is `root:root 0750`, so the `memos` account could not reach a `memos`-owned file under it, and widening that shared directory would expose every rendered secret. The bind literal is explicit because `%d` is rejected in `BindReadOnlyPaths`. A live transient-unit probe on OCI confirmed the credential bind gives the sandboxed unit read access that an unprivileged read lacks. Whether the provider is honoured at runtime still needs the deployed unit's journal, and the instance-settings fallback stands if it is not.

## TU-1 — `tududi` is one Nix-managed container

A single digest-pinned container from the image policy, with `virtualisation.podman` and the repository's container conventions: an explicit `dataDir` under `/srv/data/tududi` holding `db`, `uploads` and `backups`, tmpfiles ownership matched to the image's runtime uid — 1001, the uid its entrypoint drops to, since the image declares no `USER` — a `podman-tududi` unit with `RequiresMountsFor`, a restart budget, and a loopback-only port publish so the socket stays edge-local and the route can be `direct`.

Verified against tududi `v1.9.1`: the redirect it registers is `{BASE_URL}/api/oidc/callback/{slug}`, so the Kanidm client's callback path is `/api/oidc/callback/kanidm`, and the issuer is declared without a trailing slash because that form is the one Kanidm advertises. The pinned image is `docker.io/chrisvel/tududi:1.9.1` at its multi-architecture index digest, which carries both fleet architectures. PKCE stays enabled even though tududi's own documentation tells operators to disable it — its source sends an S256 challenge, so the documentation contradicts the code and the code is followed, with the conflict recorded here rather than silently resolved. The client sets `enableLegacyCrypto` for the same reason as Actual — tududi validates an ID token and no source-side override exists — and the same Kanidm setting permits it.

Environment: `TUDUDI_USER_EMAIL` (plain, the bootstrap admin), `TUDUDI_TRUST_PROXY=true` and `TUDUDI_ALLOWED_ORIGINS` plus `BASE_URL` set to the public route, the `OIDC_*` block from the contract, and three secret values — the bootstrap admin password, `TUDUDI_SESSION_SECRET`, and the OIDC client secret. The first two are app-local and belong in a new service-scoped secret file; the client secret belongs with the other client secrets in the host-scoped file.

`TUDUDI_OIDC_SECRET_ENCRYPTION_KEY` is left unset: upstream derives it from the session secret, and introducing a third key would add rotation surface without changing the security model.

## SEC-1 — What the operator must do

1. Add the three client secrets (actual, memos, tududi) to `secrets/hosts/oci-melb-1/oidc.yaml` and encrypt.
2. Create and encrypt `secrets/services/tududi.yaml` with the bootstrap admin password and the session secret.
3. Deploy; then verify that Memos honours the rendered provider file, falling back to configuring the provider once in its instance settings if it does not (runbook).
4. Actual's first sign-in provisions the admin through Kanidm — under the default `ACTUAL_USER_CREATION_MODE` an Actual user with a matching name has to exist first.

## VER-1 — Verification

Per-app, on evaluated configuration rather than source text:

- each aspect publishes its placement and the host selects it;
- each route's port equals the port the service or container actually listens on, and the exposure mode matches the socket;
- each app's OIDC client resolves from the contract with a matching route key, and its `oidc.enabled` route flag agrees with the app's own enablement;
- state paths and the state-backups registrations exist for all three;
- tududi's mounts, uid and secret bindings are present, and its image ref carries both tag and digest.

Plus the repository battery, the scaffold placement contract, the secret-scope fixture, and the identity directionality test — all of which the three new placements touch.

## DOC-1 — Records

`ARCHITECTURE.md`, `STRUCTURE.md` and `docs/architecture.md` gain the three placements and the Memos caveat; `docs/decisions.md` gains the decision entry for the exposure and identity choices; a runbook documents the Memos step and the two secret files the operator must encrypt. Every upstream value these decisions rest on, with its source and its unverified parts, is recorded in `docs/research/actual-memos-tududi-upstream-facts.md`.
