## Context

See proposal.md — Why. The DO→LA migration is complete. `do-admin-1` has been decommissioned and its host/recipient removed, so the repo still carries dead references, disabled-service residue, and a legacy host-auth module no longer imported by any host. SoulSync was superseded by the beets inbox as the sole ingest path. `oci-melb-1` was bootstrapped with a legacy guarded `hardware-configuration.nix`, and `modules/services/apprise.nix` was left as dead code after notification-daemon superseded it. This change reconciles the tree with the deployed reality.

## Goals / Non-Goals

**Goals:**
- Remove every confirmed-dead reference (DO leftovers, SoulSync end-to-end, Apprise zombie) so the fleet description matches reality.
- Adopt the unified bootstrap flow on `oci-melb-1` (committed `nixos-facter` report over guarded legacy hardware config).
- Keep the `pkgs.apprise` package and its legitimate consumers (notification-daemon, beets) intact.

**Non-Goals:**
- No new architecture or service changes; this is removal-and-reconciliation only.
- No operator-owned secret actions (prune soulsync ciphertext keys, rename slskd key, re-encrypt) — recorded as follow-ups, not executed here.
- No deploy of any host as part of this change.

## Decisions

### D-1: Remove decommissioned-host leftovers and reconcile drifted docs

Delete `do-admin-1` references from live configs, secret templates, STRUCTURE.md, and docs/plan.md rollback language. Dated ADRs (D-025/031/036/042) intentionally retain `do-admin-1` as history. Canonical specs get host-assignment and publisher-count reconciliation to `la-admin-1`.

### D-2: Remove SoulSync end-to-end

Remove the module, application wiring, policy catalog route, OCI image reference, Cloudflare cache rule, secret template entries, slskd cross-service secret coupling, canonical `soulsync-ingest` spec, and doc mentions. slskd consumes a neutral `slskd_api_key` secret name. Beets inbox remains the sole ingest path; operator must prune/rename encrypted keys and apply tofu before the next deploy.

### D-3: Adopt the committed facter report on oci-melb-1

`hardware.facter.reportPath` points at a committed on-host-captured report; the guarded legacy `hardware-configuration.nix` import and file are removed. Disko keeps owning filesystems and the provider GRUB device stays explicit (`/dev/sda`). No eval conflicts observed.

### D-4: Remove the Apprise zombie module

`modules/services/apprise.nix` is dead code — it landed before notification-daemon superseded it, was accidentally resurrected inside an unrelated commit, references a nonexistent `apprise-webhook` package, and has zero importers. Verdict: SUPERSEDED-BY-NOTIFICATION-DAEMON. Remove the module, its obsolete `secrets/services/apprise.yaml` (encrypted) and template, and its `.sops.yaml` creation rule. The `pkgs.apprise` package and its notification-daemon/beets consumers are unaffected.

## Risks / Trade-offs

- [Secret-file deletion removes the apprise decryption scope] → `.sops.yaml` rule and `secrets/services/apprise.yaml` are removed together; no remaining consumer references `services.apprise` or the apprise secret path.
- [SoulSync ciphertext keys linger in encrypted files] → Operator follow-up: prune from `secrets/applications/music.yaml`, rename `soulsync_slskd_api_key` → `slskd/slskd_api_key` during next re-encryption, then `just tofu plan && apply`.
- [Facter report on the wrong platform/kernel modules breaks OCI eval] → Report was captured live on-host (aarch64-linux); eval verified no conflicts with disko mounts or GRUB device.
