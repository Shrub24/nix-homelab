## Context

The fleet has identity (Kanidm), edge ingress (Caddy on do-admin-1), notifications (apprise daemon), shared PostgreSQL, and declarative state backups — all established capabilities. Karakeep proved the pattern for running an OIDC-authenticated, Tailscale-upstream service on oci-melb-1 with Kanidm client registration, SOPS secrets, and Caddy ingress. Paperless-ngx is the natural next service: NixOS-native, requires the same infrastructure capabilities (PG, OIDC, ingress, backups), and adds AI document processing via paperless-gpt + docling-serve.

## Goals / Non-Goals

**Goals:**
- Paperless-ngx running as a native NixOS service on oci-melb-1 with `services.paperless`
- OIDC authentication via Kanidm (no local Paperless password auth for daily use)
- Edge ingress through do-admin-1 Caddy over Tailscale (same `tailscale-upstream` pattern as Karakeep)
- Post-consume notification via apprise daemon
- AI auto-classification (titles, tags, correspondents) via paperless-gpt sidecar container with bifrost gateway LLMs
- AI-enhanced OCR via docling-serve (native NixOS service consumed by paperless-gpt)
- Django group seeding for OIDC sync (Kanidm groups matched by name)
- State backups via `services.state-backups`
- Shared PostgreSQL with dedicated `paperless` database

**Non-Goals:**
- IMAP email consumption (deferred to follow-up phase — requires Resend middleman or separate IMAP mailbox)
- nginx reverse proxy in front of Paperless (Caddy-over-Tailscale uses direct `0.0.0.0:8080` binding)
- User provisioning via Kanidm group sync (Paperless handles user creation separately from OIDC login)
- ASN QR label generation (low priority, can add later)
- Public internet exposure (Cloudflare-proxied + Access-gated, same as Karakeep)

## Decisions

### D1: Direct port binding over nginx reverse proxy
Paperless supports `configureNginx` which defaults to `127.0.0.1`. Binding to `0.0.0.0` on port 8080 matches the Karakeep container pattern — Caddy on do-admin-1 proxies directly via Tailscale. No nginx layer to maintain, no TLS termination at the origin.

### D2: paperless-gpt as Podman sidecar (not native service)
paperless-gpt is a Go binary with its own web UI, distributed only as a container image. Running it as a Podman container matches the established Karakeep pattern (systemd-managed, tmpfiles for state, explicit dependencies). It communicates with host-local Paperless and docling-serve via `host.containers.internal` and with LLMs via the bifrost gateway's container-facing endpoint.

### D3: docling-serve as native NixOS service (not container)
`pkgs.docling-serve` (v1.10.0) is available in nixpkgs. Running it as a native systemd service avoids unnecessary container overhead. paperless-gpt supports Docling Server as an OCR provider via `OCR_PROVIDER: "docling"`.

### D4: Bifrost gateway as LLM provider (no separate Ollama)
paperless-gpt uses OpenAI-compatible API. The bifrost gateway already provides this for Karakeep. Using it avoids deploying and maintaining a separate Ollama instance. paperless-gpt's `OPENAI_BASE_URL` points to the same gateway endpoint.

### D5: Sealed SOPS secret file pattern (not per-key env template)
Paperless has many environment variables (`PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS`, `PAPERLESS_ADMIN_PASS`, email settings, etc.). Rather than registering each as a separate `sops.secrets` entry, use a single SOPS-encrypted env file sourced as an `environmentFile`. This matches the Karakeep `secretFiles.host` → `sops.templates.*.environment` pattern. The agent creates the scaffold/template only; the user creates the encrypted secret file. OIDC client secret remains in a separate file (shared with other OIDC clients on the same host).

### D6: Post-consume notification via notify CLI
Paperless natively supports `PAPERLESS_POST_CONSUME_SCRIPT` — a script called after each consumed document with env vars like `DOCUMENT_TITLE` and `DOCUMENT_FILE_NAME`. A thin wrapper shell script calls `notify info "Paperless: $DOCUMENT_TITLE"`. No polling, no API calls. Failure notifications use the existing `services.notification-daemon.monitor` module.

### D7: OIDC as sole auth for daily use
Paperless supports OIDC via django-allauth. Setting `PAPERLESS_REDIRECT_LOGIN_TO_SSO = true` and `PAPERLESS_DISABLE_REGULAR_LOGIN = true` means all daily logins go through Kanidm. An initial admin user is created via SOPS-administered password for first setup.

### D8: Django group seeding for OIDC sync
Paperless OIDC group sync (`PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS`) matches Django `Group.name` exactly against claim strings from Kanidm. A Python seed script runs as a systemd oneshot to pre-create the Django groups that Kanidm will emit. Taxonomy (tags, correspondents, document types) is managed imperatively via the Paperless UI — it is application state, not infrastructure.

## Risks / Trade-offs

- **[paperless-gpt container stability]** Container restart may race with Paperless startup → systemd `wants`/`after` ordering on paperless-web.service
- **[docling-serve memory]** `docling-serve` loads ML models into memory. On OCI Free Tier (4GB RAM), may need increased swap or reduced batch sizes → Mitigation: configure via `UVICORN_WORKERS=1` and set `OOMScoreAdjust=200` in systemd
- **[OIDC callback mismatch]** Paperless callback URL must match the Caddy subdomain exactly → Mitigation: derive callback URL from `web-services.nix` route config, not hardcoded
- **[First deploy without OIDC groups]** Paperless OIDC login works but group sync is empty if the seed script fails → Mitigation: seed script runs as `Type=oneshot` with `RemainAfterExit=true`, non-fatal on failure
- **[ORACLE ARM4 RAM pressure]** Paperless + PostgreSQL + docling-serve + paperless-gpt + existing services may exceed 4GB → Mitigation: monitor via Beszel, add swap if needed
- **[paperless-gpt port conflict]** paperless-gpt's built-in web UI defaults to port 8080, colliding with Paperless's port → Mitigation: explicitly bind paperless-gpt to a different port (e.g., `PAPERLESS_GPT_PORT=5050`) in the Podman container config

## Migration Plan

1. Create the Paperless secret scaffold/template, then have the user create `secrets/services/paperless.yaml` with `PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS`, `PAPERLESS_ADMIN_PASS`
2. Add paperless OIDC client to `policy/identity.json` and wire secret in `do-admin-1/default.nix`
3. Add paperless edge route to `policy/web-services.nix`
4. Implement `modules/services/paperless/` module
5. Implement `modules/applications/paperless/` composition layer
6. Wire post-consume notification and state-backups
7. Implement paperless-gpt container module
8. Implement docling-serve native service
9. Wire OIDC group seed script
10. Wire host config in `oci-melb-1/default.nix`
11. Deploy to oci-melb-1
12. Create initial superuser via `paperless-manage createsuperuser`
13. Verify OIDC login, document consumption, AI processing, notifications
