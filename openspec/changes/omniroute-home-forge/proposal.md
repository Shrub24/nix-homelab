# Proposal: omniroute-home-forge

## Why

Coding agents on the workstation (opencode, pi, hermes) need a shared, always-on LLM router with provider OAuth subscriptions, usage tracking, and a dashboard. OmniRoute on `home-forge` provides that routing plane over LAN/Tailscale with no public exposure. The declarative surface stays thin — package pin, service module, secrets — while runtime configuration (providers, routing, tunnels) remains imperative state owned by the dashboard/CLI, matching the intended operating model.

## What Changes

- Add an `omniroute` image ref (`registry/repo:tag@sha256:digest`) to `policy/oci-images.nix`, Renovate-managed like the other OCI refs.
- New leaf service module `modules/services/omniroute.nix` exposing `services.omniroute.enable` with `image`, `dataDir`, `port` options. It translates the upstream docker-compose **base profile** to `virtualisation.oci-containers`: the omniroute container plus the redis sidecar (rate limiter backend; compose defines it always-on), container-name DNS between them, 40s stop grace for the SQLite WAL checkpoint, and a sops environment template (`JWT_SECRET`, `API_KEY_SECRET`, `STORAGE_ENCRYPTION_KEY`, `INITIAL_PASSWORD`, `OMNIROUTE_WS_BRIDGE_SECRET`).
- Enable `services.omniroute` on `hosts/home-forge/default.nix` with state under `/srv/data/omniroute`, bound to `0.0.0.0:20128` (LAN ethernet + tailnet via MagicDNS).
- Add secret template `secrets/.templates/services/omniroute.yaml` and a home-forge-scoped path rule in `.sops.yaml`; include the user-created encrypted `secrets/services/omniroute.yaml` without decrypting or modifying it.
- Add the state-backups contract for the data directory (logs excluded).
- Explicitly out of scope: OIDC dashboard login, public ingress / `web-services.nix` entry, provider wiring to bifrost/litellm, Tailscale Funnel tunnel backend (not viable in-container and public by definition). Provider OAuth connections, Cloudflare Quick Tunnel, traffic inspector, and workstation CLI integrations (opencode/pi/hermes via remote mode) are dashboard/CLI-managed imperative state and require no Nix surface.

## Capabilities

### New Capabilities

- `omniroute-service`: OmniRoute LLM router on `home-forge` — container topology (app + redis sidecar), secrets contract, private tailnet-only access posture, memory/stop-grace runtime requirements, and backup contract.

### Modified Capabilities

- None. The existing `feature-topology` singleton-leaf requirement (standalone workload enabled through a canonical `services.<name>.enable` entrypoint) and `network-access` private-first baseline already cover this change's shape; no requirement-level behavior changes there.

## Impact

- **Files:** `policy/oci-images.nix`, `modules/services/omniroute.nix` (new), `hosts/home-forge/default.nix`, `.sops.yaml`, `secrets/.templates/services/omniroute.yaml` (new); user-created `secrets/services/omniroute.yaml`.
- **Runtime:** two podman containers on `home-forge` (`omniroute`, `omniroute-redis`); port 20128 reachable over LAN and tailnet only.
- **Workstation-side (outside this repo):** `omniroute` CLI remote-mode connect, `setup-opencode`/pi/hermes configuration, optional local traffic-inspector usage.
- **Constraints:** Tailscale/LAN-only access; no OIDC; password dashboard login bootstrapped from `INITIAL_PASSWORD`; config/state mutable under `DATA_DIR` and owned by the app; thin core first with more features enabled later from the dashboard.
