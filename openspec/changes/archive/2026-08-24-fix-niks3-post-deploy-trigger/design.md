## Context

`services.niks3-post-deploy` is enabled on all three hosts but has never pushed a closure. Its trigger is a `systemd.paths` unit watching `PathChanged = "/run/current-system"`. Per `systemd.path(5)`, `PathChanged` fires only on open-for-write followed by close of the watched file; for a symlink, systemd watches the resolved target. `/run/current-system` is a symlink to an immutable `/nix/store/...` directory, so re-pointing the symlink with `ln -sfn` on every switch produces no write event — the path unit can never fire. Host evidence confirms: `niks3-post-deploy.path` has been `active (waiting)` since Aug 10 with the oneshot never running, despite multiple switches.

Because `niks3-post-deploy` forces `nix.settings.post-build-hook = ""`, the sovereign cache only ever receives what niks3's own auto-upload hook pushes for local builds. Deployed closures — the majority, since deploys are remote-build heavy — are never pushed.

## Goals / Non-Goals

**Goals:**

- Push the filtered system closure after every activation where a new generation lands on the host, regardless of where the closure was built (host-local, dev machine, nixbuild.net, or CI).
- Preserve the existing design: filtered push (public-key exclusion), forced-empty post-build-hook, oneshot semantics, no shared fleet push token.
- Skip pushes at boot when the active generation is already current; push only when a new generation actually activates.

**Non-Goals:**

- Change `post-build-hook` semantics (reverting to per-build pushes is a deliberate non-goal; the module forces it empty).
- Alter secret contents, SOPS recipients, or the niks3 server API contract.
- Introduce a fleet orchestration tool; this stays a single-module trigger fix.

## Decisions

- **Trigger from `system.activationScripts` instead of `systemd.paths`.** Activation scripts run on the host at every activation (`switch` and `boot`) with `$systemConfig` set to the *new* toplevel path before the snippet block runs, so the trigger knows the new generation without racing the final `ln -sfn /run/current-system`. This is the native post-deploy equivalent: it fires on the host that owns the generation, irrespective of build location.
- **Rejected `restartTriggers = [ config.system.build.toplevel ]`.** The idiomatic native mechanism, but circular here: systemd-lib renders `X-Restart-Triggers` into a `writeText` file whose content stringifies the trigger paths, so the unit text embeds the toplevel path while the toplevel derivation contains the unit text. Evaluation fails with infinite recursion on every host (verified: `config.system.build.toplevel` no longer evaluates with this change in place). nixpkgs only uses `restartTriggers` with leaf files (journald.conf, tmpfiles.d sources), never the generation root.
- **Write the new toplevel to `/run/niks3-post-deploy/target` and start the oneshot with `systemctl start --no-block`.** `$systemConfig` is substituted into the snippet; the service reads the target file with a `readlink -f /run/current-system` fallback. The file avoids the post-snippet `ln -sfn` race and makes the unit's input explicit. `--no-block` plus `|| true` ensures a failed push never fails the switch.
- **Guard the `systemctl start` with `[ -e /run/systemd/system ]`.** At boot, stage-2 runs activation scripts before `exec systemd`, so systemctl is unavailable and the push is skipped — correct, since a boot of an already-pushed generation needs no push. At switch time systemd is up and the push runs. `nixos-rebuild boot` staging is covered: staging activation runs with systemd up, so staged closures are pushed before reboot.
- **No `wantedBy`.** The unit is started exclusively by the activation snippet; boot does not trigger it (per the guard), keeping boot-time cache HEAD checks minimal.

## Risks / Trade-offs

- **Activation-time network failure** → `--no-block` + `|| true` keeps the switch successful; the push is skipped until the next activation. A retry hook is out of scope; boot-time push was deliberately excluded to avoid per-boot cache checks.
- **Path unit and activation script both triggering** → Not possible: the path unit is removed, so there is exactly one trigger path.
- **`/run/niks3-post-deploy/target` staleness** → The file is rewritten every activation with the new toplevel, and the service falls back to `readlink -f /run/current-system` if absent. A manually started unit on a fresh boot pushes the current generation, which the filter makes a cheap no-op.

## Migration Plan

1. Evaluate each host: activation script text contains the target write and guarded `systemctl start`; no `niks3-post-deploy.path` unit is generated; the toplevel evaluates without recursion.
2. Deploy `oci-melb-1` through the normal host workflow (deploy-rs), then the remaining hosts.
3. Confirm the oneshot runs after activation and the journal shows the filtered push result (`No paths to push` or `niks3-hook send` completion).
4. Roll back through deploy-rs if activation or the push misbehaves; the change is a single module, so rollback is a single-generation revert.
