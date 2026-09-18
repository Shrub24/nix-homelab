## 1. Baseline and boundaries

- [x] 1.1 At apply start, pin the exact post-D-054 parent revision this change applies onto, then capture every current host's (`oci-melb-1`, `la-admin-1`, `home-forge`) state-backup units/timers/repositories/paths, Niks3 upload units/socket/activation script/filter, secret registrations, bootstrap gates, and monitor contributions, including the `aspects.backups` selections in `modules/flake/registry.nix`; verify the two capability inventories are explicit.

## 2. Independent aspects

- [x] 2.1 Publish `state-backups` owning only restic state recovery and its monitoring; verify selecting it alone introduces no Niks3 upload or publication units.
- [x] 2.2 Publish `cache-publisher` owning the upstream upload module, upload client, post-deploy trigger/filter, write secret, and its monitoring; verify selecting it alone introduces no restic definitions.
- [x] 2.3 Replace `backups` with explicit selection of both aspects on all current hosts and delete the old contributor without a compatibility bundle; verify no transitive public-aspect imports exist.

## 3. Bootstrap and behavior equivalence

- [x] 3.1 Preserve independent two-step secret gates using current host-scoped paths/keys; verify absent-secret synthetic hosts can enable either capability independently without base activation failure.
- [x] 3.2 Compare all captured units, timers, activation scripts, repositories, paths, filters, secrets, and monitor behavior before/after; verify no runtime delta beyond aspect ownership and names.
- [x] 3.3 Add subset and regression checks in two explicit gates complementing task 3.2's equivalence comparison: (a) subset — `state-backups` and `cache-publisher` each evaluate alone and introduce only their own units (a cache-publisher-only host has no restic unit; a state-backups-only host has no Niks3 upload daemon or post-deploy push); (b) old-aspect absence — no `flake.modules.nixos.backups` output and no `aspects.backups` selection remains.

## 4. Validation

- [ ] 4.1 Update architecture/spec references and feature-oriented source ownership; verify no documentation describes cache publication as state backup.
- [ ] 4.2 Run `treefmt --fail-on-change`, `just checks all`, all host evaluations, and `openspec validate split-state-backups-cache-publication --strict`; obtain independent security/operations review and leave the change undeployed/unarchived.
