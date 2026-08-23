## 1. Rework niks3-post-deploy trigger

- [x] 1.1 Replace the `systemd.paths.niks3-post-deploy` unit with a `system.activationScripts.niks3-post-deploy` snippet that writes `readlink -f "$systemConfig"` to `/run/niks3-post-deploy/target` and starts the service with `systemctl start --no-block` when systemd is running, in `modules/shared/niks3-post-deploy.nix`.

    refs: `modules/shared/niks3-post-deploy.nix`
    criteria: the `systemd.paths` block is gone; the activation snippet writes the target file and starts the unit; the unit script reads the target file with a `readlink -f /run/current-system` fallback.

- [x] 1.2 Keep the existing script body, `post-build-hook = lib.mkForce ""`, and `EXCLUDE_PUBLIC_KEYS` semantics unchanged.

    refs: `modules/shared/niks3-post-deploy.nix`
    criteria: the script still uses the filter and `niks3-hook send`; no unrelated edits.

## 2. Validation

- [x] 2.1 Evaluate `oci-melb-1` and confirm the activation script contains the target write and guarded `systemctl start`; confirm no `niks3-post-deploy.path` is generated; confirm the toplevel still evaluates (no infinite recursion from restartTriggers).

    verify: `nix eval .#nixosConfigurations.oci-melb-1.config.system.activationScripts.niks3-post-deploy.text --json` plus `nix eval .#nixosConfigurations.oci-melb-1.config.systemd.paths --apply builtins.attrNames --json` (niks3-post-deploy must be absent) and `nix eval .#nixosConfigurations.oci-melb-1.config.system.build.toplevel --apply (p: p.outPath) --json`.

- [x] 2.2 Run `openspec validate fix-niks3-post-deploy-trigger --strict` and `nix flake check` (or the repo's standard checks).

    verify: both pass with no warnings or errors.
