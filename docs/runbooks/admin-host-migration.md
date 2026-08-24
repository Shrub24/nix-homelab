# LA Admin Host Migration Runbook

LA-specific transfer facts for replacing the retired `do-admin-1` host with `la-admin-1`. Generic host bring-up, fact capture, key derivation, and first-boot steps live in [host-initialization.md](./host-initialization.md); this runbook references it and records only LA transfer details.

> **Status: COMPLETE.** The migration to `la-admin-1` has been cut over and the DigitalOcean host `do-admin-1` is decommissioned and removed from the repository. The steps below are retained for reference and rollback understanding; they are no longer a live migration procedure.

## LA host facts (recorded, do not re-discover)

| Fact | Value |
|---|---|
| Host identity | `la-admin-1` (permanent; no staged rename) |
| Provider shape | LA VPS, KVM, 2 vCPU / 4 GiB, x86_64 |
| Public bootstrap address | `216.75.75.168` |
| Guest network | DHCP/NAT guest on `ens18`, observed `100.114.1.124` |
| Root filesystem | ext4 root, UUID `44effe1c-64cf-4a8f-9e36-6e5378199f5a`; `/srv/data` lives on root (no separate data mount) |
| ESP | `1EDE-F013`, preserved UEFI `systemd-boot`; no NVRAM boot-entry writes |
| Verified host fingerprint | `SHA256:g71ri368dh+EkeJgXrHmMsrxlkwHI2T9G8rFD+G6fWw` |
| Initial password-sudo account | `root` |

Provider console is verified to perform and observe a reboot; keep a console session open through the first switch.

## Roles and boundaries

- `la-admin-1` is the active admin, edge, and Kanidm/OIDC host. The former DigitalOcean rollback source `do-admin-1` has been decommissioned.
- This is LA **adoption** of a preinstalled NixOS system, separate from later AU edge and US-East workload work.
- Cross-host consumers read stable service IDs from the policy catalog (`config.repo.web.catalog`); physical deployment facts (`edgeHost`, `deployOrder`) stay only in `lib/deploy/hosts.nix`.
- Open WebUI deployment is deferred until this migration's cutover and backup gates pass.

## Operator-owned encrypted-secret actions

The operator — never the agent — performs these, in order:

1. Verify the host fingerprint (above) before deriving the `la_admin_1` age recipient from the persistent host key.
2. Create LA host and OIDC ciphertext from repository templates, including the new outbound `identity/ssh_private_key`; preserve existing identity/OIDC values; do not rotate credentials.
3. Create LA tagged auth material carrying `tag:homelab` and `tag:ssh-clients`.
4. Create the LA R2 repository (`shrublab-backup-la-admin-1`); the DO repository was retained as migration recovery evidence.
5. Create the LA ntfy token.
6. Re-encrypt moving feature scopes for the LA recipient; the DO recipient was retained only on the shared scopes its running rollback services consumed, and has now been removed.

## First generation

Adoption, not reimage — follow host-initialization steps 2–7 with these LA values:

```sh
nixos-rebuild boot --target-host root@216.75.75.168 --use-remote-sudo --flake .#la-admin-1
```

- apply `boot`, not live `switch`; reboot through the provider console
- after reboot verify declared `dev` key SSH, Tailscale, and console-only `rescue` login
- then `deploy-rs` becomes the normal path (`dev@la-admin-1` over Tailscale); the public address is no longer the regular management path
- the first boot enables declared services; it is **not** the state-restore or private-validation gate

## State transfer sequence

1. **Quiesce LA first** — before any restore, subsequent reboot, or normal deploy, stop the state writers and timers for the restore window. Keep Tailscale running.

   ```sh
   sudo systemctl stop \
     kanidm.service vaultwarden.service \
     podman-termix.service podman-guacd.service podman-quantum.service \
     beszel-hub.service ntfy-sh.service restic-backups-state.service \
     restic-backups-state.timer host-recovery-reboot.timer nh-clean.timer

   for timer in restic-backups-state.timer host-recovery-reboot.timer nh-clean.timer; do
     test "$(systemctl show "$timer" -p LoadState --value)" = loaded
     test "$(systemctl is-active "$timer")" != active
     test -z "$(systemctl show "$timer" -p NextElapseUSecRealtime --value)"
   done
   ```

   Confirm every listed unit and timer is inactive, every named timer is loaded,
   and every timer has no next trigger before continuing. A runtime mask under `/run/systemd/system` does not
   override NixOS's generated unit link under `/etc/systemd/system`; do not use
   `systemctl is-enabled=masked` as the safety assertion. Re-run the stop and
   no-next-trigger checks after any `nixos-rebuild boot` because bootloader staging
   reloads systemd units. Do not stop
   `tailscaled.service`; do not start `podman-quantum.service` during this window,
   because its writable SSHFS mount reaches OCI.

2. **Private validation** — restore a recent DO snapshot to LA read-only using the canonical [state-restore runbook](./state-restore.md) procedures: version-matched Kanidm portable backup (`/var/lib/kanidm/backups/backup-*.json.gz`) via the stopped-service restore helper with offline verify before `kanidm.service` starts; Vaultwarden export plus state; Termix/Beszel state; ntfy uses declarative auth (see the runbook's ntfy section — there is no direct-copy restore); Quantum intentionally empty; no LA instance accepts authoritative writes. Keep the writers and timers quiesced until this validation is complete.

   The offline verify is a strict gate: every nonzero result is fatal before ownership repair or service start — do not proceed past a failure, and do not edit or "repair" the database to make the verify pass. The migration-period exception (Kanidm 1.10.4 single `RefintNotUpheld(319)` revoked-OAuth-session false positive, accepted only after read-only `db-scan` proofs) applied only to the migration restore window and was removed with the Kanidm 1.11 upgrade; the helper is now unconditionally fail-closed.
3. **Source freeze and final transfer** — quiesced DO writers during the maintenance window; captured the final managed backup; restored final state to stopped LA services per the state-restore runbook. ntfy was not part of the final transfer: its auth DB is recreated from declarative SOPS auth-users/auth-tokens on LA, and cache/history/attachments are accepted ephemeral state (no attachments exist) — remove any stale LA `auth.db` before the declarative reprovisioning. Record the final snapshot ID.
4. **Cloudflare cutover** — applied the policy-driven OpenTofu origin update to `216.75.75.168`; ran the cutover verification matrix; DO remained startable and routable as rollback through the soak window.
5. **24-hour soak and LA backup** — started the LA timers deliberately after the restore window, then ran and verified the first LA backup to `shrublab-backup-la-admin-1` with restore evidence per the state-restore runbook (Kanidm, Vaultwarden, ntfy).
6. **DO retirement** — retained the final DO snapshot, destroyed the droplet and attached resources, revoked the DO tailnet device after LA became authoritative, then removed the DO SOPS recipient and legacy configuration.
