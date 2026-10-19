# Design

## Context

See `proposal.md` for motivation and scope. The new workload is a v2 Homarr container on `oci-melb-1`; it is not a nixpkgs package. Upstream publishes `ghcr.io/homarr-labs/homarr` and documents `/appdata` as persistent state, OIDC configuration through environment variables, and user/group/board management in the UI. The selected release is v2.5.2; its pinned GHCR index was verified to include `linux/arm64`.

Relevant repository patterns: standalone user-facing app aspects under `modules/apps/`, canonical route data in `policy/web-services.nix`, images in `policy/oci-images.nix`, Kanidm clients in `policy/identity.json`, secrets via SOPS templates, and consumer-owned state backup registrations. Existing `admin-homepage` remains a separate operator dashboard on `la-admin-1`. The pinned v2.5.2 GHCR index was verified to include `linux/arm64`; its immutable index digest is recorded in `policy/oci-images.nix`.

## Goals / Non-Goals

**Goals:**
- Keep image, runtime, listener, OIDC secret delivery, host placement, and backup participation declarative.
- Keep Homarr's boards, apps/catalogue presentation, groups, permissions, and user home-board selections in Homarr's persisted application data, where operators can edit them through its UI.
- Give each user a distinct Homarr identity through Kanidm OIDC and allow user-specific boards/access.
- Avoid container-runtime socket access and avoid duplicating service origins or routing policy in Nix dashboard data.

**Non-Goals:**
- Replacing Homepage or automatically synchronizing Homarr's UI catalogue from web policy.
- Declaratively managing every Homarr user, board, widget, or integration in Nix.
- Adding Redis, PostgreSQL, container discovery, or Docker/Podman control unless testing identifies a mandatory v2 runtime dependency.
- Guaranteeing that every fleet application is reachable by every Homarr user; downstream app authorization remains owned by each service.

## Decisions

### HD-1: Nix owns deployment; Homarr owns the editable dashboard data

Use the existing `oci-containers` pattern with a Renovate-managed tag-and-digest image policy. Mount `/srv/data/homarr` at `/appdata`; publish the Homarr listener only on loopback so the edge ingress reaches it through the existing provider transport. Do not mount `/var/run/docker.sock`. This makes runtime and secret inputs reproducible while preserving the requested imperative workflow for boards and personal layouts. Native Nix packaging was considered but rejected: nixpkgs does not provide Homarr, and maintaining its full application build is outside this service deployment.

Pin released v2.5.2 as the initial candidate, after confirming the exact GHCR manifest digest and its `linux/arm64` platform. Do not use a floating `latest` or `early-adopters` tag.

### HD-2: Homarr is a separate user-facing OIDC route

Declare `home.shrublab.xyz` in canonical web policy on `oci-melb-1`, on Homarr's documented port 7575, with `exposureMode = "tailscale-serve"`. Although the active public edge and Homarr share a host, this transport gives the operator a private Tailscale URL for bootstrap while `publicReady = false`; after release, the edge uses the same provider-side front. Disable Cloudflare Access because Homarr performs its own Kanidm OIDC flow. Homarr's application authentication—not route obscurity—guards dashboard content. Its canonical callback is `https://home.shrublab.xyz/api/auth/callback/oidc`; the private callback is the provider's Tailscale Serve origin (`https://<provider-tailnet-name>:7575/api/auth/callback/oidc`), derived from the service catalog's provider endpoint host and port with HTTPS because Serve terminates TLS.

Use only OIDC at steady state. Keep the public route withheld until an initial administrator exists and OIDC has been verified through the private Tailscale endpoint. Homarr's documented onboarding creates its first user through the credentials provider, so expose that provider only through an explicit temporary configuration option. Create the initial local admin privately, sign in through Kanidm to create the separate OIDC account, promote that account to admin in Homarr, then remove the temporary account and disable credentials before public release. Do not enable dangerous automatic account linking.

### HD-3: Separate Homarr identity from Homarr's local authorization and presentation

Register a dedicated Kanidm OAuth2 client with the canonical callback and the private Tailscale callback, using only the minimal `openid`, `email`, and `profile` scopes. Do not assume Kanidm group claims are available; configure Homarr to manage OIDC group membership locally and explicitly disable dangerous credential linking. Homarr should maintain its own users, groups, board permissions, integrations, and individual home-board preferences in `/appdata`; the initial user/admin membership and later sharing are operator actions in Homarr. Test that two separate Kanidm identities create separate Homarr accounts and that private boards/home-board choices do not leak across them.

Store the client secret in the explicit OCI host OIDC secret source consumed by Kanidm provisioning. Store distinct persistent 64-character-hex `AUTH_SECRET` and `SECRET_ENCRYPTION_KEY` values in the service-scoped encrypted secret. `AUTH_SECRET` stabilizes Auth.js sessions; `SECRET_ENCRYPTION_KEY` decrypts integration secrets in SQLite and is recovery-critical. Render both through the SOPS-nix environment template. Set Homarr's `BASE_URL` to the private Tailscale Serve origin while the credentials-bootstrap option is enabled, then to the canonical public origin in steady state. Leave `NEXTAUTH_URL` unset so the OIDC callback is derived from the forwarded request host and can use either registered URI.

### HD-4: Persistent state gets an explicit recovery path

Register `/srv/data/homarr` under `services.state-backups.services.homarr` as an export-mode backup. Capture the rest of `/appdata` raw, exclude the live SQLite database directory, and run `sqlite3 -readonly ... '.backup ...'` to create a consistent database artifact. Preserve both generated secrets and a pre-upgrade backup for v2 image/schema updates. Document restoration into staging and the ordered service restart.

### HD-5: Keep the existing service catalog as the URL authority

Homarr's app tiles are manually curated user-facing links. The initial catalogue can contain URLs that are already published in canonical web policy, but Nix must not attempt to mirror all route entries into Homarr's database. User customization and service endpoint policy have different ownership; a hostname/route change remains a policy change and may require a corresponding UI edit.

## Risks / Trade-offs

- [The pinned image index includes arm64, but the OCI host's runtime behavior is not yet proven] → Keep the arm64 manifest check as evidence, then verify container evaluation and listener/state permissions before operator deployment.
- [Kanidm OIDC account creation and group behavior must match the release] → Configure local OIDC group management; verify the private Tailscale callback and two distinct Kanidm accounts before public acceptance.
- [Homarr's UI-managed data can drift from canonical route policy] → Treat the catalogue as presentation-only; document that links may need manual maintenance and never duplicate origin/transport facts.
- [Live SQLite files may not form a consistent backup, and encrypted integration values become unreadable without the key] → Verify the export/capture path and restore a scratch copy; preserve the exact encryption key with the recovery instructions.
- [No Cloudflare Access means the app's own auth is the sole browser gate] → Require OIDC in steady state, no anonymous board, no permanent credentials fallback, and verify unauthenticated requests cannot read dashboard content.
- [v2 upgrades can migrate persisted data and prevent older versions from using it] → Back up the full appdata and encryption key before upgrades; document restore-before-image-rollback.

## Migration Plan

1. Add the pinned image, Tailscale-Serve route (with its public release withheld), Kanidm client and private callback, service aspect, OCI selection, and backup contract.
2. Operator prepares the encrypted service secrets and OIDC client secret; enable the temporary credentials provider and use the private Tailscale origin to create the initial admin, create and promote a Kanidm-backed account, and verify separate users and board permissions.
3. Remove the temporary local account, then disable credentials and release the public route together so `BASE_URL` changes from the private Tailscale origin to `https://home.shrublab.xyz`; configure initial user-facing boards in Homarr's UI.
4. Verify one backup and scratch restore before treating the dashboard state as recoverable.
5. Rollback by stopping Homarr and restoring the pre-upgrade `/appdata` plus the matching image configuration and encryption key. Do not rely on changing only the image tag after a database migration.

## Open Questions

None that change the agreed scope. The pinned image, OIDC environment, private callback, SQLite export, and first-user flow are implementation checks tracked in the tasks.
