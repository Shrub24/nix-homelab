## Execution rules

- The parent agent owns every checkbox update in this file; delegates must not edit `tasks.md`.
- Hard stop: if the inventory finds a legacy responsibility without an obvious natural owner, or validation finds any unexplained runtime delta, stop and raise an architecture redesign. Do not patch around it with `mkForce`, a compatibility wrapper/aspect, hidden aspect imports, or a generic composition bus.
- Forbidden throughout: editing/decrypting/re-encrypting `secrets/**`, editing `.sops.yaml`, or editing deployment-related scripts, topology files, modules, or workflows. No deployment is part of this change.

## 1. Stage 1 baseline and exhaustive inventory

- [x] 1.1 Capture the clean Stage 1 baseline for all three hosts before implementation.
  - refs: `design.md` FND-7 and Equivalence; `modules/flake/registry.nix`; `modules/hosts/{oci-melb-1,la-admin-1,home-forge}/default.nix`
  - criteria: Record each host's toplevel derivation and targeted boot loader, `/build`, networkd/resolved/firewall, Tailscale flags/environment/secrets, notification daemon/monitor hooks, users, SSH, Nix settings, host outputs, and deploy projections; classify pre-existing failures.
  - delegate: BuildAgent
  - verify: All three target configurations evaluate from the clean pre-change tree and the baseline is sufficient for exact later comparisons.

- [x] 1.2 Inventory every import and responsibility under `modules/core/` and `modules/profiles/`, then assign each to an explicit Stage 2 owner.
  - refs: `design.md` FND-2, FND-3, FND-6; `modules/core/`; `modules/profiles/`; all three host modules; `modules/flake/registry.nix`
  - criteria: The inventory is exhaustive and host-by-host; it maps base, users, shell/p10k, networking, host recovery, Tailscale, Beszel auth, state backups, `niks3-post-deploy`, nixbuild SSH, `nh`, outbound SSH identity, cache upload, firewall, and Nix tuning to either a named aspect, an existing explicit leaf import, or an unchanged host declaration.
  - delegate: CodeScout
  - verify: Exhaustive import/reference search has no unclassified responsibility; if any item lacks an obvious owner, stop and raise an architecture redesign before editing code.

## 2. Foundation aspects and typed host facts

- [x] 2.1 Publish exactly the five foundation aspects and the minimal typed base facts.
  - refs: `design.md` FND-1, FND-2; `specs/fleet-infrastructure/spec.md`; `modules/flake/aspects.nix`; `modules/flake/registry.nix`
  - criteria: `flake.modules.nixos` publishes `base`, `shell`, `networking`, `tailscale`, and `notify`; selection is enablement; no aspect imports another aspect; the redundant `cli` aspect is removed and its nix-index input belongs to `shell`; `fleet.foundation.bootLoader` accepts only `grub` or `systemd-boot`, and `buildTmpfsSize` is a required typed string.
  - delegate: CoderAgent
  - verify: Targeted option evaluation rejects invalid/missing facts and confirms each registry record explicitly selects all five aspects.

## 3. Base, shell, and networking migration

- [x] 3.1 Migrate base/users and shell behavior, declare each host's base facts, and preserve legacy bundle responsibilities explicitly.
  - refs: `design.md` FND-2 and FND-6 responsibility table; `modules/core/base.nix`; `modules/core/users.nix`; `modules/profiles/base-server.nix`; `modules/profiles/fleet-standard.nix`; `modules/profiles/shell-profile.nix`; all three host modules
  - criteria: Base owns the existing base policy, users, Nix/`nh` tuning, outbound SSH identity contract, boot rendering, and `/build`; shell owns the existing packages, zsh, wezterm, activation, and p10k data; OCI declares `grub`/`8G`, LA and home-forge declare `systemd-boot`/`50%`; old boot and `/build` `mkForce` definitions are removed.
  - criteria: Every `base-server`/`fleet-standard` responsibility from the approved inventory is preserved at its design-table owner: base policy retains port 22/trusted Tailscale interface, substituters, Nix tuning, BBR, scheduler, host SSH identity convention, and host recovery; explicitly deferred leaves retain Beszel auth, state backups, `niks3-post-deploy`, nixbuild SSH, and cache-upload behavior; no compatibility wrapper/aspect or three-host secret-path duplication is introduced.
  - delegate: CoderAgent
  - verify: Targeted base, user, shell, SSH, Nix, firewall, boot, filesystem, and explicit-leaf import comparisons match the Stage 1 inventory for all hosts.

- [x] 3.2 Move the existing native networking contract into the networking aspect without redesign.
  - refs: `design.md` FND-3; `specs/fleet-infrastructure/spec.md`; `specs/network-access/spec.md`; `modules/profiles/networking.nix`; all three host networking facts
  - criteria: Existing `fleet.networking` options, assertions, networkd units, DHCP disabling, bridge behavior, resolved defaults, and all host facts remain unchanged; networking and Tailscale do not select one another.
  - delegate: CoderAgent
  - verify: Per-host networkd, resolved, DHCP, bridge, DNS, and firewall option values equal the Stage 1 baseline.

## 4. Tailscale and notification ownership

- [x] 4.1 Move Tailscale auth-key registration and MTU rendering to the Tailscale-owned contract.
  - refs: `design.md` FND-4; `specs/secrets-management/spec.md`; `specs/network-access/spec.md`; `modules/services/tailscale.nix`; all three host modules
  - criteria: The module derives `secrets/hosts/${config.networking.hostName}/system.yaml`, conditionally registers `tailscale_auth_key` with the existing key/path/mode, sets `authKeyFile`, preserves two-step bootstrap and secret ordering, and renders nullable typed `services.tailscale.debugMtu`; OCI and LA select `1200`, home-forge leaves it unset.
  - criteria: Host copies of the Tailscale secret, `authKeyFile`, and raw `TS_DEBUG_MTU` environment are removed; SSH/hostname flags, firewall posture, restart behavior, ciphertext, and readership remain unchanged.
  - delegate: CoderAgent
  - verify: Targeted `sops.secrets`, `services.tailscale`, and `systemd.services.tailscaled*` evaluations match Stage 1 except for ownership/source provenance; secret-scope checks pass without touching forbidden files.

- [x] 4.2 Make notification aspect selection compose and enable the existing daemon.
  - refs: `design.md` FND-5; `specs/apprise-notification-module/spec.md`; `modules/services/notification-daemon/default.nix`; `modules/services/state-backups.nix`; all three host modules
  - criteria: `notify` imports the existing notification-daemon leaf and sets `services.notification-daemon.enable = true`; hosts retain only established secret bindings, LA's local ntfy endpoint, ntfy selection, and monitor service lists; redundant host enable assignments/imports are removed.
  - delegate: CoderAgent
  - verify: Notification package/daemon, rendered config, monitor hooks, and backup integration evaluate equivalently for every host.

## 5. Atomic legacy-root deletion and exclusion shrink

- [x] 5.1 Delete obsolete core/profile contributors and shrink the exact import-tree contract.
  - refs: `design.md` FND-6; `specs/repository-structure/spec.md`; `modules/core/`; `modules/profiles/`; `modules/flake/_unconverted-nixos-dirs.nix`; `tests/check-dendritic-scaffold-contract.sh`
  - criteria: After proving all behavior moved, delete the obsolete wrappers/files and empty `modules/core/` and `modules/profiles/`; p10k data lives with the private shell implementation; no host references a removed path; no replacement compatibility layer exists.
  - criteria: Remove only `core` and `profiles` from the exclusion list and exact test inventory, leaving `applications`, `hosts`, `providers`, `services`, `shared`, and `storage`; if either directory retains a `.nix` file, stop and keep both conversion claim and exclusion shrink incomplete.
  - delegate: CoderAgent
  - verify: Exhaustive references to removed paths are clean, both directories are absent, and the scaffold contract passes with the exact reduced inventory.

## 6. Targeted contracts and current-state documentation

- [x] 6.1 Add or tighten only the contracts needed to lock Stage 2 behavior.
  - refs: all five delta specs; `tests/check-dendritic-scaffold-contract.sh`; `tests/check-secret-scope.sh`; `tests/phase-02-03-host-contract.sh`; `tests/phase-la-admin-contract.sh`; `.just/checks.just`
  - criteria: Focused checks cover exact aspect publication/host selection, typed base facts, explicit retained leaf imports, reduced exclusions, boot and `/build` rendering, Tailscale secret/MTU ownership, notify composition, and the absence of compatibility buses/new `mkForce` workarounds.
  - delegate: TestEngineer
  - verify: Each new assertion has a recorded failing pre-fix/negative case and passes on the Stage 2 tree; existing secret-scope and host contracts remain green.

- [x] 6.2 Update only current architecture and migration documentation affected by the completed structure.
  - refs: root `ARCHITECTURE.md`, `STRUCTURE.md`, `CONVENTIONS.md`; `docs/architecture.md`; `docs/decisions.md`; `docs/plan.md`; `docs/context-history.md`; `docs/dendritic-transition-analysis.md`; `docs/runbooks/host-initialization.md`; implemented Stage 2 paths
  - criteria: Current docs describe the five foundation aspects, typed host facts, explicit retained leaves, Tailscale/notify ownership, and removal of `modules/core/` and `modules/profiles/`; operator instructions and root taxonomy name only live paths; the former music-first Stage 2 sequence is marked superseded/historical.
  - delegate: DocWriter
  - verify: Current-path search finds no stale instruction to import deleted wrappers, and every documented path exists.

## 7. Equivalence, review, and strict validation

- [x] 7.1 Run formatting, focused contracts, the full check set, and canonical flake evaluation.
  - refs: `treefmt.toml`; `.just/checks.just`; `flake.nix`; `design.md` Equivalence
  - criteria: `treefmt --fail-on-change`, focused Stage 2 contracts, `just checks all`, and `nix flake check --no-build --no-write-lock-file --refresh path:.` pass; architecture-specific builds run only on capable builders.
  - delegate: BuildAgent
  - verify: Complete command output is recorded with no unclassified failure and no forbidden-file edit.

- [x] 7.2 Compare all three hosts to Stage 1 with `nix-diff` and targeted option equivalence.
  - refs: task 1.1 baseline; `design.md` FND-7, Equivalence, Risks; all three `nixosConfigurations`
  - criteria: Every derivation difference is classified line-by-line; targeted boot, `/build`, networking/resolved/firewall, Tailscale environment/secrets/order, notify/monitor, users, SSH, Nix settings, services, packages, host outputs, and deploy projections are equivalent.
  - delegate: BuildAgent
  - verify: Three-host report accepts only explained source/provenance movement; any unexplained runtime delta is a hard stop requiring architecture review, not `mkForce` or compatibility patching.

- [x] 7.3 Review the complete change for architecture, security, scope, and rollback correctness.
  - refs: `proposal.md`; `design.md`; all five delta specs; implementation diff; equivalence report
  - criteria: Review confirms no lost legacy responsibility, hidden aspect dependency, compatibility wrapper, generic bus, new `mkForce`, accidental feature activation, secret/readership change, deploy edit, or unexplained runtime delta.
  - delegate: CodeReviewer
  - verify: Independent review has no unresolved high- or medium-severity finding; redesign findings return to the parent rather than being patched locally.

- [x] 7.4 Run strict OpenSpec validation and hand off without deployment or archival.
  - refs: all change artifacts
  - criteria: Parent confirms all implementation/review evidence before updating checkboxes; `openspec validate dendritic-stage-2-foundation-aspects --strict` passes; the change is implementation-complete but neither deployed nor archived automatically.
  - delegate: Parent agent
  - verify: Strict validation succeeds and `openspec status --change dendritic-stage-2-foundation-aspects --json` reports all tasks complete.
