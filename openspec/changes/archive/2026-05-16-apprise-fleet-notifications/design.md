## Context

The migration from ntfy.sh to apprise (commit `cabe529`) established the notification infrastructure: a service module writing a JSON config, a CLI wrapper (`apprise-notify`), and tier-based Telegram routing. What remains is the design for wiring all notification consumers into this infrastructure.

Current state (post-migration):

- **Infrastructure:** `modules/services/apprise.nix` owns all internals. `/etc/apprise/notify.json` defines `token_file`, `chat_id`, and `topics`. `apprise-notify <tier> <title>` is the sole consumer contract. SOPS manages the Telegram bot token via `secrets/services/apprise.yaml` → `/run/secrets/apprise/telegram_bot_token` (`0440 root:apprise`).
- **Tiers configured:** `critical`, `warning`, `info`, `music`, `system` — each maps to a distinct topic ID within one Telegram supergroup.
- **Beets (done):** Notification script migrated. Calls `apprise-notify music "Beets runner beets-$runner failed"` with journalctl output on stdin.
- **Users:** `dev` and `beets` users are in the `apprise` group for secret read access.

Remaining consumers:

- **Gatus:** Endpoint health monitoring. Needs notification on status changes (degraded → critical → recovered).
- **Beszel:** System metrics (disk pressure, OOM). Needs notification on threshold breaches.
- **Beets duplicates:** Inbox duplicate detection run. Needs notification when duplicates found requiring manual approval.
- **Fleet-wide system events:** Deploy failures, systemd unit failures. Tier routing: warning/critical.

## Goals / Non-Goals

**Goals:**

- Provide a single HTTP endpoint (`127.0.0.1:5555/notify`) for all programmatic consumers (Beszel, Gatus, external tools)
- Provide a thin CLI wrapper (`apprise-notify`) for systemd hooks, deploy-rs, and SSH sessions
- Keep each consumer's notification logic self-contained in its module (no shared notification helper module)
- Use the `feature-topology` pattern: consumers own "when to notify" decisions; apprise module owns "how to route"
- Replace webhook middleman and bash CLI with a single FastAPI daemon calling apprise Python API directly

**Non-Goals:**

- Multi-backend routing (Discord, Slack, etc.) — Telegram-only for initial baseline
- Notification templating or formatting engine — each consumer constructs its own message body
- ntfy.sh reinstatement — removed and not coming back
- HTTP ingress beyond loopback — all traffic bound to `127.0.0.1:5555`

## Decisions

### D1: FastAPI daemon replaces webhook middleman + bash CLI

The first iteration used two independent paths: a bash CLI (`apprise-notify`) using `jq` for JSON parsing, and an adnanh/webhook hook that called the CLI. This forked two processes per notification (webhook → shell), split configuration across two Nix files, and had no structured error handling.

**Decision:** A single FastAPI daemon calling apprise's Python library directly replaces both. It serves `POST /notify` for all HTTP consumers and exposes structured JSON errors. The CLI becomes a thin HTTP POST wrapper (~5-10 lines). Benefits:

- Zero forks per notification (apprise runs in-process)
- Structured error responses (not exit codes)
- Single binary/deployment unit (one flake package, one NixOS module)
- Easy to extend with rate limiting, dedup, logging
- Apprise Python API is more feature-rich than apprise CLI

**Alternatives considered:**
- Go binary: Rejected — more boilerplate for HTTP + notification routing; Python has apprise directly available
- Keep adnanh/webhook + bash CLI: Rejected — two-process fork per request, no structured errors, harder to extend

### D2: Thin CLI wrapper POSTs to daemon

The systemd.monitor service and deploy-rs hooks call `apprise-notify` directly. Rather than maintaining a standalone bash CLI with `jq` for JSON parsing, the CLI becomes a thin wrapper that POSTs to the daemon.

**Decision:** `apprise-notify` is a ~10-line shell script (or Python one-liner via `/etc/apprise/bin/apprise-notify`) that sends `{"tier":"...", "title":"...", "type":"...", "message":"..."}` to `http://127.0.0.1:5555/notify`. This eliminates the `jq` dependency entirely.

```
CLI call:      apprise-notify info "Deploy succeeded" deploy
               │
               ▼
Shell script:  POST http://127.0.0.1:5555/notify
               {"tier":"info","title":"Deploy succeeded","type":"deploy","message":""}
               │
               ▼
FastAPI daemon: POST /notify
               reads /etc/apprise/notify.json
               calls apprise.Apprise() in-process
               returns 200/500
```

**Alternatives considered:**
- Keep standalone bash CLI with jq: Rejected — ~25 lines of shell with fragile JSON parsing, extra dep
- Python CLI script reading config directly: Rejected — duplicates config-reading logic, diverges from daemon

### D3: JSON config over environment variables

The first iteration embedded URL construction in Nix. This was fragile (nested quoting) and opaque (generated commands invisible in deployed system).

**Decision** (unchanged from first iteration): `/etc/apprise/notify.json` contains `token_file`, `chat_id`, and `topics`. The CLI reads it at runtime. Nix writes it with `builtins.toJSON` — zero escaping risk.

**Alternatives considered:**
- Environment variables per tier (`APPRISE_TOPIC_CRITICAL=...`): Rejected — unbounded variable count, harder to validate
- YAML config (`builtins.toJSON` equivalent): Rejected — requires `yq` instead of `jq`, same dep weight

### D4: Dedicated `apprise` group for secret read

The Telegram bot token must be readable by notification consumers (beets service user, dev user for testing).

**Decision** (unchanged): `users.groups.apprise = {}`, secret mode `0440 root:apprise`. Both `beets` and `dev` users added to the group via their respective `extraGroups`.

**Alternatives considered:**
- World-readable secret (`0444`): Rejected — unnecessary exposure even on homelab
- `sudo` wrapper: Rejected — adds friction for manual testing, doesn't work for systemd units started as non-root

### D5: Tier-based routing via Telegram topics

All notifications go to one Telegram supergroup, with different topics per tier.

**Decision** (unchanged): `policy/globals.nix` defines `chatId` (the supergroup) and `topics` (tier → topic ID map). Apprise URLs use the format `tgram://token/chatId:topicId`.

**Alternatives considered:**
- Separate chat IDs per tier: Rejected — Telegram only allows one supergroup per bot; separate chats would need multiple group invites
- Apprise tags (`#critical`, `#warning`): Rejected — Telegram topics provide cleaner separation and per-topic notification settings for users

### D6: HTTP on loopback, no authentication

The daemon only listens on `127.0.0.1:5555`, reachable only from the local host. All consumers (Beszel, Gatus, CLI wrapper) are local.

**Decision:** No authentication on the `/notify` endpoint. Attack surface is bounded by the loopback interface and Tailscale-only networking model.

**Alternatives considered:**
- Shared secret header: Rejected — unnecessary on loopback with private networking
- mTLS: Over-engineered for a homelab notification daemon

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      NOTIFICATION FLOW                      │
└─────────────────────────────────────────────────────────────┘

  Beszel alert ──┐
  Gatus alert  ──┤
  curl / CLI   ──┤
                  │  POST /notify
                  ▼
       ┌─────────────────────┐
       │   apprise-webhook   │  ← FastAPI, port 5555
       │   (Python daemon)   │
       │                     │
       │  reads JSON config  │
       │  calls apprise API  │
       └─────────┬───────────┘
                 │
                 ▼
       ┌─────────────────────┐
       │   Telegram API      │
       │   (supergroup +     │
       │    per-tier topics) │
       └─────────────────────┘

  systemd.monitor ──┐
  deploy-rs       ──┤
  SSH session    ──┤
                    │  apprise-notify warning "X failed"
                    ▼
       ┌─────────────────────┐
       │  CLI wrapper        │  ← thin shell script
       │  POSTs to daemon    │
       └─────────┬───────────┘
                 │
                 ▼
       ┌─────────────────────┐
       │   apprise-webhook   │
       │   (same as above)   │
       └─────────────────────┘
```

## Risks / Trade-offs

- **[R1] FastAPI + uvicorn adds Python ASGI overhead (~30MB)** → Acceptable; Python is already in the closure via apprise
- **[R2] Daemon crash kills all notifications** → systemd auto-restart mitigates; CLI wrapper fails fast with connection refused
- **[R3] Bot token revocation kills all notifications** → Single point of failure. Mitigation: no mitigation needed for homelab; token rotation is manual via sops
- **[R4] New tier needs code change (policy/globals.nix)** → Acceptable; tier additions should be explicit and reviewed, not ad-hoc
- **[R5] Daemon startup race with secret availability** → systemd dependency ordering: `apprise-webhook.service` `After=sops-nix.service`, `Requires=sops-nix.service`

## Remaining Consumer Wiring

| Consumer               | Tier       | Trigger                          | Method              | Status   |
| ---------------------- | ---------- | -------------------------------- | ------------------- | -------- |
| Beets runner failure   | `music`    | systemd OnFailure= + monitor     | CLI `apprise-notify` | ✅ Done |
| Gatus status alerts    | `warning`  | Gatus alerting config            | POST /notify        | ⬜ Pending |
| Beets duplicates found | `info`     | Duplicate runner exit check      | CLI `apprise-notify` | ✅ Done |
| Disk pressure          | `critical` | Beszel alert                     | POST /notify        | ⬜ Pending |
| OOM events             | `critical` | Beszel alert                     | POST /notify        | ⬜ Pending |
| Deploy failures        | `warning`  | deploy-rs post-deploy hook       | CLI `apprise-notify` | ✅ Done |
| Unit failures          | `warning`  | systemd.monitor module           | CLI `apprise-notify` | ✅ Done |
