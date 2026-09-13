## 1. Baseline and contract

- [ ] 1.1 Capture all current `services.notification-daemon.monitor.services` inputs and evaluated target service definitions on all three hosts; verify the report includes the deployed home-forge baseline from `/tmp/home-forge-beets-monitor-baseline.txt`.
- [ ] 1.2 Add typed `monitor.units.<unit>` event options in `modules/services/notification-daemon/default.nix`; verify a focused eval covers defaults and per-event overrides.
- [ ] 1.3 Add a fail-closed real-service assertion using pre-injection service definitions; verify a synthetic phantom unit fails with its name.

## 2. Ownership migration

- [ ] 2.1 Move Beets monitor contributions into the music concern owner and remove OCI's Beets entries; verify home-forge has hooks and OCI has no Beets service fragments.
- [ ] 2.2 Move Beszel, `nh-clean-all`, OmniRoute, and remaining repository-owned monitor registrations to their owning contributors; verify every registered unit has a real `ExecStart` or `script`.
- [ ] 2.3 Remove the old monitor list option and host-maintained reverse indexes; verify exhaustive search finds no stale assignment.

## 3. Equivalence and validation

- [ ] 3.1 Compare Beets `OnFailure`, `ExecStartPost`, and `ExecStopPost` before/after; verify retry/failure and preprocess cleanup hooks remain and requested notification hooks are additive.
- [ ] 3.2 Add positive and negative monitoring contract tests to `tests/check-dendritic-scaffold-contract.sh` or a focused test; verify they fail on phantom targets and wrong-host Beets registration.
- [ ] 3.3 Run `treefmt --fail-on-change`, `just checks all`, all host evaluations, and `openspec validate feature-owned-service-monitoring --strict`; obtain an independent blocker review and leave the change undeployed/unarchived.
