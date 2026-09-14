## Why

The deployed home-forge generation confirms that Beets keeps only its own retry/failure hooks and receives no generic notification-daemon lifecycle hooks, while OCI still evaluates phantom Beets service fragments from a stale host-maintained monitor list. Monitoring participation must follow the capability that owns each unit so moving a capability also moves its observability.

**Core Value:** A selected capability carries the monitoring behavior required to operate it, without host-maintained reverse indexes or phantom units.

## What Changes

- Replace the global list of service names with a typed additive per-unit monitoring contract.
- Make each capability contribute monitoring policy for units it owns; move Beets registrations to music and other existing registrations to their actual owners.
- Make the notification module generate hooks only for real systemd service definitions and fail closed when a contribution names no implemented service.
- Preserve feature-owned hooks such as `beets-inbox-retry.timer` and `beets-notify-failure@` while composing generic lifecycle hooks without overwriting existing definitions.
- Add evaluation tests proving home-forge monitors real Beets units and OCI contains no synthetic Beets fragments.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `apprise-notification-module`: Replace host-maintained service-name monitoring with typed feature-owned unit contributions and reject phantom services.
- `feature-topology`: Require runtime relationships such as monitoring participation to be contributed by the capability that owns the affected units.

## Impact

- Affects `modules/services/notification-daemon/default.nix`, music/Beets composition, operational aspects, host monitor lists, and Dendritic contract tests.
- No daemon HTTP API, routing backend, secrets, or deployed service names change.
- Uses the deployed baseline captured at `/tmp/home-forge-beets-monitor-baseline.txt`: `beets-inbox` has its feature-owned retry/failure `OnFailure`, its preprocess cleanup `ExecStartPost`, and an empty `ExecStopPost`.
- Must preserve two-step secret bootstrap and must not edit encrypted secrets.
