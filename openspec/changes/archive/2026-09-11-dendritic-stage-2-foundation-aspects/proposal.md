## Why

Stage 1 proved the typed flake-parts registry in production, but every host still imports the same legacy profile bundle and repeats boot overrides, Tailscale secret registration, MTU tuning, and notification-daemon composition. Convert that fleet foundation into explicit Dendritic aspects, deleting compatibility glue rather than preserving accidental legacy boundaries.

**Core Value:** Make each host a small declaration of capabilities and genuine machine facts while keeping the evaluated fleet behavior, secret blast radius, and recovery posture unchanged.

## What Changes

- Publish explicit NixOS foundation aspects for base server policy, shell tooling, networking, Tailscale, and notifications; host selection of an aspect is its enablement.
- Decompose the legacy `base-server`, `fleet-standard`, and `networking` profile bundles instead of wrapping them as permanent aspects.
- Move Tailscale auth-key registration and its conventional host-scoped secret path into the Tailscale-owned module contract; remove the three host copies.
- Make the notification aspect own daemon availability so backup monitoring cannot depend on every host remembering a separate leaf import.
- Replace GRUB/systemd-boot and `/build` `mkForce` conflicts with explicit host facts consumed by the base aspect.
- Represent the proven Tailscale MTU workaround once through the Tailscale contract while preserving host-specific selection.
- Remove `core` and `profiles` from the temporary import-tree exclusion boundary once every file in those directories has been converted, relocating or deleting obsolete wrappers where that is simpler.
- Preserve all runtime services, users, firewall policy, secret paths/readership, deploy topology, and host outputs; classify any intentional architectural delta explicitly before implementation.
- Keep backups, builder access, Beszel, identity-client, admin/Cockpit, edge, and music conversion in subsequent focused changes.

Key constraints:

- Do not edit or decrypt encrypted secrets and do not change `.sops.yaml` readership.
- Do not reintroduce `specialArgs`, generic compatibility buses, hidden transitive aspect imports, or new `mkForce` workarounds.
- Preserve break-glass SSH, provider quirks, host storage, and deployment behavior.
- Validate all three architectures/configurations; architecture-specific builds remain on capable builders.

## Capabilities

### New Capabilities

None. This change restructures existing fleet behavior without introducing a new operator-facing capability.

### Modified Capabilities

- `fleet-infrastructure`: Fleet hosts select explicit foundation aspects and provide typed machine facts instead of importing legacy profile bundles.
- `repository-structure`: The `core` and `profiles` compatibility roots leave the temporary import-tree exclusion boundary after their contents become Dendritic contributors or are removed.
- `secrets-management`: Tailscale owns its host-scoped secret registration/default contract while recipient policy remains independent.
- `network-access`: Tailscale enablement and the proven per-host MTU setting become aspect-owned contracts without changing private-access behavior.
- `apprise-notification-module`: The notification aspect guarantees daemon/module composition for fleet consumers such as backup monitoring.

## Impact

- Primarily affects `modules/flake/`, `modules/core/`, `modules/profiles/`, `modules/services/tailscale.nix`, `modules/services/notification-daemon/`, and the three host assemblies.
- Updates the Dendritic scaffold contract, host/secret contract tests, and current architecture documentation.
- No new flake input, package dependency, service, secret, network exposure, or deployment target is introduced.
