## 1. Create Phoenix NixOS module

- [x] 1.1 Create `modules/services/phoenix.nix` with module options (`enable`, `image`, `dataDir`, `port`, `grpcPort`, `extraEnv`)
- [x] 1.2 Define `services.phoenix.endpoint` read-only option with `grpc`, `grpcContainer`, and `http` sub-attributes (referencing existing bifrost-gateway pattern for host.containers.internal)
- [x] 1.3 Wire container deployment via `virtualisation.oci-containers.containers.phoenix` with `autoStart = true`, ports `6006:6006` and `4317:4317`, volume mount for `/srv/data/phoenix:/var/lib/phoenix`, and environment variables (`PHOENIX_WORKING_DIR`, `PHOENIX_GRPC_PORT`, `PHOENIX_PORT`, `PHOENIX_HOST`)
- [x] 1.4 Add `systemd.tmpfiles.rules` for the Phoenix data directory (`d /srv/data/phoenix 0755 root root`)
- [x] 1.5 Wire `systemd.services.podman-phoenix` with `wants`/`after` on `network-online.target` and `RequiresMountsFor` on data directory, mirroring bifrost-gateway pattern
- [x] 1.6 Register the module in the host's import chain — add `../../modules/services/phoenix.nix` to `hosts/oci-melb-1/default.nix` imports

## 2. Enable Phoenix on oci-melb-1

- [x] 2.1 Add `services.phoenix.enable = true` to `hosts/oci-melb-1/default.nix` alongside the existing `services.bifrost-gateway` block
- [x] 2.2 Verify ports 6006 and 4317 are not claimed by any other service on `oci-melb-1`

## 3. Add trace retention pruning

- [x] 3.1 Add a `systemd.services.phoenix-prune` oneshot service that prunes spans older than `retentionDays` using sqlite3, and rotates the DB file if it exceeds `pruneMaxDbSizeMb`
- [x] 3.2 Add a `systemd.timers.phoenix-prune` timer that fires monthly (`OnCalendar=monthly`) with a 6-hour randomized delay
- [x] 3.3 Add a `services.phoenix.retentionDays` option (default `90`) so the retention period is configurable
- [x] 3.4 Wire the prune service to depend on the Phoenix container being running (`after = ["podman-phoenix.service"]`)

## 4. Create test scripts and integration helpers

- [x] 4.1 Create `scripts/test-phoenix-trace.py` — a standalone Python script that:
  - Installs `openinference-instrumentation-openai`, `opentelemetry-exporter-otlp`, `openai` at runtime via pip
  - Configures OpenAIInstrumentor with OTLP gRPC exporter pointing at `localhost:4317`
  - Sends a dummy chat completion to Bifrost (`http://localhost:7411/v1`, model `shrublab-text`)
  - Prints a success message with a link to the Phoenix UI
- [x] 4.2 Verify Phoenix and Bifrost are running on deployed host (verified via smoke test + Gatus health checks)

## 5. Wire state-backups for Phoenix data

- [x] 5.1 Add `services.state-backups.services.phoenix` entry to the Phoenix module (referencing existing bifrost-gateway's state-backups pattern in `modules/services/bifrost-gateway.nix`)

## 6. Format and validate

- [x] 6.1 Run `nix fmt` on all changed `.nix` files
- [x] 6.2 Run `treefmt` on all changed files
- [~] 6.3 Run `nix flake check` to verify evaluation passes
- [x] 6.4 Verify module syntax parses cleanly (`nix-instantiate --parse`)

> **Note on 6.3:** `nix flake check` fails due to a pre-existing issue (untracked `modules/services/music/audiomuse.nix`), not related to this change. The Phoenix module itself parses and validates correctly.

## 7. Documentation

- [x] 7.1 Add a `docs/arize-phoenix.md` quick-start document covering:
  - How to access the Phoenix UI (Tailscale IP + port 6006)
  - How to run the test script
  - How to instrument a Python service with OpenInference
  - Manual cleanup instructions (`PHOENIX_WORKING_DIR/phoenix.db` truncation)
