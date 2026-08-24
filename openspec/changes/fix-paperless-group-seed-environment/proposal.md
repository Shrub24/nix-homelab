## Why

After the flake update raised Paperless-ngx from 2.20.15 to 3.0.4, the custom OIDC group-seeding unit fails because its Django process does not receive `PAPERLESS_SECRET_KEY`. The release also changes duplicate handling from rejection by default to acceptance by default. This prevents otherwise valid host activations and silently changes future ingest behavior.

The core value is a reproducible, low-complexity host configuration whose activation succeeds after supported dependency updates.

## What Changes

- Make the custom `paperless-group-seed` unit consume the same sealed Paperless environment file as the upstream Paperless units.
- Preserve the v2 duplicate-rejection behavior explicitly.
- Add a focused evaluation check for the unit's secret-key environment binding.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `paperless-service`: custom Paperless Django maintenance units receive the sealed runtime environment required to start safely.

## Impact

- `modules/services/paperless/default.nix`
- `openspec/specs/paperless-service/spec.md`
- No secret contents, host bindings, or external interfaces change.
