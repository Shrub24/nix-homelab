# Design

## The lever is the restart mode, not the delivery path

systemd 254 added `RestartMode=`: `normal` (the default) restarts by passing through a failed or
inactive state, while `direct` transitions straight back to activating and skips `OnSuccess=` and
`OnFailure=` for the attempts it retries. Both modes run `ExecStopPost=`, and both are subject to
`StartLimitIntervalSec=`/`StartLimitBurst=`.

That is exactly the split the notification channel wants, so the change is one directive on the
monitored units rather than a new component in the delivery path. Verified against the pinned
systemd 262 source (`src/core/service.c`, `src/core/unit.c`): `service_enter_dead` only sets the
intermediate state when the restart mode is not direct, and `unit_notify` starts `OnFailure=`
dependencies whenever the unit enters `UNIT_FAILED` — which the intermediate state does map to.

## A notification means the retries ended, so the retries must end

`direct` is only coherent with a finite budget. With no window of its own a slow crash loop — a
service that fails twenty seconds after start — retries for ever under systemd's default five
starts per ten seconds, and direct mode would then silence it with nothing ever reported. So the
budget and the mode travel together: `StartLimitIntervalSec=3600`, `StartLimitBurst=5` by
`mkDefault`, matching the bound the container units already carry (D-077's sibling invariant), with
an owner's explicit value winning.

Because the two must not drift, a registered unit that disables its own limit fails evaluation with
a named `notify:` error instead of quietly restarting for ever.

## Scope: monitored units only, decided by the registration

The rule keys on `services.notify.events`, the contract a capability already writes when it owns a
unit, so no new option and no second enablement dialect appear. A unit nobody registered keeps
whatever restart policy its owner chose, and the contract check fails if an unmonitored unit
acquires the mode.

The budget follows the unit's own `Restart` setting rather than the registration: a oneshot that
never restarts has no recovery to bound, and bounding it would only refuse a sixth deploy of the
same generation. Package-provided units (`tailscaled`, `nix-daemon`) get the mode as an override
drop-in and keep their upstream budget, because their unit text is not ours to budget.

## Rejected alternatives

- **Debounce in the daemon.** It hides the trigger instead of removing it, still pays one handler job
  per attempt, and adds a stateful policy layer to a component whose job is delivery.
- **Severity splitting (transient versus real).** systemd reports a result code, not a classification;
  the fleet would be inventing the distinction, and the operator would still see a burst.
- **A global `RestartMode=direct` default.** It would change the recovery of every restarting unit in
  the fleet, including the ones whose dependents rely on that propagation, to fix a notification.

## Consequences accepted

- A transient crash is no longer announced. That is the decision: the trail is the journal, the log
  lane and the Grafana boards.
- Direct mode does not propagate the restart to dependent units. A monitored provider
  (`podman-geopulse-backend`, `podman-sparkyfitness-server`) therefore no longer restarts its
  consumer; the consumer stays running across the outage and reconnects. This is the simpler
  recovery, and the contract check records that it is deliberate rather than accidental.
- The seam that decides "notify on failure means notify when a failure transition is exposed" is
  nix-fleet's `lib/notify-contract.nix`. This change is the fleet's realization of its direct-mode
  clause; if a second consumer wants the same semantics, the six lines move upstream and are bound
  here.

## Validation

`tests/check-notify-recovery-contract.sh` evaluates every host and asserts, from the rendered unit
files rather than from option plumbing: a monitored restarting unit carries `RestartMode=direct` and
a finite `StartLimitIntervalSec`; an unmonitored unit carries no mode; no `notify:` assertion fails.
It then runs the same rules against three single-field mutations — a forced `normal` mode, a forced
`direct` mode on an unmonitored unit, and a disabled start limit — and fails unless each is
reported, so a rule cannot pass by being vacuous.
