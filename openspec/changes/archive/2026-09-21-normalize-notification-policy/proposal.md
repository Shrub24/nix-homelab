## Why

The host running ntfy currently owns a hand-maintained list of fleet publishers, even though publisher identity is fleet policy rather than an LA machine fact. Notification routing should have one policy owner and an interface that can later move to `nix-fleet` without moving homelab-specific topics, recipients, or secrets prematurely.

**Core Value:** Notification infrastructure is reusable, while publisher authorization and routing remain explicit, testable homelab policy keyed by canonical host identities.

## What Changes

- Add a canonical typed notification publisher policy keyed by canonical host IDs and consumed by the `push-server` aspect.
- Derive ntfy ACL subjects from publisher policy instead of maintaining a host-local reverse list.
- Validate publisher policy, committed secret-template placeholders, and host publish-token contracts against each other without deriving or editing encrypted values.
- Keep daemon/CLI/systemd-hook mechanics separate from homelab routing policy so the generic component is ready for later `nix-fleet` extraction.
- Preserve current publisher access and notification delivery behavior.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `notification-policy-defaults`: Add canonical publisher identity and authorization policy alongside routing defaults.
- `apprise-notification-module`: Separate generic notification mechanics from fleet-specific publisher/routing policy.
- `internal-service-auth`: Require ntfy publisher authorization to derive from typed publisher identities and explicit secret contracts.

## Impact

- Affects notification policy, `modules/services/ntfy.nix`, the push-server contributor, host-local ACL configuration, templates, secret-scope tests, and docs.
- Depends on canonical host identity from Stage 8; it must not introduce a competing host registry.
- No secret values, ciphertext, or `.sops.yaml` readership are generated or changed automatically.
