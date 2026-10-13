# Add Actual Budget, Memos and tududi as oci-melb-1 placements

## Why

These are three applications the household will use directly, and they arrive in three shapes the repository has not placed before: a native nixpkgs service with an existing OpenID implementation (Actual Budget, `services.actual`), a native nixpkgs service that loads its identity provider from a file in a fixed directory rather than from its environment (Memos, `services.memos`), and a self-contained third-party container that needs no substrate (tududi, `chrisvel/tududi`).

They also exercise the exposure shape we already use for applications that bring their own identity: published through the edge, **no Cloudflare Access gate**, with Kanidm as the login provider. That is the shape `termix`, `karakeep` and `paperless` use (`access.requireCloudflareAccess = false` together with `access.oidc.enabled = true`). It exists because Actual's desktop and mobile sync clients and Memos' mobile app and API tokens cannot carry a Cloudflare Access session, so Access would break the client instead of protecting it; the application's own OIDC login is the gate.

## What changes

- Three placement aspects selected by `oci-melb-1`: `actual`, `memos` and `tududi`, each supplying its own enablement from selection.
- Three routes in the web policy, all `origin.provider = "oci-melb-1"`, Access off, application OIDC on.
- Three Kanidm OAuth2 clients (actual, memos, tududi) with their callback paths and their host-scoped secret sources, so the client URIs stay provider-owned rather than restated per app.
- One OCI image reference (tududi) in the image policy; Renovate keeps tag and digest current.
- One new service secret file for tududi's session secret and bootstrap admin password; the three OIDC client secrets join the existing host-scoped `secrets/hosts/oci-melb-1/oidc.yaml`.
- Mutable state for all three under `/srv/data/<name>`, registered with state-backups.
- A contract test pinning the placements' evaluated observables, plus the scaffold, secret-scope and identity-directionality updates the new placements require.
- A rendered identity-provider file for Memos, because it loads providers from a fixed directory rather than from its environment, plus a runbook covering the fallback for the case where the running service does not honour it.

## Identity surfaces (verified against upstream sources)

- **Actual Budget** — the server config `openId` block (`discoveryURL`, `issuer.{name,authorization_endpoint,token_endpoint,userinfo_endpoint}`, `client_id`, `client_secret`, `server_hostname`, `authMethod`) selected by `loginMethod = "openid"`, verified from `packages/sync-server/src/load-config.js`. `services.actual.settings` supports `_secret`, so the whole block including the client secret is declared. Upstream marks OpenID auth **"(in preview)"**, so `password` stays an allowed method as a fallback.
- **tududi** — environment-driven: `OIDC_ENABLED`, `OIDC_PROVIDER_NAME`, `OIDC_PROVIDER_SLUG`, `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `OIDC_SCOPE`, `OIDC_AUTO_PROVISION`, with `BASE_URL` required for the callback URL, all from its shipped `.env.example`.
- **Memos** — it loads its identity provider from `/etc/secrets/memos-idp-<label>.json`, a directory 0.31.0 hardcodes with no flag or environment override, holding one OAuth2 provider (`name`, `type`, `config.oauth2Config.clientSecret`, the authorization, token and userinfo endpoints, `fieldMapping` keyed on `sub`). The endpoints derive from the identity contract and the client secret from the host-scoped file, so the provider is declared rather than pasted. Two properties are settleable only on a running host — whether a sops-nix symlink target satisfies Memos' documented symlink support, and whether the service sandbox reads that target — so the runbook carries the instance-settings fallback and its consequence, that a provider configured that way lives in Memos' database.

## Out of scope

- `geopulse` (needs a derivation, possibly an upstream package) and `inboxzero` (an OCI service plus nix-managed substrate).
- Any change to how Kanidm is run or to the OIDC contract in `modules/identity/_oidc.nix`.
- Moving services that already authenticate another way onto Kanidm clients.
