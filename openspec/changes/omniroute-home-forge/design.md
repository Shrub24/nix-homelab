# Design: omniroute-home-forge

## Context

`home-forge` is a landed x86_64 fleet node (32 GB RAM, NVMe root + HDD `/srv/storage`, br0 LAN, Tailscale via base-server, deploy-rs node outside the serial chain). The repo already runs OCI workloads through `virtualisation.oci-containers` with image refs pinned in `policy/oci-images.nix` (Renovate-managed) and consumed via the `ociImages` specialArg — `modules/services/bifrost-gateway.nix` and `modules/services/karakeep.nix` are the structural precedents. See proposal.md for motivation.

Upstream distribution research (docs-mcp index of `diegosouzapw/OmniRoute` @ release/v3.8.51): the docker-compose **base profile** is the first-class server shape (app + always-on redis sidecar); the npm tarball path carries unverified native-addon risk and a CLI-first orientation this deployment does not need; the Traffic Inspector/AgentBridge MITM stack is host-local by design and stubbed under Docker (#3390); tunnel backends are managed in-process from the dashboard.

## Goals / Non-Goals

**Goals:**
- Thin declarative core: image pin, leaf service module, secrets contract, backup contract — nothing more.
- Faithful translation of the upstream compose base profile into `virtualisation.oci-containers`.
- Private reachability over LAN ethernet and tailnet with zero public surface.
- Runtime configuration (providers, OAuth connections, routing, tunnels) stays imperative, owned by the dashboard/CLI, persistent across redeploys.

**Non-Goals:**
- No OIDC dashboard login (password login bootstrapped from `INITIAL_PASSWORD`).
- No `web-services.nix` entry, edge route, or Cloudflare exposure.
- No provider wiring to bifrost/litellm endpoints.
- No Tailscale Funnel tunnel backend (not viable in-container; public exposure by definition).
- No workstation-side integration work in this repo (opencode/pi/hermes setup happens on the workstation via remote mode).

## Decisions

### D1: OCI digest pin, not npm-tarball derivation
Add `omniroute = "ghcr.io/shrub24/omniroute:edge@sha256:<digest>"` to `policy/oci-images.nix`. The maintained edge image carries the runtime fixes required by this deployment. Digest pins give immutable refs and Renovate bump PRs; skip-a-version is tolerated by not merging a bump.

### D2: Compose base-profile translation with redis sidecar
Two `virtualisation.oci-containers.containers` entries: `omniroute` and `omniroute-redis` (repo's existing `redis7Alpine` pin). The app reaches redis at `redis://omniroute-redis:6379` via container-name DNS — the established pattern (`karakeep.nix`: `MEILI_ADDR = "http://karakeep-meilisearch:7700"`). Redis publishes no host port (compose binds it to loopback only for host tooling; we need none). Upstream marks Redis as recommended (rate limiter degrades to in-memory fallback without it), so the sidecar ships in the thin core.

### D3: Leaf service module modeled on bifrost-gateway, minus config rendering
`modules/services/omniroute.nix` with `enable`/`image`/`dataDir`/`port` options and a `secretFiles.host` contract via `lib/secrets.nix`. Unlike bifrost there is no `configFile` option and no render oneshot: OmniRoute owns its config imperatively in `DATA_DIR`. Tmpfiles create the data directory for the image's UID 1000 (`node`); `restartTriggers` include the sops environment file.

### D4: Secrets via sops template → environmentFiles
`sops.templates."omniroute.environment"` renders `JWT_SECRET`, `API_KEY_SECRET`, `STORAGE_ENCRYPTION_KEY`, `INITIAL_PASSWORD`, and `OMNIROUTE_WS_BRIDGE_SECRET` into the container's `environmentFiles`. `STORAGE_ENCRYPTION_KEY` enables upstream's SQLite encryption-at-rest path and must remain stable after encrypted credentials exist; it is generated separately for the server and never copied from the workstation's `~/.omniroute/.env`. The required-secret assertion follows `mkRequiredSecretAssertion`.

### D5: Plain-HTTP private posture
Bind `0.0.0.0:20128` (bifrost pattern) — serves LAN ethernet and tailnet simultaneously; no funnel, no reverse proxy. `AUTH_COOKIE_SECURE=false` is set explicitly because upstream auto-enables secure cookies off-localhost, which silently breaks dashboard login over plain HTTP on the private network. `OMNIROUTE_SERVER_HOST=0.0.0.0` (never `HOSTNAME`, upstream #6194).

### D6: Remote OAuth flows ride upstream-native paths, no Nix surface
Ranked for this fleet: (1) workstation remote-mode helper — `omniroute connect home-forge`, then `npx omniroute login <provider>` completes OAuth locally and pushes the credential (upstream's recommended Option A; no tunnel); (2) SSH `-L` forwards over Tailscale for fixed-loopback providers (codex `1455`, xai `56121`, grok `56122` plus the dashboard port); (3) in-dashboard Cloudflare Quick Tunnel for providers requiring a public HTTPS redirect — works in-container (managed cloudflared, HTTP/2 transport). Tailscale Funnel is excluded: the in-process backend drives the system `tailscale` CLI/`tailscaled` via sudo, which the container does not have, and Funnel is public-internet exposure against the fleet baseline.

### D7: Runtime sizing per upstream guidance
`OMNIROUTE_MEMORY_MB=8192` (upstream: coding agents need 8192+; image default 1024 is for toy loads; home-forge has 32 GB). Stop grace 40 s via `extraOptions = [ "--stop-timeout=40" ]` so the SQLite WAL checkpoint completes (compose files set the same). Single instance only — SQLite is single-replica; scale-out is an upstream-documented multi-container pattern deferred until needed.

## Risks / Trade-offs

- [Weekly release cadence with occasional broken releases] → digest pins + opt-in Renovate merges; a bad release is skipped by not merging.
- [Upstream image regression (e.g. #11835 node-version mismatch)] → validate `/healthz` after each merged bump before restarting long sessions; rollback is the previous generation.
- [V8 heap abort on very large concurrent agent requests (#7849)] → 8192 MB ceiling plus upstream's auto-sized admission budget; single-instance posture keeps concurrent large jobs within `N × 2`.
- [Plain HTTP on LAN/tailnet] → accepted for a private, single-user network; no secrets beyond the bootstrap set transit the dashboard; provider credentials are stored encrypted at rest by the app.
- [Redis sidecar adds a second unit to operate] → compose-native, image already pinned in-repo, no host exposure; removing it later is a one-container deletion.

## Migration Plan

1. Land module + host wiring with the image pin and the user-created encrypted `secrets/services/omniroute.yaml`; never decrypt or modify its ciphertext.
2. `just deploy home-forge`; containers start; dashboard bootstrap with `INITIAL_PASSWORD` at `http://home-forge:20128` (LAN or MagicDNS).
3. Workstation: `npm i -g omniroute && omniroute connect home-forge`; configure opencode/pi/hermes against the remote catalog.
4. Rollback: flip `services.omniroute.enable = false` (or revert the generation); data directory persists for re-enable.

## Open Questions

- None blocking. The deployment uses the digest-pinned maintained edge image; Chromium variants remain out of scope because this deployment does not use web-session providers.
