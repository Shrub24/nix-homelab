#!/usr/bin/env bash
# Notification recovery contract: a registered failure event reports that
# automatic recovery ended, never a single failed attempt.
#
# Every monitored unit that restarts therefore restarts in direct mode (systemd
# skips the failed/inactive transition, and its failure hook, for each attempt)
# and carries a finite start limit, which is the ending the notification
# reports. Units nobody monitors are untouched, and a monitored unit that
# removes its own start limit fails evaluation instead of restarting silently
# for ever.
#
# The projection only asserts a contract if breaking it is detectable, so the
# same rules run against three single-field mutations: a forced normal mode, a
# forced direct mode on an unmonitored unit, and a disabled start limit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "check-notify-recovery-contract: $*" >&2
  exit 1
}

report="$(mktemp)"
trap 'rm -f "$report"' EXIT

nix eval --impure --json --no-write-lock-file \
  --file tests/notify-recovery-contract.nix \
  --apply "f: f { flake = builtins.getFlake \"git+file://$ROOT\"; }" >"$report"

python3 - "$report" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1]))
if not report:
    sys.exit("check-notify-recovery-contract: no host was evaluated")

problems = []
for host, result in sorted(report.items()):
    if not result["restartingMonitored"]:
        problems.append(f"{host}: no monitored unit restarts; the contract is unproven here")
    problems += [f"{host}: {finding}" for finding in result["findings"]]
    problems += [
        f"{host}: assertion {message}"
        for message in result["notifyAssertionFailures"]
        if message.startswith("notify:")
    ]

    forced = result["forcedNormal"]
    if not any(f"{forced['unit']}: restarts without RestartMode=direct" in f for f in forced["findings"]):
        problems.append(
            f"{host}: forcing RestartMode=normal on {forced['unit']} was not reported, "
            "so the direct-mode rule proves nothing"
        )

    stray = result["strays"]
    if not any(f"{stray['unit']}: carries RestartMode=direct" in f for f in stray["findings"]):
        problems.append(
            f"{host}: forcing RestartMode=direct on {stray['unit']} was not reported, "
            "so the scope rule proves nothing"
        )

    unbounded = result["unbounded"]
    if not any(
        message.startswith(f"notify: {unbounded['unit']} ")
        for message in unbounded["notifyAssertionFailures"]
    ):
        problems.append(
            f"{host}: disabling the start limit on {unbounded['unit']} was accepted, "
            "so the recovery-budget guard proves nothing"
        )

if problems:
    sys.exit("check-notify-recovery-contract:\n  " + "\n  ".join(problems))

print("check-notify-recovery-contract: ok (%s)" % ", ".join(sorted(report)))
PY
