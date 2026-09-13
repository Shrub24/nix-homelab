## Conventions

### Feature Namespace and Enablement

**Applications** are composition roots for multi-service stacks. They own shared paths, assertions, composition-level secret inputs, and multi-service wiring behind one operator-facing toggle.

- Namespace: `applications.<name>`
- Every application entrypoint MUST expose `applications.<name>.enable`.
- Application/product aspects are published from discovered concern contributors under `modules/flake/<concern>.nix`; their private implementations live beside the owner under underscore-private paths (`modules/flake/_<concern>/`) or, transitionally, under `modules/services/`. The legacy `modules/applications/` root was deleted in Stage 7 (D-053).

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

- The five foundation aspects are `base`, `shell`, `networking`, `tailscale`, and `notify`; the three operational aspects are `backups`, `builder-access`, and `observability-agent`; `dj` is a host-selected application aspect and `identity-client` is a host-selected deployment aspect composed from two discovered contributors. All current registry hosts select the eight foundation/operational aspects; `home-forge` additionally selects `dj`, while `oci-melb-1` and `la-admin-1` select `identity-client`.
- `provenance`, `oci-images`, `fleet-packages`, and `web-policy` are infrastructure support modules (typed repository data, package projections, provenance, and resolved web policy for lower-level consumers), not host-facing deployment capabilities; they remain only until consumers migrate to native projections. All three hosts select `web-policy` because all three consume `config.repo.web` (notification defaults and host policy).
- Plain class-oriented NixOS leaves and the import-tree filter are transitional, not the endpoint: after Stage 7 the filter is exactly `hosts` and `services`, it must shrink as converted roots empty, and underscore-renaming whole roots solely to hide unchanged code is not completion. Genuine private implementation/data may remain private with underscore-prefixed or otherwise explicit private paths.
- Several discovered top-level contributors may define the same `flake.modules.nixos.<aspect>` when a capability is composed from independent source files: `identity-client` is the first such merge (`modules/flake/identity-oidc.nix` + `kanidm-host-auth.nix`, each nesting its own options/config inline). Do not add a `_identity-client/` private leaf directory, a central wrapper, or a cross-contributor import for this pattern.
- Private implementation leaves live under concern-owned underscore-prefixed paths beside their aspect owner, and the split is deliberate — do not normalize it away later. `modules/flake/_aspects/` holds foundation implementations (`base.nix`, `shell.nix` + `p10k.zsh`, `networking.nix`, `host-recovery.nix`), `modules/flake/_backups/` holds the backups leaves (`niks3-upload-client.nix`, `niks3-post-deploy.nix`), and `modules/flake/_builder-access/` holds `nixbuild-ssh.nix`, `modules/flake/_dj/` holds the DJ composition + Engine DJ implementation (`default.nix`, `engine-dj.nix`), `modules/flake/_edge/` holds the relocated edge-ingress implementation, and `modules/flake/_oci/` holds the relocated OCI provider defaults. They are not discovered, publish no `flake.modules.nixos.<name>`, and are imported only by their owning aspect (`modules/flake/dj.nix`, `edge.nix`, `oci.nix`).
- Policy co-selection is a recorded, documented relationship, not an implicit trap: `admin-hub`, `identity-provider`, and `identity-client` are Mandatory co-selection on `la-admin-1` (Kanidm enablement lives in `identity-provider`, which reads `applications.admin` from `admin-hub` and sets `services.identity.oidc.providerUrl` owned by `identity-client`; `admin-hub` writes `services.admin.kanidm.*` declared by the leaf `identity-provider` imports). All three are selected together by that host's registry record; no aspect imports a sibling aspect, and a lone selection fails evaluation loudly with the missing option namespace.
- An aspect may import its own private NixOS leaf (under `modules/flake/_aspects/`, `_backups/`, `_builder-access/`, or a service leaf) without creating a hidden public dependency — e.g. `base` imports `modules/flake/_aspects/host-recovery.nix`, `tailscale` imports `modules/services/tailscale.nix`, `notify` imports `modules/services/notification-daemon/`, `backups` imports `modules/services/state-backups.nix` plus the upstream `niks3-auto-upload` module and the `modules/flake/_backups/niks3-{upload-client,post-deploy}.nix` leaves, `builder-access` imports `modules/flake/_builder-access/nixbuild-ssh.nix`, `observability-agent` imports `modules/services/beszel-agent-auth.nix`.
- `backups` derives the conventional host secret path (`secrets/hosts/<host>/system.yaml`) and the `shrublab-backup-<host>` bucket, gates enablement on the secret file's existence (two-step sops bootstrap), injects the post-deploy `nix-path-filter` package per system, and asserts `services.notification-daemon.monitor.enable` (the `notify` aspect owns monitor composition) without importing `notify`. The classified `nix.settings.post-build-hook = lib.mkForce ""` suppression is required because upstream `niks3-auto-upload` has no separate hook-disable option.
- `builder-access` owns only nixbuild.net SSH trust; substituter policy stays in `base`. `observability-agent` owns Beszel agent enrollment (derived host secret path, pathExists gate) but not the Beszel hub, which remains an admin-service leaf.
- `base` owns the typed machine facts `fleet.foundation.bootLoader` (`"grub"` | `"systemd-boot"`) and `fleet.foundation.buildTmpfsSize` (required string); hosts declare facts instead of fighting shared defaults with `mkForce`.
- The former `modules/core/`, `modules/profiles/`, `modules/shared/`, and `modules/storage/` directories are deleted; their behavior lives in the foundation aspects, the operational aspects, the concern-owned private leaves, the discovered contributors, or host-local layouts. Do not reintroduce profile/core wrappers, a shared storage menu, or a `modules/shared/` catch-all.

**Hosts** are thin assembly layers. They declare identity, typed foundation facts, feature enables, secret source bindings, and narrow host-only overrides.

- Namespace: `modules/hosts/<host>/default.nix`, registered as a `nixos.configurations.<host>` record in `modules/flake/registry.nix`
- The registry record owns the explicit aspect/leaf import list; host files MUST NOT own application-internal `sops.secrets`, `sops.templates`, tmpfiles, or cross-service wiring that belongs in application/service modules.

**Providers** isolate cloud/platform-specific behavior.

- Namespace: host-selected provider aspect (`modules/flake/oci.nix` + private leaf `modules/flake/_oci/default.nix`); the legacy `modules/providers/<name>/` root was deleted in Stage 7
- Hosts select the provider aspect relevant to their cloud in the registry; they do not import provider implementations.

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
| Music | `applications.music` | `applications.music` (enablement provided by the selected `music` aspect) |
| Admin | `applications.admin` | `applications.admin` (enablement provided by the selected `admin-hub` aspect; Kanidm by `identity-provider`, Cockpit by `cockpit`) |
| Edge Ingress | `applications."edge-ingress"` | `applications."edge-ingress"` (enablement provided by the selected `edge` aspect; `role` stays host-set) |
| Tailscale | `services.tailscale` | `services.tailscale` (no change) |
| Syncthing | `services.syncthing` | `services.syncthing` (no change) |
| Bifrost | `services.bifrost-gateway` | `services.bifrost-gateway` (no change) |
| Admin sub-services | `services.admin.*` | `services.admin.*` (no change) |

### User Home Structure

The standard XDG base directories for operator users (`.config`, `.cache`, `.local`, `.local/share`, `.local/state`) are declared as tmpfiles rules in the `base` foundation aspect (`modules/flake/_aspects/base.nix`), next to the user declaration. Service and application modules own ONLY their leaf directories under that chain and MUST NOT declare parent home directories.

Name-based home-path tmpfiles rules cannot resolve on the very first boot pass (the `users` activation has not run yet); that is benign and healed by the reboot already required by the host-initialization runbook.
