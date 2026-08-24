# Tasks: post-migration-cleanup

## 1. Obvious cleanup

- [x] 1.1 Remove decommissioned-host leftovers and reconcile drifted docs.
  - refs: `hosts/la-admin-1/default.nix`, `secrets/.templates/services/ntfy.yaml`, `secrets/.templates/services/notification-daemon.yaml`, `STRUCTURE.md`, `docs/plan.md`
  - criteria: No live config or template references `do-admin-1`; STRUCTURE.md reflects the real repo name/host set; plan.md rollback language matches completed decommission.
  - verify: `rg do-admin-1` outside openspec/archive + docs history returns nothing actionable; `just checks all` green.
  - notes: Also reconciled canonical specs (edge-proxy-ingress soulsync examples removed, 9 specs' host assignments → la-admin-1), docs/architecture.md + decisions.md stale notes, phase-la-admin-contract publisher count 3→2. Dated ADRs (D-025/031/036/042) intentionally retain do-admin-1 as history.

## 2. SoulSync removal

- [x] 2.1 Remove SoulSync end-to-end and update docs/specs.
  - refs: `modules/services/music/soulsync.nix`, `modules/applications/music/default.nix`, `policy/web-services.nix`, `policy/oci-images.nix`, `opentofu/cloudflare/main.tf`, `secrets/.templates/applications/music.yaml`, `modules/services/music/slskd.nix`, `openspec/specs/soulsync-ingest/`, `docs/architecture.md`, `docs/runbooks/state-restore.md`
  - criteria: No module, option, route, image ref, cache rule, template entry, or doc mention remains; slskd consumes a neutral `slskd_api_key` secret name; generated web-policy JSON regenerated; operator steps recorded (ciphertext key prune/rename, tofu apply).
  - verify: `rg -i soulsync` returns only operator-follow-up notes; `just checks all`, treefmt, strict OpenSpec validation green; LA+OCI toplevels evaluate.
  - notes: Tofu cache-bypass var/output/README rows removed too. Operator must rename `soulsync_slskd_api_key` → `slskd/slskd_api_key` in encrypted music.yaml before next OCI deploy.

## 3. Unified bootstrap on oci-melb-1

- [x] 3.1 Replace legacy hardware-configuration with a committed nixos-facter report.
  - refs: `hosts/oci-melb-1/facter.json`, `hosts/oci-melb-1/default.nix`, `hosts/oci-melb-1/hardware-configuration.nix`
  - criteria: `hardware.facter.reportPath` set from an on-host captured report; guarded hardware-config import and file removed; disko filesystems and provider GRUB device untouched.
  - verify: OCI toplevel evaluates with facter-provided platform/kernel modules; `just checks all` green; deploy flagged for next regular rollout.
  - notes: Report captured live on-host (aarch64-linux); grub.devices [/dev/sda] intact; disko mounts intact; no eval conflicts.

## 4. Apprise disposition

- [x] 4.1 Record the provenance verdict for `modules/services/apprise.nix` and decide removal vs completion.
  - refs: `modules/services/apprise.nix`, git history, `docs/context-history.md`
  - criteria: Documented answer to "in-progress or superseded", recorded in this change; removal executed or explicitly kept with rationale.
  - verify: Decision noted in tasks.md notes; no code change without decision.
  - notes: Verdict SUPERSEDED-BY-NOTIFICATION-DAEMON — landed fea9635 (2026-05-13), deliberately replaced by notification-daemon in df40002 (2026-05-21), accidentally resurrected as dead code inside paperless commit 579a50c (2026-05-27); references nonexistent apprise-webhook package, zero importers. Removal is safe (pkgs.apprise package unaffected) but deferred pending user go-ahead.
