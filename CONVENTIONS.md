## Conventions

### Feature Namespace and Enablement

**Applications** are composition roots for multi-service stacks. They own shared paths, assertions, composition-level secret inputs, and multi-service wiring behind one operator-facing toggle.

- Namespace: `applications.<name>`
- Every application entrypoint MUST expose `applications.<name>.enable`.
- Application modules live under `modules/applications/<name>/default.nix` (directory form) or `modules/applications/<name>.nix` (single-file form where the name is a clean domain label).

**Services** are leaf implementation modules. They own runtime configuration, podman/systemd units, internal `sops.secrets` registrations, templates, assertions, and restart semantics.

- Namespace: `services.<domain>.<name>` for grouped services, `services.<name>` for top-level standalone services.
- Every service that can be directly enabled by a host MUST expose `services.<name>.enable`.
- Service modules live under `modules/services/<name>.nix` or `modules/services/<domain>/<name>.nix`.
- Service option names MUST NOT be host-suffixed; keep them host-agnostic.

**Deployment aspects** are the cross-cutting host baseline published through `flake.modules.nixos.<aspect>` and selected explicitly by host registry records. Selection is enablement: there is no aspect-level `enable` option, and selecting an application aspect (e.g. `dj`) provides the application's top-level enablement. Aspect relationships are modeled by semantics rather than a universal no-aspect-import rule:

- **Intrinsic composition:** the owner directly imports a required implementation or aspect that has no meaningful independent placement; the relationship is documented at the ownership boundary.
- **Policy co-selection:** independently placeable capabilities are selected together by host policy and may use a named evaluation assertion (e.g. `backups` asserts the notify-owned monitor option without importing `notify`).
- **Optional integration:** integration activates only when both contracts are present; neither capability silently selects the other.

Direct public-aspect imports are not globally forbidden but require intrinsic-composition justification.

- The five foundation aspects are `base`, `shell`, `networking`, `tailscale`, and `notify`; the three operational aspects are `backups`, `builder-access`, and `observability-agent`; `dj` is the first host-selected application aspect. All current registry hosts select the eight foundation/operational aspects; `home-forge` additionally selects `dj`.
- `provenance`, `oci-images`, and `fleet-packages` are infrastructure support modules (typed repository data, package projections, provenance for lower-level consumers), not host-facing deployment capabilities; they remain only until consumers migrate to native projections.
- Plain class-oriented NixOS leaves and the six-directory import-tree filter are transitional, not the endpoint: the filter must shrink as converted roots empty, and underscore-renaming whole roots solely to hide unchanged code is not completion. Genuine private implementation/data may remain private with underscore-prefixed or otherwise explicit private paths.
- An aspect may import its own private NixOS leaf (under `modules/flake/_aspects/` or a service/shared leaf) without creating a hidden public dependency — e.g. `base` imports `modules/shared/host-recovery.nix`, `tailscale` imports `modules/services/tailscale.nix`, `notify` imports `modules/services/notification-daemon/`, `backups` imports `modules/services/state-backups.nix` plus the upstream `niks3-auto-upload` module and the `modules/shared/niks3-{upload-client,post-deploy}.nix` leaves, `builder-access` imports `modules/shared/nixbuild-ssh.nix`, `observability-agent` imports `modules/services/beszel-agent-auth.nix`.
- `backups` derives the conventional host secret path (`secrets/hosts/<host>/system.yaml`) and the `shrublab-backup-<host>` bucket, gates enablement on the secret file's existence (two-step sops bootstrap), injects the post-deploy `nix-path-filter` package per system, and asserts `services.notification-daemon.monitor.enable` (the `notify` aspect owns monitor composition) without importing `notify`. The classified `nix.settings.post-build-hook = lib.mkForce ""` suppression is required because upstream `niks3-auto-upload` has no separate hook-disable option.
- `builder-access` owns only nixbuild.net SSH trust; substituter policy stays in `base`. `observability-agent` owns Beszel agent enrollment (derived host secret path, pathExists gate) but not the Beszel hub, which remains an admin-service leaf.
- `base` owns the typed machine facts `fleet.foundation.bootLoader` (`"grub"` | `"systemd-boot"`) and `fleet.foundation.buildTmpfsSize` (required string); hosts declare facts instead of fighting shared defaults with `mkForce`.
- The former `modules/core/` and `modules/profiles/` directories are deleted; their behavior lives in the foundation aspects, the operational aspects, or feature leaves selected in host records. Do not reintroduce profile/core wrappers.

**Hosts** are thin assembly layers. They declare identity, typed foundation facts, feature enables, secret source bindings, and narrow host-only overrides.

- Namespace: `modules/hosts/<host>/default.nix`, registered as a `nixos.configurations.<host>` record in `modules/flake/registry.nix`
- The registry record owns the explicit aspect/leaf import list; host files MUST NOT own application-internal `sops.secrets`, `sops.templates`, tmpfiles, or cross-service wiring that belongs in application/service modules.

**Providers** isolate cloud/platform-specific behavior.

- Namespace: `modules/providers/<name>/`
- Hosts import the provider relevant to their cloud.

### Application vs Service Ownership

- **Application**: wraps multiple interacting services and shared feature behavior. Use only when real composition value exists (shared paths, assertions, secrets shared across services, multi-service tmpfiles/ACL logic, one operator-facing stack toggle).
- **Service**: single workload or well-defined leaf primitive. Singleton services do NOT get application wrappers just for taxonomy.

### Secret Ownership

- Applications and services own their `sops.secrets`, `sops.templates`, assertions, and runtime wiring for their own secret contracts.
- Leaf modules expose explicit contract inputs (`secretFiles.*`, `secretKeys.*`) rather than requiring callers to mutate raw `sops.secrets.<name>` internals.
- Hosts only provide host-scoped secret file paths and feature enables; they do not assemble internal secret templates.

### Namespace Canonical Forms

| Feature | Current (pre-refactor) | Target (post-refactor) |
|---------|----------------------|----------------------|
| Karakeep | `services.karakeep-oci` | `services.karakeep-pod` |
| Music | `applications.music` | `applications.music` (add `enable`) |
| Admin | `applications.admin` | `applications.admin` |
| Edge Ingress | `applications."edge-ingress"` | `applications."edge-ingress"` |
| Tailscale | `services.tailscale` | `services.tailscale` (no change) |
| Syncthing | `services.syncthing` | `services.syncthing` (no change) |
| Bifrost | `services.bifrost-gateway` | `services.bifrost-gateway` (no change) |
| Admin sub-services | `services.admin.*` | `services.admin.*` (no change) |

### User Home Structure

The standard XDG base directories for operator users (`.config`, `.cache`, `.local`, `.local/share`, `.local/state`) are declared as tmpfiles rules in the `base` foundation aspect (`modules/flake/_aspects/base.nix`), next to the user declaration. Service and application modules own ONLY their leaf directories under that chain and MUST NOT declare parent home directories.

Name-based home-path tmpfiles rules cannot resolve on the very first boot pass (the `users` activation has not run yet); that is benign and healed by the reboot already required by the host-initialization runbook.
