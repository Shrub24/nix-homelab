## Why

The fleet has no unified notification infrastructure. The only notification consumer (beets) was hardwired to ntfy.sh via curl, exposing raw URLs, tokens, and HTTP headers across multiple layers. As we add more notification consumers — gatus health alerts, beets duplication approval pings, and fleet-wide system events — each one would independently re-solve token management, routing, and secret ownership.

An apprise-backed notification service consolidates routing, token handling, and consumer abstraction into one owner, following the existing feature-topology secret-contract pattern. A FastAPI daemon replaces both the bash CLI and the webhook middleman, providing a single HTTP endpoint for all consumers (Beszel, Gatus, systemd hooks, deploy-rs, CLI users).

**Core Value:** One notification service module owns all routing internals, secrets, and HTTP endpoint; consumers POST JSON to `127.0.0.1:5555/notify` or use the thin CLI wrapper `apprise-notify` which POSTs to the daemon.

## What Changes

- **NEW** `modules/services/apprise.nix` — notification service module with FastAPI daemon, JSON config, SOPS-managed Telegram bot token, and dedicated `apprise` group for secret access
- **NEW** `apprise-webhook/` — self-contained FastAPI application calling apprise Python library directly (no shell, no jq)
  - `POST /notify` — accepts `{tier, title, message, type}`, dispatches via apprise Python API
  - `GET /health` — health check for Beszel/Gatus monitoring
  - Packageable as `pkgs.apprise-webhook` in flake
- **NEW** `apprise-notify` CLI — thin shell script (or Python one-liner) that POSTs to `127.0.0.1:5555/notify`, replacing the previous bash CLI with jq
- **NEW** `policy/globals.nix` notifications section — fleet-wide Telegram chat ID + per-tier topic mapping (critical, warning, info, music, system)
- **NEW** `secrets/services/apprise.yaml` — SOPS-encrypted service secret for Telegram bot token
- **MODIFIED** `modules/services/beets/default.nix` — notification script migrated from ntfy curl to `apprise-notify music`, ntfy options replaced with single `tier` option
- **MODIFIED** `modules/applications/music.nix` — ntfyAdminUrl/ntfyTokenSecretPath wiring removed, beets notify config simplified to `tier = "music"`
- **MODIFIED** `modules/core/users.nix` — dev user added to `apprise` group
- **REMOVED** beets ntfy_token, hardcoded ntfy URL/topic/headers in shell scripts
- **RETAINED** `secrets/services/firebase-key.json` and ntfy Firebase wiring — still in use by admin service
- **REMOVED** webhook notify hook — Gatus and Beszel POST directly to `/hooks/notify` on the apprise daemon
- **REMOVED** `pkgs.jq` dependency — Python handles JSON natively in the daemon; CLI wrapper uses HTTP POST, no JSON parsing needed
- **PLANNED** wire remaining notification consumers: gatus status alerts, beets duplicate-approval pings, fleet-wide system events, systemd.monitor integration

## Capabilities

### New Capabilities

- `apprise-notification-module`: Notification infrastructure module with FastAPI daemon, JSON config, thin CLI wrapper (`apprise-notify`), SOPS secret ownership, and tier-based routing (chat ID + topic). Exposes HTTP endpoint `127.0.0.1:5555/notify` for programmatic consumers; CLI for systemd hooks, deploy-rs, and SSH sessions.
- `notification-policy-defaults`: Fleet-wide notification defaults in `policy/globals.nix` mapping notification tiers to Telegram topic IDs within a shared supergroup.
- `apprise-webhook-daemon`: FastAPI application that reads `/etc/apprise/notify.json` at startup, calls apprise Python API directly, and serves `POST /notify` and `GET /health`.

### Modified Capabilities

- `beets-automation`: Beets notification subsystem changed from ntfy.sh curl dispatch to `apprise-notify` CLI via tier-based routing. Old ntfy options (ntfyUrl, tokenFile) replaced by single `tier` option.
- `feature-topology`: Apprise follows the existing secret-contract pattern (secretFiles.host input, internal SOPS registration, no secret leakage to consumers). No spec-level changes required — implementation follows existing rules.

## Impact

- **Files created:** `modules/services/apprise.nix`, `apprise-webhook/` (FastAPI app), `secrets/services/apprise.yaml`, `secrets/.templates/services/apprise.yaml`
- **Files modified:** `modules/services/beets/default.nix`, `modules/applications/music.nix`, `modules/core/users.nix`, `hosts/oci-melb-1/default.nix`, `hosts/do-admin-1/default.nix`, `policy/globals.nix`, `.sops.yaml`
- **Files removed:** webhook notify hook from `modules/services/admin/webhook.nix`, `secrets/.templates/applications/music.yaml` (ntfy entries), `secrets/applications/music.yaml` (ntfy_token)
- **New dependency:** `pkgs.python3Packages.apprise`, `pkgs.python3Packages.fastapi`, `pkgs.python3Packages.uvicorn` in system closure (Python already present via apprise)
- **Dependency removed:** `pkgs.jq` (~400KB), adnanh/webhook notify hook
- **Secret contract:** `services.apprise.secretFiles.host` → `secrets/services/apprise.yaml` → `/run/secrets/apprise/telegram_bot_token` (`0440 root:apprise`) — daemon reads at startup, no group membership required for consumers
- **HTTP contract:** `POST http://127.0.0.1:5555/notify` with JSON body `{tier, title, message, type}` — loopback-only, no auth, any local process can send
- **CLI contract:** `apprise-notify <tier> <title> [message]` — Python script POSTs to daemon, works from any process (no special group required)
- **Remaining consumers to wire:** gatus alerts, beets duplicate-approval pings, fleet-wide system events
