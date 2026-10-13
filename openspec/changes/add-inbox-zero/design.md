# Design

## Context

See `proposal.md` for scope and `docs/research/inbox-zero-deployment.md` for tagged-source evidence. The user selected OCI, Gmail, public webhooks and Bifrost. OCI already selects native PostgreSQL, Bifrost, ingress, container-environment recreation and state backups. Current composition uses discovered domain contributors and declaration-only consumer contracts; older OpenSpec context mentioning transitional roots or LiteLLM-specific database options is not the implementation authority.

## Goals / Non-Goals

**Goals:** one application container, native database ownership, restricted Google login, authenticated mail delivery, scheduled maintenance and explicit live acceptance.

**Non-Goals:** rewriting upstream ingestion, guaranteeing delivery, Microsoft, generic OIDC, calendar/contacts/Drive, billing, Redis/worker, custom image builds or Terraform management of Google Cloud. Do not add per-variable options or general queue abstractions without a consumer.

## Decisions

### IZ-1 One discovered application owner

Add `modules/apps/inbox-zero.nix`, publishing `flake.modules.nixos.inbox-zero`; selection enables the service. OCI selects it and binds `services.inbox-zero.secretFiles.host`. Runtime, environment, network, database registration, maintenance units and assertions belong to the aspect, not its host. Other hosts remain unchanged.

Pin `ghcr.io/elie222/inbox-zero:2.30.0@sha256:e9970c499a79b8a15bbab21363d1b87ea247c75b2721f036c7cee0e2c78d1fcc` in `policy/oci-images.nix`. The published arm64 image identifies source `c7a640d51944f2eec5f08bd72c6ed57f777647d4`. Version selection is deliberate; upgrades must recheck these source seams. A source build adds no required behavior and is excluded.

### IZ-2 Bridge networking and local substrate

Use one app-owned Podman bridge, loopback-only host port publication and the established `host.services.internal` service-address mapping. Choose an unused host port at implementation and declare it once in web policy; the container listens on 3000. PostgreSQL uses `services.postgres.localEndpoint.port`; the database host is the fleet service address, not loopback inside the bridge.

Import `modules/database/postgres/_consumer.nix` and register the `inbox-zero` database/role with one authoritative SOPS password, the bridge CIDR and idempotent setup SQL for `uuid-ossp` and `btree_gist`. Setup runs as postgres in the current mechanism, so the application need not receive superuser privileges. These are shipped PostgreSQL extensions; confirm availability against the placing server. Require successful database provisioning before the application starts. Verify Prisma migration status live: upstream startup catches migration errors and continues, so listening on 3000 is insufficient.

No second database container or duplicate database backup. The substrate already exports registered databases.

### IZ-3 Google login and public origin

Default origin is `https://inbox.shrublab.xyz`, route key `inbox-zero`, `direct` on OCI. Set Cloudflare Access off and application OIDC off; use Google authorization as both sign-in and Gmail connection. `AUTH_ALLOWED_EMAILS` must be populated explicitly through the app environment, with fail-closed startup validation of required values. No Kanidm client is added: the tagged app exposes SAML organization SSO, not a supported generic OIDC configuration.

Configure callbacks `/api/auth/callback/google` and `/api/google/linking/callback`. Core authorization requests profile/email plus `gmail.modify` and `gmail.settings.basic`; optional contacts, calendar and Drive remain disabled. Only the app route is public; PostgreSQL and Bifrost keep their existing private listeners. Cron callers use loopback, while publicly reachable cron/internal handlers retain their upstream credential gates. Do not invent a new path-policy framework to hide those authenticated handlers.

Google Pub/Sub targets `/api/google/webhook?token=<secret>`, with wrapped delivery and a nonempty `GOOGLE_PUBSUB_VERIFICATION_TOKEN`. Grant the Gmail publisher identity access to the selected topic. This tag checks a shared query token, not Google OIDC push JWTs. Do not enable request-URL logging that reveals query credentials; the runbook covers Cloudflare/Google logging controls too. Inspect the rendered edge configuration and validate actual requests during rollout.

### IZ-4 Secrets, encryption and recovery

Use `secrets/services/inbox-zero.yaml` with an OCI-and-owner-only `.sops.yaml` rule and an operator bootstrap template. The service owns all secret registrations and its rendered environment. Include database password, Google credentials, stable auth secret, email encryption secret/salt, Pub/Sub token, cron secret and internal API key; retain operator Gmail allowlist and topic settings alongside the documented bootstrap inputs. Do not inspect or manufacture plaintext secrets as an agent.

Set `NODE_ENV=production`, `NEXT_PUBLIC_BASE_URL` from the route, explicit `QUEUE_BACKEND=internal`, `NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS=true` following upstream personal self-host guidance, and container-local `INTERNAL_API_URL=http://127.0.0.1:3000`. Microsoft, billing, emulation, SSO, QStash and Redis variables remain absent. The fleet's `container-env` invariant handles rotation-driven recreation. Verify environment consumption and mount ordering rather than adding redundant restart hashes.

Native PostgreSQL state stays under its existing host data root. Do not create an unused `/srv/data/inbox-zero` volume if the app has no durable file state. Recover database plus original encryption secrets, then reconnect/revalidate Google authorization and renew watches. Schema upgrades require a pre-deploy export: rolling back an image does not roll back its migrations.

### IZ-5 Minimal maintenance, honest reliability

Create authenticated GET jobs for `/api/watch/all` every six hours and `/api/cron/scheduled-actions` every minute, calling the loopback-published app port. Deliver `CRON_SECRET` through systemd credentials to a curl configuration/header file, never through argv or public URLs. Use HTTP-failure-sensitive calls and the existing notification registry. Start after the web unit and require the data mount where needed. Use native timers instead of Compose loops. Optional automation/digest/calendar timers are excluded.

The tagged guide and Vercel schedule use one minute for scheduled actions, while Compose uses fifteen; adopt the former. The internal dispatcher and Gmail webhook are best-effort. BullMQ would retry selected dispatched jobs but Gmail webhook processing bypasses it, so adding Redis does not solve acknowledged-notification loss.

### IZ-6 Bifrost integration and acceptance

Resolve the existing OCI container-reachable Bifrost endpoint, following `modules/apps/karakeep.nix`, and append `/v1` once. Set `DEFAULT_LLM_PROVIDER=openai-compatible`, `DEFAULT_LLM_MODEL` and `OPENAI_COMPATIBLE_MODEL` from the fleet text alias, and `OPENAI_COMPATIBLE_BASE_URL` from that endpoint. The app's shared credential knob is `LLM_API_KEY`, not `OPENAI_COMPATIBLE_API_KEY`; omit a real provider credential for the unauthenticated fleet gateway. User-stored model/key choices can override defaults.

Verify a representative app-generated JSON-schema request with the routed model and then one controlled mailbox rule. No silent provider fallback. A failed structured-output check blocks AI acceptance, rather than prompting an unrelated gateway-policy change.

## Risks / Trade-offs

- **Accepted mail can be lost across a restart** → record best-effort semantics and watch/history recovery limits; do not claim lossless catch-up.
- **Testing consent expires Gmail refresh tokens in seven days** → require operator selection of an eligible personal-use consent/publishing configuration for ongoing use. Do not assume a verification exemption has been exercised.
- **Migrations warn and continue** → verify migration status independently before accepting the service; take an export before upgrades.
- **Query-token disclosure** → disable or redact request-query logging wherever enabled, including external log products; preserve token authentication.
- **AI model mismatch** → exercise actual structured requests before enabling unattended rules.
- **License ambiguity** → preserve root personal-use exemption, official self-host guidance and commercial subtree caveats. Bundled billing imports are not proof of a subscription requirement, and a bypass flag is not a legal grant.

## Migration Plan

1. Operator prepares encrypted app secrets and Google OAuth/Pub/Sub resources; land encrypted file before consumers require its path. Publish no placeholder credentials.
2. Validate the module, host instantiation, effective network/secret/endpoint relationships, web-policy export and existing repository gates. CI remains validation-only.
3. Deploy OCI only on operator authorization. Check database provisioning and migration status, then restricted Google sign-in.
4. Test unauthorized webhook rejection, valid mail delivery, watch renewal, scheduled-action authorization and a controlled Bifrost-backed rule.
5. Record live acceptance separately from configuration tests. On failure stop new processing; rollback the generation, and restore the database only if schema compatibility requires it. Google OAuth grants and subscriptions are external state and need explicit cleanup if abandoning the service.
