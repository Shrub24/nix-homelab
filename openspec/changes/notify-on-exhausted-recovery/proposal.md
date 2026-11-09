# Proposal

## Why

A failure notification is the fleet's priority channel, and today it reports the wrong thing. A unit
that systemd is about to retry still exposes a failed state, so `OnFailure=` fires on every attempt:
one crash loop pages once per retry, a transient crash reaches the operator as an alert, and the
burst of `notify-event@<unit>` jobs outruns the handler's own start limit, which drops the
notifications the operator needed.

Per-attempt evidence already has a home. Journald keeps the invocation, Vector ships it to
VictoriaLogs, and the metric lanes keep the unit state, so the notification channel can stay sparse
and mean one thing: automatic recovery gave up.

**Core Value:** A failure notification is worth acting on, and arrives once per incident.

## What Changes

- Every unit registered under `services.notify.events` that auto-restarts runs in
  `RestartMode=direct`: systemd skips the intermediate failed state and its hook while it retries,
  and fires the hook when the start limit gives out.
- Those units carry a finite start limit (five starts an hour by default) so that ending exists; an
  explicitly configured budget still wins, and a registration on a unit that disables its limit
  fails evaluation with a named error.
- Units nobody monitors are untouched, and the mechanism itself — daemon, CLI, handler, contract —
  stays in nix-fleet.

## Impact

- `modules/notifications/notify.nix` — the fleet's notification policy contributor.
- `tests/check-notify-recovery-contract.sh` and `tests/notify-recovery-contract.nix` — the contract,
  with negative controls, registered in `just checks all` and the repository-contract runner.
- `ARCHITECTURE.md` and `docs/decisions.md` (D-131).
