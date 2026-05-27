## Why

Paperless-ngx fills the last big document management gap in the fleet. The existing stack has music (Navidrome/Beets), bookmarks (Karakeep), and identity (Kanidm), but no automated document ingestion, classification, and archival. Adding Paperless-ngx with OIDC, AI enhancement, and edge ingress establishes a complete document lifecycle capability that matches the operational maturity of the rest of the fleet.

## What Changes

- New `modules/services/paperless/` module wrapping `services.paperless` with OIDC, secrets, post-consume notification, shared PostgreSQL, and direct Caddy-over-Tailscale ingress (no nginx)
- New `modules/applications/paperless/` application composition layer (secret contracts, OIDC wiring, path defaults)
- New Paperless route in `policy/web-services.nix` — public subdomain `paper.shrublab.xyz`, `tailscale-upstream` exposure, OIDC with Kanidm
- New Kanidm OIDC client registration in `policy/identity.json` for Paperless
- New `paperless-gpt` Podman container deployment (matching Karakeep container pattern) for AI auto-tagging, auto-titling, and LLM-enhanced OCR
- New `docling-serve` native NixOS service for advanced document OCR/understanding, consumed by paperless-gpt
- Post-consume notification hook via apprise daemon
- State backups via existing `services.state-backups`
- Email consumption configuration (IMAP) deferred to follow-up phase

## Capabilities

### New Capabilities
- `paperless-service`: Core Paperless-ngx NixOS service module — native module, OIDC auth, shared PostgreSQL, storage layout, post-consume notification, edge ingress, secrets contract
- `paperless-ai-enhancement`: AI document processing — paperless-gpt sidecar container with LLM auto-classification and docling-serve integration for advanced OCR

### Modified Capabilities
- *(none — all existing capability contracts remain unchanged)*

## Impact

- **New code**: `modules/services/paperless/` (includes `paperless-gpt.nix` submodule), `modules/applications/paperless/`
- **Policy changes**: `policy/web-services.nix` (add paperless route), `policy/identity.json` (add paperless OIDC client)
- **Host config**: `hosts/oci-melb-1/default.nix` (import paperless application module, bind secrets)
- **Secrets**: `secrets/.templates/services/paperless.yaml` scaffold plus user-created `secrets/services/paperless.yaml` (secret key, DB password, admin password)
- **Dependencies**: `services.paperless` (nixpkgs stable), `pkgs.paperless-gpt` (container image), `pkgs.docling-serve` (native package), bifrost gateway (existing), shared PostgreSQL (existing)
- **No nginx override** — paperless listens on `0.0.0.0:8080`, Caddy over Tailscale handles ingress
