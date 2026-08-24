## Why

`services.niks3-post-deploy` is wired on all three hosts but has never pushed a closure: the `systemd.paths` unit watches `PathChanged = "/run/current-system"`, a symlink to an immutable `/nix/store/...` directory. `PathChanged` fires only when the watched file is opened for writing and closed; for a symlink systemd watches the resolved target, and re-pointing the symlink produces no write event. Host evidence confirms the failure: `niks3-post-deploy.path` sits in `active (waiting)` while the service stays `inactive (dead)` across multiple switches.

As a result the sovereign cache only receives whatever niks3's `auto-upload` post-build-hook pushes for local builds — and `niks3-post-deploy` even forces that hook to `""` — so deployed closures are never pushed from the host after activation.

## What Changes

- Replace the broken `systemd.paths` trigger with a `system.activationScripts` snippet that writes the new toplevel path (from `$systemConfig`, available to activation snippets) to `/run/niks3-post-deploy/target` and starts the oneshot with `systemctl start --no-block` when systemd is running. The target file avoids a race with the final `ln -sfn /run/current-system`, which runs after all activation snippets; the unit reads the target from that file.
- The `restartTriggers = [ config.system.build.toplevel ]` alternative is impossible: the unit text embeds the trigger path (`X-Restart-Triggers` writeText) while the toplevel contains the unit text — circular evaluation, so the host toplevel fails to evaluate.
- At boot the snippet's `systemd` guard is false (stage-2 activates before systemd starts), so boot never triggers a push; `nixos-rebuild boot` staging does push because staging activation runs with systemd up.
- Keep the existing script body, public-key exclusion filter, and forced-empty `post-build-hook` semantics unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `sovereign-binary-cache`: host-side post-deployment closure push is guaranteed by a working trigger instead of a dead path unit.

## Impact

- `modules/shared/niks3-post-deploy.nix`
- `openspec/specs/sovereign-binary-cache/spec.md`
- No secret contents, host bindings, or external interfaces change.
