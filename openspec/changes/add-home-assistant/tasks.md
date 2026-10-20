# Tasks

## 1. Pin the image and declare the placement

- [x] 1.1 Verify the `ghcr.io/home-assistant/home-assistant:2026.10.1` image index covers `linux/amd64` and `linux/arm64`, and record the tag plus index digest in `policy/oci-images.nix`.
- [x] 1.2 Add the `home-assistant` aspect under `modules/apps/` with `services.hass` options (image, data directory, port, timezone), host networking, the `/config` mount and the `0700` state directory.
- [x] 1.3 Assert that the canonical route exists and that its origin port matches the listener, so the policy and the service cannot drift.
- [x] 1.4 Select the aspect on `home-forge` only.

## 2. Route, notification and backup contracts

- [x] 2.1 Declare the `hass.shrublab.xyz` route in `policy/web-services.nix` with `exposureMode = "tailscale-upstream"`, `publish = false`, Cloudflare Access enabled and application OIDC off.
- [x] 2.2 Register the container with `services.notify.events` for failure.
- [x] 2.3 Register export-first backup: SQLite online backup for the recorder database, raw copy of the directory, and the database plus WAL sidecars excluded from that copy.
- [x] 2.4 Add `tests/check-home-assistant-contract.sh` covering the container shape, the withheld route, the port agreement and the backup exclusions, and wire it into `just checks all`.
- [x] 2.5 Update the scaffold contract's pins for the extra container and the extra notify registration on `home-forge`.

## 3. Documentation

- [x] 3.1 Add `docs/runbooks/home-assistant.md`: tailnet access before release, onboarding, the port constraint, adding a radio later, the release steps including `trusted_proxies`, backup/restore, and updates.
- [x] 3.2 Record the decision as D-100 and update the architecture and structure documents.

## 4. Deploy and accept

- [ ] 4.1 Deploy `home-forge` and confirm the container is active, the state directory is created `0700`, and `http://home-forge.tail0fe19b.ts.net:8123` answers.
- [ ] 4.2 Onboard the owner account and confirm the instance is usable over the tailnet.
- [ ] 4.3 Release the route: set `publish = true`, add `use_x_forwarded_for` and the pinned `trusted_proxies` entry to `configuration.yaml`, deploy, and confirm `https://hass.shrublab.xyz` reaches the instance through the edge.
- [ ] 4.4 Confirm the first backup run captured the exported database and that a restore of `.storage` plus the export loads the instance with its integrations intact.
