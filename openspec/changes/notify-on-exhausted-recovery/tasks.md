# Tasks

## 1. Restart mode and recovery budget on monitored units

- [x] 1.1 In `modules/notifications/notify.nix`, put every unit registered under
      `services.notify.events` into `RestartMode=direct`, so a restart attempt produces no failure
      event and the hook fires only when the retries end.
- [x] 1.2 Give a registered unit that restarts a finite start limit (5 starts an hour, `mkDefault`,
      so an owner's explicit budget wins), and leave a unit that never restarts unbounded so a
      deploy is not refused.
- [x] 1.3 Fail evaluation with a named `notify:` error when a registered unit disables its own start
      limit, because direct mode would then restart it silently for ever.

## 2. Hold the contract

- [x] 2.1 Add `tests/notify-recovery-contract.nix` projecting the contract from the rendered unit
      files: mode present on monitored restarting units, finite limit on them, no mode on
      unmonitored units, no `notify:` assertion failing.
- [x] 2.2 Add `tests/check-notify-recovery-contract.sh` over all three hosts, with three
      single-field mutations as negative controls (forced `normal`, forced `direct` on an
      unmonitored unit, disabled start limit), and register it in `just checks all` and
      `scripts/run-repository-contracts.sh`.

## 3. Record the reasoning

- [x] 3.1 Add D-131 to `docs/decisions.md` and update the notification sections of
      `ARCHITECTURE.md`.
