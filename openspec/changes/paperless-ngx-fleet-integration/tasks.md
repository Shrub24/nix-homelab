# Tasks: paperless-ngx-fleet-integration

## Phase 1 — Prerequisites

- [x] **1.1** — Create SOPS template/scaffold for paperless secrets
  - Agent creates `.sops.yaml` path rule and empty scaffold file for `secrets/services/paperless.yaml`
  - User creates encrypted `secrets/services/paperless.yaml` with `PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS`, `PAPERLESS_ADMIN_PASS`
  - *Crit.* Do not decrypt or manually edit secrets — follow repo convention (user runs `sops` to encrypt)

- [x] **1.2** — Add `paperless` OIDC client to `policy/identity.json`
  - `routeKey: "paperless"`, `callbackPath: "/accounts/oidc/kanidm/login/callback/"`
  - `scopeMaps`: `admins` + `shrublab-users`

- [x] **1.3** — Wire OIDC client secret in `do-admin-1/default.nix`
  - Add `paperless = ../../secrets/hosts/oci-melb-1/oidc.yaml;` to `secretFiles.oidcClients`

- [x] **1.4** — Add paperless edge route to `policy/web-services.nix`
  - Subdomain `paper.shrublab.xyz`, Tailscale upstream to oci-melb-1
  - `access.oidc.enabled = true`, `access.requireCloudflareAccess = false`

## Phase 2 — Core Paperless Service

- [x] **2.1** — Create `modules/services/paperless/default.nix`
  - Wrap `services.paperless` with `enable`, `dataDir`, `port` (default 8080), `listenAddress` (`0.0.0.0`), `secretFiles.host`
  - Configure shared PostgreSQL (`database.createLocally = false`, DB name/user/pass from env)
  - Configure Tika + Gotenberg for office docs
  - Bind to `0.0.0.0:${port}` (no nginx)
  - Timezone, OCR language, date settings

- [x] **2.2** — Create SOPS template for paperless environment
  - `sops.templates."paperless-environment"` sourcing `PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS`, OIDC client secret, and runtime vars that must not land in the Nix store
  - Expose `PAPERLESS_ADMIN_PASS` to Paperless via its dedicated admin `passwordFile` / credential path rather than relying on the generic environment file alone
  - Render as `environmentFile` consumed by Paperless systemd services
  - Set `PAPERLESS_URL=https://paper.shrublab.xyz`

- [x] **2.3** — Wire OIDC into paperless module
  - `secretFiles.oidc` option providing the Kanidm client secret from `secrets/hosts/oci-melb-1/oidc.yaml`
  - `PAPERLESS_REDIRECT_LOGIN_TO_SSO = true`, `PAPERLESS_DISABLE_REGULAR_LOGIN = true`
  - `PAPERLESS_APPS` includes `allauth.socialaccount.providers.openid_connect`
  - `PAPERLESS_SOCIALACCOUNT_PROVIDERS` JSON configured from `oidc.wellknownUrl`, `oidc.clientId`, and the secret-backed client secret

- [x] **2.4** — Wire post-consume notification hook
  - `PAPERLESS_POST_CONSUME_SCRIPT` → wrapper calling `notify info "Paperless" "New document: $DOCUMENT_TITLE"`
  - Script in `pkgs.writeShellScriptBin`

- [x] **2.5** — Wire state-backups
  - `services.state-backups.services.paperless` with data dir and media dir

## Phase 3 — OIDC Group Seeding

- [x] **3.1** — Define `socialGroups` option on the paperless module
  - List of Django group names to pre-create for OIDC sync with Kanidm

- [x] **3.2** — Create idempotent group seed script
  - Systemd `Type=oneshot` service runs after `paperless-scheduler.service`
  - Uses local `paperless-manage shell` / Django ORM
  - Idempotent: `get_or_create` by name for Django groups
  - Taxonomy (tags, correspondents, document types) managed imperatively via UI

## Phase 4 — AI Enhancement Stack

- [x] **4.1** — Deploy docling-serve as native NixOS service
  - Systemd service using `pkgs.docling-serve`, single worker, memory-constrained
  - Binds to `127.0.0.1:8070`
  - Restart on failure

- [x] **4.2** — Deploy paperless-gpt as Podman sidecar container
  - Module: `modules/services/paperless/paperless-gpt.nix`
  - Podman container (OCI image), systemd-managed
  - Depends on paperless-web.service
  - Configures `PAPERLESS_BASE_URL=http://host.containers.internal:8080`, `OPENAI_BASE_URL` (bifrost gateway container endpoint), `OCR_PROVIDER=docling`, `DOCLING_URL=http://host.containers.internal:8070`, `LLM_PROVIDER=openai`, `LLM_MODEL`, `OPENAI_API_KEY`
  - *Note:* paperless-gpt UI defaults to port 8080 (same as Paperless) — explicitly bind paperless-gpt to a different loopback port (for example via `LISTEN_INTERFACE=127.0.0.1:5050`) to avoid collision

- [x] **4.3** — Wire paperless-gpt environment file
  - Create the scaffold/template path for a SOPS-backed paperless-gpt environment file
  - API token for paperless-gpt to talk to Paperless remains a later user action from the Paperless web UI, consumed via `PAPERLESS_API_TOKEN`
  - All secrets/runtime vars flow through the environment file

## Phase 5 — Host Integration

- [x] **5.1** — Wire paperless application module in `oci-melb-1/default.nix`
  - Import application module
  - Set `secretFiles.host`, `secretFiles.oidc`, OIDC client config

- [x] **5.2** — Validate evaluation
  - Direct `nix eval .#nixosConfigurations.oci-melb-1.config.system.build.toplevel` remained blocked by a local shell env issue (`null` path)
  - Integrated validation succeeded via `just deploy oci-melb-1`

## Phase 6 — Verification (out of scope for current implementation — deferred to later/manual)

- [ ] **6.1** — Deploy to oci-melb-1, create initial superuser, verify OIDC login
- [ ] **6.2** — Test document consumption with a test file
- [ ] **6.3** — Verify post-consume notification via Telegram
- [ ] **6.4** — Verify paperless-gpt auto-classification
- [ ] **6.5** — Verify backups are captured
