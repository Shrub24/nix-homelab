# Proposal

## Why

`home-forge` runs the household's media, knowledge and observability workloads, but nothing on the fleet automates the house itself. Home Assistant is the natural home-automation hub, and it belongs on `home-forge` beside the rest of the home workloads.

**Core Value:** Run Home Assistant the way its own project supports it — the container image — without turning the fleet's Nix configuration into a copy of Home Assistant's imperative state, and without exposing a home-control surface before it has been accepted.

## What Changes

- Add a `home-assistant` aspect under `modules/apps/` and select it on `home-forge`.
- Pin `ghcr.io/home-assistant/home-assistant` by tag and digest in `policy/oci-images.nix`; run it as a container that **shares the host network namespace**, so discovery integrations (HomeKit, Chromecast, Hue, Matter, ESPHome) work, and publishes no port.
- Keep `/srv/data/home-assistant` operator-owned: Home Assistant creates its own minimal `configuration.yaml`, and Nix creates only the directory (mode `0700`, since `.storage` holds every integration credential).
- Declare the `hass.shrublab.xyz` route through canonical web policy with `publicReady = false`, so the edge serves nothing until onboarding is accepted; reach the instance on the tailnet at the provider's port in the meantime.
- Register the recorder database for export-first backup: SQLite's online backup API for history, a raw copy of the rest of the directory, and the database plus its WAL sidecars excluded from that copy.
- Register the container with `services.notify.events` so a crash loop reaches the notifier.
- Add a placement contract check, an operator runbook, and the decision record.

## Capabilities

### New Capabilities
- `home-assistant-service`: the Home Assistant deployment contract — host-networked container, operator-owned state directory, withheld route with a single-field release, and export-first recorder backup.

### Modified Capabilities
None. `policy-service-catalog`, `edge-proxy-ingress` and `state-backups` already define the generic routing, exposure and recovery contracts this placement uses.

## Impact

- `modules/apps/home-assistant.nix` (new aspect), `modules/hosts/home-forge/` (aspect selection), `policy/oci-images.nix` (image pin), `policy/web-services.nix` (route).
- `tests/check-home-assistant-contract.sh` plus the scaffold pins it changes (one more container and one more notify registration on `home-forge`), `.just/checks.just`, `docs/runbooks/home-assistant.md`, `docs/decisions.md` (D-100), and the architecture/structure documents.
- Upstream: `ghcr.io/home-assistant/home-assistant`, Apache-2.0, release `2026.10.1` (multi-arch index covering `linux/amd64` and `linux/arm64`). Home Assistant Container supports no apps/add-ons; anything add-on-shaped has to be a fleet service of its own.
