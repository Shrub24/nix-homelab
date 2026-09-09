# Dendritic Stage 2 — Foundation Aspects Design

## Context

Stage 1 established the typed `nixos.configurations` registry and explicit
`flake.modules.nixos` imports without `specialArgs` (D-047, DS-1–DS-6). This
stage converts the duplicated fleet foundation into five selected aspects;
it does not convert products or operational capabilities that have their own
placement decisions.

The live tree permits a simpler conversion than the transition analysis's old
music-exemplar sequencing: `core/` contains only `base.nix` and `users.nix`,
and `profiles/` contains only the four legacy wrappers plus p10k data. Convert
or relocate all of that in this stage and remove both directories from the
import-tree exclusion list. Service leaves remain ordinary NixOS modules until
their focused conversions.

## Behavior IDs

| ID | Preserved or introduced composition behavior | Risk |
| --- | --- | --- |
| FND-1 | Hosts explicitly select the five foundation aspects | Medium |
| FND-2 | Base policy consumes typed boot and `/build` facts | High |
| FND-3 | Native networkd is selected and configured from host facts | High |
| FND-4 | Tailscale owns conventional auth-key registration and MTU tuning | High |
| FND-5 | Notify selection supplies the daemon required by backup monitoring | High |
| FND-6 | Legacy core/profile wrappers and exclusion entries are retired atomically | Medium |
| FND-7 | All three configurations remain evaluation-equivalent and revertible | High |

## Decisions

### FND-1 — Five published aspects; selection is enablement

Publish exactly these deferred NixOS modules through
`flake.modules.nixos`: `base`, `shell`, `networking`, `tailscale`, and
`notify`. Each registry record imports all five explicitly in its own
`module.imports` list. The import is the placement and enablement statement:
there is no foundation-level `enable` option and no aspect imports another
aspect.

The aspect may import its own plain/private NixOS leaf where that avoids a
mechanical rewrite. That is not a hidden aspect dependency: the selected
aspect remains the only public composition unit. In particular, `tailscale`
may import `modules/services/tailscale.nix`, and `notify` may import
`modules/services/notification-daemon/`; neither may import a second aspect.

### FND-2 — Base is policy plus two explicit machine facts

Absorb the current `core/base.nix`, `core/users.nix`, and shared policy from
`base-server.nix` into `base`. `base` owns Nix settings and substituters, UTC,
break-glass SSH and firewall policy, users, host SSH identity convention,
host-recovery import, common EFI policy, BBR tuning, the block-device scheduler,
and the standard `/build` tmpfs declaration. It defines the smallest host-fact
surface needed to eliminate the present override conflicts:

```nix
fleet.foundation = {
  bootLoader = "grub" | "systemd-boot";
  buildTmpfsSize = "8G" | "50%"; # typed string, required per host
};
```

The base aspect renders the selected loader, including the existing GRUB
removable-media settings or systemd-boot settings, and sets `/build` from the
fact. The common `canTouchEfiVariables = false` policy stays unchanged.
`oci-melb-1` declares `grub`/`8G`; `la-admin-1` and `home-forge` declare
`systemd-boot`/`50%`. OCI's generation limit remains its explicit host
exception. Delete the GRUB and `/build` host `mkForce` definitions rather than
changing priority to win the same conflict.

`shell` is separate because interactive tooling is a capability, not base OS
policy. It takes the shell-profile packages, zsh configuration, wezterm service,
and p10k data. Move p10k beside its private shell leaf (or embed the leaf) so
`modules/profiles/` has no remaining `.nix` contributor. The private WezTerm
mux toggle moves from `profiles.wezterm-mux` to `services.wezterm-mux`; it has no
external consumers and its evaluated behavior is unchanged, so the deleted
profile namespace is not retained as compatibility surface.

### FND-3 — Networking is the existing native contract, published directly

Move the current `profiles/networking.nix` implementation into the
`networking` aspect without changing its `fleet.networking` facts, assertions,
networkd units, DHCP disabling, bridge behavior, or resolved defaults. Each
host continues to state only its uplink, optional IPv6 RA choice, bridge, and
DNS facts. No legacy networking profile remains.

This preserves the current provider distinction: OCI selects `enp0s6`, no RA,
and pinned DNS; LA selects `ens18`; home-forge selects its `eno1`/`br0` MAC and
pinned DNS. `networking` does not select Tailscale and Tailscale does not select
physical networking.

### FND-4 — Tailscale owns host-system secret convention and MTU variant

Make the Tailscale aspect import the existing service leaf and extend that leaf
with its narrow owning contract:

- derive the conventional host secret source as
  `secrets/hosts/${config.networking.hostName}/system.yaml`;
- when that file exists, register `tailscale_auth_key` with the existing key,
  path (`/run/secrets/tailscale.auth_key`), and mode, and set `authKeyFile`;
- retain the current two-step bootstrap behavior when the host secret is absent;
- expose one nullable, typed `services.tailscale.debugMtu` setting; when set,
  the Tailscale module writes `TS_DEBUG_MTU` to `tailscaled`.

`oci-melb-1` and `la-admin-1` declare `debugMtu = 1200`; home-forge leaves it
unset. Hosts delete their Tailscale `sops.secrets`, `authKeyFile`, and raw
systemd environment copies. Hostname flag, SSH flag, firewall posture, and
restart/secret ordering remain in the Tailscale leaf. This is a service-owned
default, not a new fleet secret registry; `.sops.yaml`, ciphertext, readers,
and secret values are untouched.

### FND-5 — Notify selection includes its daemon

`notify` imports the notification-daemon leaf and supplies
`services.notification-daemon.enable = true` as part of the selected aspect.
Hosts retain only real variants: their existing secret-file bindings, local ntfy
endpoint override on LA, ntfy choice, and monitor service list. Remove the
three redundant host `enable = true` assignments.

This makes `state-backups` safe: its existing
`services.notification-daemon.monitor.enable = mkDefault true` always has the
declared monitor template and daemon module when the selected host enables
backups. Do not change `state-backups`, backup semantics, notification payloads,
or notification secrets in this stage.

### FND-6 — Delete composition wrappers; retain unconverted leaves explicitly

Delete `base-server.nix`, `fleet-standard.nix`, `networking.nix`, and the
consumed `core/*.nix` files after their behavior is relocated. Move any retained
shell data into the private shell implementation; then delete `modules/core/`
and `modules/profiles/` and remove both names from
`modules/flake/_unconverted-nixos-dirs.nix`. This removal is all-or-nothing:
if any `.nix` file remains in either directory, keep that directory excluded and
do not claim conversion completion.

`fleet-standard` is not renamed into a compatibility aspect. Its responsibilities
go to their natural owners as follows:

| Current responsibility | Stage 2 location |
| --- | --- |
| `core/base.nix`: timezone, SSH/sudo, Nix defaults, EFI/GRUB baseline | `base` policy; loader rendered from the typed host fact |
| `core/users.nix`: dev/root users, SSH keys, user tmpfiles | `base` policy |
| `base-server.nix`: port 22/trusted Tailscale interface, substituters/tuning, `/build`, BBR, scheduler | `base` policy; `/build` size rendered from the typed host fact |
| `base-server.nix`: host recovery | Private leaf imported by `base` |
| `base-server.nix`: Tailscale | Selected public `tailscale` aspect, not imported by `base` |
| `base-server.nix`: Beszel auth and state backups | Explicit unchanged private leaf imports in each host record until their focused aspects |
| `fleet-standard.nix`: common Nix tuning and `nh` cleanup | `base` policy |
| `fleet-standard.nix`: outbound dev SSH identity | `base` derives the conventional host-system file and preserves the existing conditional option/template contract |
| `fleet-standard.nix`: `niks3-post-deploy` and nixbuild SSH | Explicit unchanged private leaf imports in each host record until their focused aspects |
| `fleet-standard.nix`: their enablement, cache endpoint/token defaults | Existing host declarations, unchanged until each focused ownership change |

The explicit deferred-leaf rows intentionally remain visible raw-leaf
composition. Moving them into `base` would silently enable optional operational
features and would scope-creep into backups, builder access, or Beszel. No new
wrapper, registry, or abstraction layer is introduced.

`shell` imports the nix-index-database input module directly because it owns
comma. The standalone `cli` aspect is deleted rather than retained as a second
name for the same capability. `notify` resolves its two packages through
`withSystem` and passes them through the notification module's native package
options. Neither aspect relies on registry co-selection to declare or satisfy
its own options; the temporary `fleet-packages` aspect remains only for
unconverted service consumers.

## Non-goals and boundaries

- No edits to encrypted secrets, `.sops.yaml`, recipient policy, deployment
  topology/order, bootstrap metadata, or `specialArgs` (which Stage 1 removed).
- No conversion of backups, builder access, Beszel, identity/admin/Cockpit,
  music, or product/service aspects. Existing direct leaf imports are retained
  only to preserve their declared options while their owning conversion is
  deferred.
- No hidden aspect imports, compatibility aspect, new generic contract bus, or
  `mkForce` replacement.

## Equivalence, staged migration, and rollback

1. Capture each Stage 1 host toplevel derivation and targeted values: boot
   loader, `/build`, networkd/resolved/firewall, Tailscale flags/environment and
   secrets, notification service/monitor hooks, users, SSH, and Nix settings.
2. Add the five aspect definitions and move private leaves; change every host
   registry import list and replace profile imports in one working change.
3. Move the two base facts and the Tailscale/notify declarations to their owning
   contracts; delete legacy definitions only after the new evaluated values
   match.
4. Prove `core` and `profiles` are empty of `.nix` files before removing their
   import-tree exclusions. Run the dendritic scaffold contract, secret-scope
   check, formatter check, and canonical
   `nix flake check --no-build --no-write-lock-file --refresh path:.` gate.
5. Evaluate all three target systems and run `nix-diff` against Stage 1.
   Any derivation delta must be classified line-by-line; changed source/provenance
   alone is acceptable only when the targeted option comparisons prove runtime
   equivalence. Architecture-specific builds run on capable builders.

Rollback is a revert of the single Stage 2 JJ change followed by the same
evaluation checks. There is no deployment, disk migration, secret migration, or
data migration in this change.

## Risks

- **Fact migration changes bootability** — require exact boot and filesystem
  option comparisons for every host; do not deploy as part of the refactor.
- **A direct raw leaf is omitted while deleting `fleet-standard`** — inventory
  every old import/configuration responsibility against the table above and
  evaluate all hosts before deletion.
- **Tailscale secret registration changes activation order** — preserve the
  existing paths, mode, and `sops-install-secrets` dependency; compare evaluated
  secret records and `tailscaled` unit environment.
- **Notify becomes an accidental product dependency** — it stays a foundation
  requirement only because all current backup-enabled hosts rely on its monitor;
  later backup/notify aspect work may separate that selection explicitly.
- **Import-tree discovers an unconverted leaf** — retain the explicit exclusion
  until the directory inventory proves the conversion complete.

## Unresolved question

None requiring user input. The exact private-leaf placement (embedded deferred
module versus underscore-prefixed local NixOS leaf) is an implementation choice:
use the shorter form that preserves the above public aspect and import contracts.
