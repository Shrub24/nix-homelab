# Research: Inbox Zero on OCI Melbourne, Gmail and Bifrost

## Summary

Inbox Zero 2.30.0 has a published Linux arm64 image matching its tagged source. The smallest complete Gmail deployment is that web image, native PostgreSQL, authenticated public Pub/Sub delivery, local cron timers, Google OAuth and the existing OCI Bifrost origin; Redis, a worker and a Redis HTTP bridge are not required. This is functional but best-effort: Gmail processing acknowledges before completion, and enabling BullMQ does not make that path durable.

Planning only. No configuration, secrets, live hosts, mailbox calls or provider-key calls were changed or exercised. Selected placement is `oci-melb-1`; Microsoft, GeoPulse and optional feature services are outside scope.

## Findings

### 1. Published image and source

**Direct evidence; high confidence.** Anonymous GHCR manifest/config reads confirmed:

| Item | Value |
|---|---|
| Published tag | `ghcr.io/elie222/inbox-zero:2.30.0` (no leading `v`) |
| Multiarchitecture index | `sha256:e9970c499a79b8a15bbab21363d1b87ea247c75b2721f036c7cee0e2c78d1fcc` |
| Linux arm64 manifest | `sha256:1dea6c2b9a43712290cc1112004af95439f04f380beff1b1d11e2d8375b26d13` |
| Arm64 config blob | `sha256:b9ae27d7a1f606ee1581e4ca5143464ecfb9da89fffa38d3c83fb3511f502c46` |
| OCI revision label | `c7a640d51944f2eec5f08bd72c6ed57f777647d4` |
| OCI version / created labels | `2.30.0` / `2026-05-18T11:41:56.445Z` |
| Source tag | `v2.30.0`, peeled to the same revision |
| Runtime | `/app/docker/scripts/start.sh`, port `3000/tcp`, no image `User` setting |

Pin `ghcr.io/elie222/inbox-zero:2.30.0@sha256:e9970c499a79b8a15bbab21363d1b87ea247c75b2721f036c7cee0e2c78d1fcc`; the index selects arm64 on OCI. The arm64 manifest is also available for an architecture-specific pin. These labels identify the publisher's claimed source; no reproducible image rebuild was performed. The image license label is `NOASSERTION`, not licensing evidence.

Registry evidence: [index](https://ghcr.io/v2/elie222/inbox-zero/manifests/2.30.0), [arm64 manifest](https://ghcr.io/v2/elie222/inbox-zero/manifests/sha256:1dea6c2b9a43712290cc1112004af95439f04f380beff1b1d11e2d8375b26d13), [config](https://ghcr.io/v2/elie222/inbox-zero/blobs/sha256:b9ae27d7a1f606ee1581e4ca5143464ecfb9da89fffa38d3c83fb3511f502c46) (anonymous registry bearer token required).

The image starts Prisma migrations but logs a warning and continues if migration fails. Startup is not proof of a migrated database. `NEXT_PUBLIC_*` placeholders are substituted at startup, so the official image's public URL is runtime-configurable. Source: [start.sh](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docker/scripts/start.sh), lines 8–29.

### 2. Minimal web environment

**Direct source evidence, plus explicitly recommended operational settings; high confidence.** Values below are planning placeholders, not secret material.

| Variable | Contract |
|---|---|
| `NODE_ENV` | `production` |
| `DATABASE_URL` | PostgreSQL DSN for the provisioned application role/database; required |
| `NEXT_PUBLIC_BASE_URL` | Chosen stable HTTPS application origin, without a path |
| `AUTH_SECRET` | Set a stable secret explicitly; Better Auth uses this, or `NEXTAUTH_SECRET` as fallback |
| `EMAIL_ENCRYPT_SECRET`, `EMAIL_ENCRYPT_SALT` | Required encryption values; preserve for database recovery |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | Required Google web OAuth credentials |
| `GOOGLE_PUBSUB_TOPIC_NAME` | Full `projects/<project-id>/topics/<topic-id>` |
| `GOOGLE_PUBSUB_VERIFICATION_TOKEN` | Nonempty random shared webhook token |
| `CRON_SECRET` | Set explicitly: cron handlers reject missing secrets despite schema optionality |
| `INTERNAL_API_KEY` | Required shared internal-call credential |
| `INTERNAL_API_URL` | Private web origin, e.g. `http://127.0.0.1:3000` in the web container's own namespace; must reach the actual listener |
| `QUEUE_BACKEND` | Explicit `internal` (or leave unset with no QStash token) |
| `NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS` | `true`, as recommended by upstream for self-hosting |
| `AUTH_ALLOWED_EMAILS` | Operator's exact Gmail address; recommended sign-up restriction |
| `DEFAULT_LLM_PROVIDER`, model/base URL | Bifrost settings in finding 6 |

Leave Microsoft/Apple credentials, Google emulation variables, `SSO_LOGIN_ENABLED`, `QSTASH_*`, `REDIS_URL` and `UPSTASH_REDIS_*` unset. Keep optional contacts/calendar/Drive features disabled unless intentionally selected. `ADMINS` is only needed for app-admin operations, not basic Gmail processing.

PostgreSQL requires `uuid-ossp` and `btree_gist` (tagged migrations). Native database export is the primary backup; retain the encryption/auth secrets separately. The proposed native PostgreSQL consumer registration is planning, not an implemented or validated privilege contract.

Sources: [env.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/env.ts), lines 35–112, 137–163, 224–234; [auth.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/auth.ts), lines 185–218; [internal-api.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/internal-api.ts), lines 17–35; [environment docs](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docs/hosting/environment-variables.mdx).

### 3. Gmail OAuth and Pub/Sub

**Direct evidence; high confidence.** Use one Google Cloud project for the OAuth client and Gmail topic. Enable Gmail API and Pub/Sub. Create a Web Application OAuth client with these exact HTTPS redirects on the chosen app origin:

- `/api/auth/callback/google` — sign-in and first Gmail authorization.
- `/api/google/linking/callback` — linking another Google mailbox; include per upstream setup guidance even for the first single-mailbox deployment.

Core scopes are `userinfo.profile`, `userinfo.email`, `gmail.modify`, `gmail.settings.basic`. Contacts are conditional on `NEXT_PUBLIC_CONTACTS_ENABLED`; calendar/Drive are separate optional connections, not required sign-in scopes. This corrects the earlier broad scope list.

Create a Pub/Sub topic and grant `roles/pubsub.publisher` to `gmail-api-push@system.gserviceaccount.com`. Configure a push subscription to:

```text
https://<app-origin-host>/api/google/webhook?token=<GOOGLE_PUBSUB_VERIFICATION_TOKEN>
```

The route accepts **POST**, decodes wrapped Pub/Sub `message.data` as base64 JSON containing `emailAddress` and `historyId`, and checks the query token against the env value. Missing env token gives 503; a mismatched token gives 403; an empty env string deliberately disables token checking. The route does not itself verify a Google push OIDC bearer JWT. For this proposal keep the token nonempty and retain wrapped delivery. Redact query strings in edge/access logs to avoid exposing the token.

The public webhook must bypass Cloudflare Access; Google cannot supply an interactive Access identity. Keep database, internal job endpoints and cron calls private. Do not assume an origin matcher or an Access opt-out is already implemented: public route placement and path-specific exposure remain proposal work. Avoid applying an interactive gate to OAuth callback requests either.

`watchGmail()` subscribes to INBOX and SENT using the configured topic. Initial authenticated `GET /api/watch` and the renewal job use the watch manager; successful OAuth alone does not prove watches and automation rules are active. Provision a rule in the UI and confirm watch renewal after first sign-in during eventual operator acceptance.

Sources: [tagged Google setup](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docs/hosting/google-oauth.mdx), [Pub/Sub setup](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docs/hosting/google-pubsub.mdx), [scopes.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/gmail/scopes.ts), lines 1–30; [webhook route](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/app/api/google/webhook/route.ts), lines 17–141; [watch.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/gmail/watch.ts), lines 10–43.

**Google consent caveat.** External Testing works for operator setup but Google expires its Gmail-scoped refresh tokens after seven days. It is not an unattended long-term deployment configuration. Google's OAuth policies distinguish personal use (not shared, or fewer than 100 personally known users) from production apps subject to production verification rules. The earlier blanket statement that all multi-user or published personal apps need verification was too strong. Determine the project's eligible consent/publishing configuration without assuming enterprise/public-app verification requirements automatically apply to this personal instance. Restricted-scope classification remains true; no verification exemption or consent-screen flow was exercised here.

Sources: [Google OAuth token expiration](https://developers.google.com/identity/protocols/oauth2#expiration), [Google OAuth policies](https://developers.google.com/identity/protocols/oauth2/policies#use-separate-projects-for-testing-and-production). Direct inspected passages; high confidence about seven-day Testing expiry and the stated personal-use definition.

### 4. Timers and request authentication

**Direct evidence; high confidence.** All proposed timers call the private web origin via **GET** with `Authorization: Bearer <CRON_SECRET>`. Use HTTP-failure-sensitive requests; the upstream Compose `curl -s` loops do not reliably report HTTP errors as failed commands.

| Endpoint | Proposed cadence | Required for selected scope? |
|---|---|---|
| `/api/watch/all` | Every 6 hours | Yes: mailbox push watch renewal |
| `/api/cron/scheduled-actions` | Every minute | Yes for delayed/scheduled email actions using internal fallback |
| `/api/cron/automation-jobs` | Every 15 minutes | Only if proactive automation jobs are enabled |
| `/api/follow-up-reminders` | Hourly | Only if follow-up reminders are enabled |
| `/api/meeting-briefs` | Every 15 minutes | No: optional calendar feature |
| `/api/resend/digest/all` | Optional digest schedule | No: not basic Gmail processing |
| `/api/cron/reasoning-retention` | Daily | Only if retention policy is selected |
| `/api/cron/draft-cleanup` | Daily | Only if draft cleanup is selected |

`/api/watch/all` also has POST support using JSON `{ "CRON_SECRET": "..." }`; do not confuse that with GET bearer auth. `/api/cron/scheduled-actions` supports the same two checks. Set `CRON_SECRET` rather than relying on its optional env schema.

**Cadence discrepancy:** tagged Compose calls scheduled-actions every **900 seconds**, while the tagged self-host guide and Vercel schedule say **every minute**. The proposed one-minute timer follows the documented delayed-action contract, not the Compose loop. Watch renewal is present in Compose at 21600 seconds; the earlier brief omitted it by reading only the first part of the sidecar.

Sources: [cron.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/cron.ts), lines 4–38; [watch/all](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/app/api/watch/all/route.ts), lines 1–38; [scheduled-actions](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/app/api/cron/scheduled-actions/route.ts), lines 14–32; [Compose](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docker-compose.yml), lines 109–160; [self-host guide](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docs/hosting/self-hosting.mdx), lines 128–179; [Vercel schedules](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/vercel.json).

### 5. App login and Kanidm

**Direct evidence; high confidence.** For the selected Gmail-only configuration, use Google login. Better Auth's Google social provider requests the core Gmail scopes and offline consent, so first sign-in also authorizes Gmail. Password login is disabled.

Generic Kanidm OIDC is **not an exposed deployment contract at this tag**. The generic OAuth plugin is configured only for Google/Microsoft emulation. `SSO_LOGIN_ENABLED=true` exposes organization SSO, but the supported admin registration accepts **SAML metadata XML**, stores `samlConfig` and returns `/api/auth/sso/saml2/callback/<providerId>`. No application source writes `oidcConfig`; the presence of that database field or Better Auth library capability is not proof of an app OIDC integration. No native Kanidm OIDC env knobs or supported provider setup were found. Do not repurpose `GOOGLE_BASE_URL`: it is an OAuth/resource API emulator seam, not an independent login IdP.

SAML SSO is separate from mailbox authorization and configured by an app admin (`ADMINS`), but it is unnecessary here. Kanidm OIDC would require new upstream/application integration and is not part of this proposal.

Sources: [auth.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/auth.ts), lines 54–84, 135–177, 211–235; [SSO actions](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/actions/sso.ts), lines 13–105; [SSO guide](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docs/hosting/sso.mdx).

### 6. Bifrost contract

**Direct app evidence; high confidence. Integration remains untested.** Set:

```text
DEFAULT_LLM_PROVIDER=openai-compatible
DEFAULT_LLM_MODEL=shrublab-text
OPENAI_COMPATIBLE_MODEL=shrublab-text
OPENAI_COMPATIBLE_BASE_URL=http://<OCI-container-reachable-Bifrost-origin>/v1
```

The origin must be reachable from the web container. Use the existing same-host Bifrost container-facing service address, not container loopback and not the public Access-gated route. `shrublab-text` and colocated Bifrost placement come from the existing fleet research/context; they were not reconfigured here. No provider-prefix rewrite is needed in Inbox Zero: it sends the selected model string to the gateway.

`OPENAI_COMPATIBLE_MODEL` is the branch fallback when no selected `aiModel` is passed; the provider uses `aiModel` first. The API-key resolution is a user's configured `aiApiKey`, then the shared **`LLM_API_KEY`**. There is no `OPENAI_COMPATIBLE_API_KEY` knob. The app can omit a key for this branch; use no real provider key for an unauthenticated gateway, or the gateway's actual client credential policy if one is enabled. A user-stored key/model may override deployment defaults.

The SDK is `createOpenAICompatible`, not a plain fetch shim, and is instantiated with `supportsStructuredOutputs: true`. Bifrost and the routed model must accept the SDK's structured-output/JSON-schema requests and produce schema-conforming output; OpenAI compatibility alone does not prove this. Ordinary chat success is insufficient acceptance evidence. Test a representative app-generated structured request at implementation acceptance, without routing via the public edge. No live LLM request was made here.

Source: [model.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/llms/model.ts), lines 245–264 and 587–592; [env.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/env.ts), lines 84–112 and 137–138.

### 7. Queue choice and actual reliability boundary

**Direct evidence; high confidence. Recommendation is researcher inference.** Choose `internal` for the smallest selected stack. It needs neither Redis nor a worker. Internal job forwarding uses `INTERNAL_API_URL`, POST JSON and `x-api-key: <INTERNAL_API_KEY>`; the implementation schedules the fetch using Next.js `after()`, catches transport exceptions, and does not reject HTTP error statuses or persist retry state.

BullMQ is a meaningful optional upgrade for the jobs that use the common dispatcher: `QUEUE_BACKEND=bullmq`, persistent native Redis via `REDIS_URL`, and the same image running `/app/docker/scripts/start-worker.sh`. Worker env needs `REDIS_URL`, `INTERNAL_API_KEY` and `INTERNAL_API_URL` (or public URL fallback). Its default queues are `automation-jobs`, `digest-item-summarize`, `email-summary-all`, `email-digest-all`; `WORKER_QUEUES` can override names/concurrency. Producer jobs have three attempts and exponential 5-second backoff; worker HTTP non-2xx responses throw. A Redis HTTP bridge is not necessary for this BullMQ path.

**Crucial limitation:** `/api/google/webhook` returns success immediately, then calls Gmail history processing in `after()`; it does not enqueue the webhook through BullMQ. Redis plus a worker therefore is **not required for core Gmail processing and does not guarantee its durability**. Gmail processing also limits history gaps and advances its stored history ID when history has expired. Do not promise lossless catch-up or automatic recovery from every accepted-but-unprocessed notification.

Recommendation: default to internal plus the two mandatory timers. If reliable retryable digest/proactive automation is selected later, add persistent Redis and the worker for those features. If “reliable operation” means guaranteed completion of every acknowledged mail notification across web restarts, neither upstream topology meets that requirement from the inspected source: durable webhook admission/reconciliation is a separate unresolved upstream design issue, not a reason to add an unused worker by default.

Sources: [dispatch.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/queue/dispatch.ts), lines 1–85; [upstash/index.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/upstash/index.ts), lines 117–161; [bullmq.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/queue/bullmq.ts), lines 13–91; [worker runtime](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/worker/src/runtime.mjs), lines 1–166; [Gmail history processor](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/app/api/google/webhook/process-history.ts), lines 25–165.

### 8. Personal self-hosting, license text and feature gates

**License text — direct evidence, high confidence.** The root license adds monetization and five-or-more-business-user restrictions to AGPLv3, then explicitly exempts personal, educational and research use and organizations with fewer than five business users. `apps/web/ee/LICENSE.md` says its covered software requires a commercial subscription for production use; it also limits its scope to parts not distributed under AGPLv3 and treats specified client-side material as AGPLv3.

**Upstream guidance and code — direct evidence, high confidence.** The tagged environment guide recommends `NEXT_PUBLIC_BYPASS_PREMIUM_CHECKS=true` for self-hosting. The flag is not merely cosmetic: server-side `isPremiumRecord`, `isActivePremium` and other entitlement checks return true, and the tier resolver returns `PROFESSIONAL_ANNUALLY`. SSO is configured by self-hosted app admins per the SSO guide, not by a commercial `ee/` provider registry.

The tagged `ee/` tree contains billing integrations (Apple, Stripe, Lemon). Imports outside it include billing routes, premium seats/actions, admin actions and referral tracking; the earlier count of 13 files included tests, not 13 mandatory runtime patch sites. Bundling/importing billing code does not by itself establish that personal self-hosting must buy a subscription. Neither does a premium bypass flag grant legal rights beyond the licenses. Keep billing-provider credentials unset for this personal deployment.

**Interpretation / remaining uncertainty:** official self-host guidance and the root personal-use exemption support planning a personal instance without assuming a paid subscription. The commercial subtree's scope and execution obligations are legal questions not resolved by an import count. The earlier “subscribe, strip ee or do not run” conclusion was overstated and is withdrawn. If definitive legal certainty is needed, ask the maintainer specifically about personal use of the official image with billing inactive and the documented bypass enabled.

Sources: [root LICENSE](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/LICENSE), lines 8–31; [ee/LICENSE.md](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/ee/LICENSE.md), lines 1–28; [environment guide](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/docs/hosting/environment-variables.mdx), premium-bypass row; [premium/index.ts](https://github.com/elie222/inbox-zero/blob/c7a640d51944f2eec5f08bd72c6ed57f777647d4/apps/web/utils/premium/index.ts), lines 63–140, 198–206.

## Contradictions and corrections

- Compose scheduled-actions cadence is 15 minutes; the self-host guide/Vercel schedule says one minute. Use the latter for the proposed timer and preserve the discrepancy.
- The earlier brief's three-endpoint cron list was incomplete; watch renewal is included in tagged Compose.
- Google sign-in does not always request calendar/contacts scopes; core Gmail scopes are narrower.
- Google External Testing has seven-day Gmail refresh-token expiry. Personal-use verification policy is not the same as public commercial production policy.
- `ee/` bundling is not proof of a subscription obligation for personal self-hosting; the earlier blanket blocker is withdrawn.
- A generic OAuth library import and an `oidcConfig` schema field do not establish a supported Kanidm OIDC deployment seam.
- BullMQ retries selected background jobs, not Gmail webhook admission.

## Missing evidence

- No image was launched on OCI; matching revision labels are publisher provenance, not independent build attestation.
- Bifrost/selected model handling of app-generated structured output remains untested.
- Google consent-screen/publishing eligibility, refresh-token longevity outside Testing, and real watch/webhook delivery remain operator acceptance checks.
- No exhaustive periodic mailbox reconciliation audit or restart/failure experiment was performed; Gmail durability must not be promised.
- No legal opinion or maintainer clarification was obtained on the commercial subtree.
- Database extension provisioning/migration privileges and concrete web-policy/secret wiring remain proposal work.

## Sources and validation

Kept: tagged source and tagged hosting docs linked per finding; original Google OAuth policies and token-expiration reference; anonymous GHCR manifests/config. The prior `geopulse-inbox-zero.md` brief was reused as a starting point, not treated as proof where it overstated contracts. Current self-host docs and issue #383 were discovery aids only; no newer-branch behavior was substituted for 2.30.0.

Validation: read the pinned checkout's handlers, worker, SDK config and license texts; inspected image platform/config labels; fetched Google's original policy pages. `source_check` retrieved evidence but returned `unclear` because automated semantic assessment was unavailable; the decisive Google passages were manually fetched and inspected. No mailbox or provider-key calls and no live changes were made.

## Next steps

Propose only the web image, native PostgreSQL consumer, secret/environment bindings, selected public Gmail webhook and two local timers on OCI. Explicitly record best-effort ingestion and the structured-output acceptance gap. Add Redis/worker only for a selected durable background-job requirement; do not add calendar, contacts, Drive, billing, SSO or Redis HTTP services by default.
