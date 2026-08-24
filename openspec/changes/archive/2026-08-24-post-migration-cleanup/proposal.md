# Proposal: post-migration-cleanup

## Why

The DO→LA migration left disabled services, stale references, and legacy host plumbing behind. This change removes what is confirmed dead so the fleet description matches reality before the next structural round (edge move, dendritic refactor, new hosts).

## What Changes

- Remove SoulSync end-to-end: module, application wiring, policy catalog route, OCI image reference, Cloudflare cache rule, secret template entries, slskd cross-service secret coupling, canonical spec, and doc mentions.
- Remove decommissioned-host leftovers: do-admin-1 ntfy ACL subject, ntfy/notification-daemon secret-template placeholders, doc drift (STRUCTURE.md, docs/plan.md).
- Adopt the unified bootstrap flow on oci-melb-1: committed `nixos-facter` report replaces the guarded legacy `hardware-configuration.nix`; disko keeps owning filesystems; provider GRUB device stays explicit.
- Trace the provenance of `modules/services/apprise.nix` (in-progress vs superseded) before deciding its removal.

## Capabilities

### Removed
- `soulsync-ingest`: SoulSync control-plane ingest is fully removed; beets inbox remains the sole ingest path.

## Impact

- Affected specs: `soulsync-ingest` (REMOVED — canonical spec deleted in task 2.1; no archive delta remains)
- Affected code: `modules/services/music/`, `modules/applications/music/`, `policy/`, `opentofu/cloudflare/`, `secrets/.templates/`, `hosts/oci-melb-1/`, `tests/`
- Operator follow-ups (out of scope here): prune soulsync keys from encrypted `secrets/applications/music.yaml`, rename the slskd API-key entry during next re-encryption, `just tofu plan && apply` after route removal, deploy both hosts.
