## 1. Notification Infrastructure

- [x] 1.1 Create `modules/services/apprise.nix` with JSON config generation and CLI wrapper
- [x] 1.2 Add notification defaults to `policy/globals.nix` (chatId + tier→topic mapping)
- [x] 1.3 Add `secrets/.templates/services/apprise.yaml` template and `.sops.yaml` rule
- [x] 1.4 Create `apprise` system group and set secret permissions (`0440 root:apprise`)
- [x] 1.5 Wire `services.apprise` into `hosts/oci-melb-1/default.nix`
- [x] 1.6 Wire `services.apprise` into `hosts/do-admin-1/default.nix`
- [x] 1.7 Add `dev` user to `apprise` group in `modules/core/users.nix`
- [x] 1.8 Verify `nix flake check` passes and `apprise-notify` CLI is on PATH

## 2. Beets Migration (ntfy.sh → apprise)

- [x] 2.1 Replace ntfy options with single `tier` option in `modules/services/beets/default.nix`
- [x] 2.2 Rewrite `beets-notify-failure` script to use `apprise-notify` CLI
- [x] 2.3 Remove ntfy wiring from `modules/applications/music.nix`
- [x] 2.4 Add `beets` user to `apprise` group
- [-] 2.5 Remove `secrets/services/firebase-key.json` and ntfy Firebase wiring (skipped — still in use by admin service)
- [x] 2.6 Remove ntfy_token from `secrets/applications/music.yaml`
- [x] 2.7 Verify `beets.notify = { enable = true; tier = "music"; }` evaluates correctly

## 3. Secrets Bootstrap

- [ ] 3.1 Create encrypted `secrets/services/apprise.yaml` with `telegram_bot_token: "<bot_token>"` (user action with sops)
- [x] 3.2 Create Telegram supergroup, capture chat ID, and update `policy/globals.nix` (chatId=-3913476155 set)
- [x] 3.3 Create Telegram topics within supergroup and update topic IDs in `policy/globals.nix` (all 4 topics set)
- [ ] 3.4 Verify `apprise-notify info "test"` delivers to correct Telegram topic

## 4. Gatus Alert Wiring

- [x] 4.1 Configure Gatus alerting to POST to daemon `/notify` endpoint on status changes
- [ ] 4.2 Verify degraded→critical→recovered transitions produce notifications
- [ ] 4.3 Test recovery notification (gatus should notify on both failure and recovery)

## 5. Beets Duplicate Approval Notification

- [x] 5.1 Wire `beets-duplicates` runner to call `apprise-notify info` when duplicates found
- [x] 5.2 Include duplicate count and file list in notification body
- [x] 5.3 Only notify when NEW duplicates are found (not on every scan)

## 6. Fleet-Wide System Event Notifications

- [x] 6.1 Add `system` tier to `policy/globals.nix` if separate from `warning` (see O3)
- [x] 6.2 Wire disk pressure events → Beszel → daemon `POST /notify`
- [x] 6.3 Wire OOM killer events → Beszel → daemon `POST /notify`
- [x] 6.4 Wire deploy-rs post-deploy failures to `apprise-notify warning`
- [x] 6.5 Wire systemd.monitor module (onStart/onFailure/onSuccess hooks per service)
- [ ] 6.6 Verify each event type produces a notification with actionable context

## 7. FastAPI Daemon Implementation

- [x] 7.1 Create `apprise-webhook/` FastAPI application with `POST /notify` and `GET /health`
- [x] 7.2 Package app in flake as `pkgs.apprise-webhook` via `buildPythonApplication`
- [x] 7.3 Add `services.apprise.daemon` option to `apprise.nix` enabling the systemd service
- [x] 7.4 Write thin `apprise-notify` CLI wrapper that POSTs to daemon (replaces bash+jq version)
- [x] 7.5 Wire daemon systemd service with dependency ordering (After=sops-nix.service)
- [x] 7.6 Update Gatus alerting config to POST directly to daemon (remove webhook dependency)
- [x] 7.7 Update Beszel Shoutrrr URL to point to daemon (remove webhook dependency)
- [x] 7.8 Remove notify hook from `modules/services/admin/webhook.nix`

## 8. Cleanup & Verification

- [ ] 8.1 Remove `pkgs.jq` from system closure if no other consumers remain
- [ ] 8.2 Verify daemon starts, accepts POST, and dispatches via Telegram
- [ ] 8.3 Verify `apprise-notify` CLI wrapper works from all `apprise` group users
- [ ] 8.4 Verify Beszel alerts route through daemon (disk pressure, OOM)
- [ ] 8.5 Verify Gatus alerts route through daemon (degraded/recovery transitions)
- [ ] 8.6 Verify systemd.monitor hook notifications route via CLI wrapper → daemon
- [ ] 8.7 Verify deploy-rs post-deploy hook notifications route via CLI wrapper → daemon
