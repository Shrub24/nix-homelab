## Conventions

### Feature Namespace and Enablement

**Applications** are composition roots for multi-service stacks. They own shared paths, assertions, composition-level secret inputs, and multi-service wiring behind one operator-facing toggle.

- Namespace: `applications.<name>`
- Every application entrypoint MUST expose `applications.<name>.enable`.
- Application/product aspects are published from discovered concern contributors under their domain directory (`modules/<domain>/<concern>.nix`); a second contributor publishes the same aspect name from a sibling file in that directory (`modules/cache/cache-publisher/upload-client.nix`), and `_` is reserved for a value-imported helper beside its owner (`modules/music/_beets/runners.nix`). `modules/flake/` is reserved for flake materialization, the fleet baseline, and the infrastructure support quartet (D-056). The legacy `modules/applications/` root was deleted in Stage 7 (D-053), and the service root was converted in the post-Stage-8 services-tree conversion.

**Services** are leaf implementation modules. They own runtime configuration, podman/systemd units, internal `sops.secrets` registrations, templates, assertions, and restart semantics.

- Namespace: `services.<domain>.<name>` for grouped services, `services.<name>` for top-level standalone services.
- Every service that can be directly enabled by a host MUST expose `services.<name>.enable`.
- Service modules live beside the aspect that owns them: `modules/<domain>/<name>.nix`, where the file is either its own discovered aspect or a sibling contributor publishing the same aspect name.
- Service option names MUST NOT be host-suffixed; keep them host-agnostic.

**Deployment aspects** are the cross-cutting host baseline published through `flake.modules.nixos.<aspect>` and selected explicitly by canonical host records (`nixos.hosts.<id>`). Selection is enablement: there is no aspect-level `enable` option, and selecting an application aspect (e.g. `dj`) provides the application's top-level enablement. Aspect relationships are modeled by semantics rather than a universal no-aspect-import rule:

- **Intrinsic composition:** the owner directly imports a required implementation or aspect that has no meaningful independent placement; the relationship is documented at the ownership boundary.
- **Policy co-selection:** independently placeable capabilities are selected together by host policy and may use a named evaluation assertion (e.g. `state-backups` and `cache-publisher` assert the notify-owned monitor option without importing `notify`).
- **Optional integration:** integration activates only when both contracts are present; neither capability silently selects the other.

Direct public-aspect imports are not globally forbidden but require intrinsic-composition justification.

- The five foundation aspects are `base`, `shell`, `networking`, `tailscale`, and `notify`; the four operational aspects are `state-backups`, `cache-publisher`, `builder-access`, and `observability-agent`; `internal-contracts` is the fleet-level contract module; `dj` is a host-selected application aspect and `kanidm-host-auth` is a host-selected deployment capability. All current hosts select the eight foundation/operational aspects plus `internal-contracts`; `home-forge` selects `music`/`dj`, while `oci-melb-1` and `la-admin-1` select `kanidm-host-auth` (and `la-admin-1` additionally `identity-provider`). The canonical OIDC contract is selected by no host: it is an intrinsic module its readers import (D-059).
- `provenance`, `oci-images`, `fleet-packages`, and `web-policy` are infrastructure support modules (typed repository data, package projections, provenance, and resolved web policy for lower-level consumers), not host-facing deployment capabilities; they remain only until consumers migrate to native projections. All three hosts select `web-policy` because all three consume `config.repo.web` (notification defaults and host policy).
- Plain class-oriented NixOS leaves and the import-tree filter are transitional, not the endpoint: after Stage 8 (D-056) the filter is exactly `[ "services" ]`, it must shrink as converted roots empty, and underscore-renaming whole roots solely to hide unchanged code is not completion. Genuine private implementation/data may remain private with underscore-prefixed or otherwise explicit private paths.
- Several discovered top-level contributors may define the same `flake.modules.nixos.<aspect>` when a capability is composed from independent source files: `edge` is the current example (`modules/edge/edge.nix` plus its `edge-ingress-application` and `edge-ingress-runtime` siblings). Do not add a private leaf directory for the merge, a central wrapper, or a cross-contributor import for this pattern.
- Capability, contract, and security binding are separate concerns (D-059). A runtime capability is a host-selected aspect; a shared contract or derived projection is an intrinsic module that its readers import, or fleet-level policy (`policy/*.json`); helpers and package-family invariants are value-level support and MUST NOT become aspects; a credential's readership stays an explicit per-deployment binding even when the logical credential identity is shared with a provider.
- `_` paths are reserved for value-imported helpers, asset directories, host-private data, and intrinsic contracts — a sibling contributor publishing the same aspect name is the form for extra module bodies, not an underscore directory. Examples: `modules/flake/shell/p10k.zsh` (prompt theme beside `modules/flake/shell.nix`), `modules/music/_beets/runners.nix` (Beets runner units beside `modules/music/beets.nix`), `modules/admin/homepage/_data.nix` (dashboard data value-imported by `modules/admin/homepage.nix`), the declaration surfaces `modules/database/postgres/_consumer.nix` and `modules/backups/state-backups/_consumer.nix`, the intrinsic OIDC contract `modules/identity/_oidc.nix` and the Kanidm release-family value `modules/identity/_kanidm-packages.nix`, and host fragments such as `modules/hosts/<host>/_nixos.nix` and `_disko-*.nix`. They are not discovered and they publish no `flake.modules.nixos.<name>`; a `_` helper is imported by its owner rather than discovered. This is load-bearing, not cosmetic: a non-underscore file under `modules/` is imported as a flake-parts module, where `config` is the flake-parts config and the NixOS option tree is unavailable, so a contract or helper placed there fails rather than merely being published.
- Policy co-selection is a recorded, documented relationship, not an implicit trap, and co-location alone does not justify it (D-054): a policy co-selection exists only where explicit shared placement policy or a security/lifecycle/portability/contract rationale demands it. The former mandatory `admin-hub`/`identity-provider`/`identity-client` co-selection on `la-admin-1` was dissolved — LA selects the capabilities it wants, identity is consumed directionally, and real cross-aspect dependencies fail through named contract assertions rather than missing-option errors. The identity half of that trio was further retired by D-059: the OIDC contract is intrinsic and the capability is `kanidm-host-auth`.
- An aspect may import its own private NixOS leaf (under its domain's `_*` path, or a sibling contributor beside it) without creating a hidden public dependency — e.g. `base` imports `modules/flake/base/host-recovery.nix`, `tailscale` is `modules/flake/tailscale.nix`, `notify` carries the notification-daemon body in `modules/notifications/notify.nix`, `state-backups` is `modules/backups/state-backups.nix` with its declaration surface in `modules/backups/state-backups/_consumer.nix`, `cache-publisher` imports the upstream `niks3-auto-upload` module plus the siblings, `builder-access` is `modules/flake/builder-access.nix`, `observability-agent` is `modules/flake/observability-agent.nix`.
- `state-backups` derives the conventional host secret path (`secrets/hosts/<host>/system.yaml`) and the `shrublab-backup-<host>` bucket and gates restic enablement on the secret file's existence (two-step sops bootstrap). `cache-publisher` derives the same host secret path, owns the sibling contributors resolves the write endpoint through the `niks3Write` internal contract (`config.repo.internal.niks3Write`, D-056), injects the post-deploy `nix-path-filter` package per system, and asserts `services.notification-daemon.monitor.enable` (the `notify` aspect owns monitor composition) without importing `notify`. The classified `nix.settings.post-build-hook = lib.mkForce ""` suppression is required because upstream `niks3-auto-upload` has no separate hook-disable option. The classified `nix.settings.post-build-hook = lib.mkForce ""` suppression is required because upstream `niks3-auto-upload` has no separate hook-disable option.
- `builder-access` owns only nixbuild.net SSH trust; substituter policy stays in `base`. `observability-agent` owns Beszel agent enrollment (derived host secret path, pathExists gate) but not the Beszel hub, which remains an admin-service leaf.
- `base` owns the typed machine facts `fleet.foundation.bootLoader` (`"grub"` | `"systemd-boot"`) and `fleet.foundation.buildTmpfsSize` (required string); hosts declare facts instead of fighting shared defaults with `mkForce`.
- The former `modules/core/`, `modules/profiles/`, `modules/shared/`, and `modules/storage/` directories are deleted; their behavior lives in the foundation aspects, the operational aspects, the concern-owned private leaves, the discovered contributors, or host-local layouts. Do not reintroduce profile/core wrappers, a shared storage menu, or a `modules/shared/` catch-all.

**Internal transport contracts** are typed cross-host endpoints.

- Exactly two exist (D-056): the shared PostgreSQL substrate and the private Niks3 write API, declared in `modules/fleet/internal-contracts.nix`
- Consumers read `config.repo.internal.<contract>.{provider,port,host,fqdn,url}` instead of restating a provider host name; the endpoint derives from the provider's canonical record
- The provider host must select the aspect that enables the capability, and the declared port must match the provider's real listen port
- Identity (Kanidm) and ntfy MUST NOT gain an internal contract — they stay web-catalog contracts (`repo.web.catalog`); `tests/check-internal-contracts.sh` pins the surface to exactly the two

**Hosts** are thin assembly layers. They declare a canonical host record (identity, target system, aspect selection, reimage facts) and keep host-private facts and secret bindings in the underscore-private `_nixos.nix` composition.

- Namespace: `modules/hosts/<host>/default.nix` — a discovered contributor declaring the typed `nixos.hosts.<id>` record (schema and materializer: `modules/flake/host-registry.nix`)
- The record owns identity, target system, and the explicit `composition.aspects` selection; the private `_nixos.nix` composition owns host facts and secret-path bindings, and host files MUST NOT own application-internal `sops.secrets`, `sops.templates`, tmpfiles, or cross-service wiring that belongs in application/service modules.
- Host-private material stays underscore-prefixed (`_nixos.nix`, `_disko-*.nix`, `_cockpit-auth.nix`, `_admin-runtime.nix`); `facter.json` is the deliberate exception because its path is a host-derivation input.

**Providers** isolate cloud/platform-specific behavior.

- Namespace: host-selected provider aspect (`modules/oci/oci.nix`, provider body inline); the legacy `modules/providers/<name>/` root was deleted in Stage 7
- Hosts select the provider aspect relevant to their cloud in the registry; they do not import provider implementations.

### Flake Reference and Provenance

Local evaluation of this repository uses the Git-tree flake form `.#`. `path:` remains correct in exactly three places: contract tests that evaluate a copied tree with no Git repository (or that evaluate the working tree while injecting untracked fixtures), the nvfetcher refresh validation that must see freshly generated untracked files, and `scripts/export-web-services-policy.sh`, which resolves the tree with an explicit path because it exports policy data rather than evaluating host configuration.

- Operator entrypoints — `justfile` recipes, workflow files, `scripts/resolve-host-config.sh`, and documented cutover commands — MUST use `.#` / `.#<output>`. One exception is deliberate: `scripts/export-web-services-policy.sh` resolves the tree with an explicit path because it exports policy data rather than evaluating host configuration.
- The form decides what `/etc/nixos-source` publishes. `.#` copies tracked content, so the published provenance is the fleet configuration (~5.5 MB) rather than the working directory (440 MB, including VCS metadata, `.terraform` provider binaries, editor caches, and plaintext credential files), and `system.configurationRevision` is populated instead of `null`.
- Tracking is the single filtering authority. Do not add a Nix-side exclusion list (`lib.fileset`, `cleanSourceWith`, `filterSource`) to compensate for untracked files; track them instead.
- `.#` reads the Git index: do not run index-mutating Git commands (`git reset`, `git checkout`, `git stash`) in this colocated repository, and repair a reported divergence with `git add -A` (guarded by `tests/check-flake-source-tracking.sh`).
- `flake.nix` is generated by `flake-file`. Inputs are declared in the tree — `modules/flake/inputs.nix` for the shared baseline and the fleet-owned dependencies, or the contributor that owns a dependency — and regenerated with `nix run .#write-flake`. Never hand-edit it: it carries a do-not-edit header, and both `just checks all` and CI build `checks.<system>.check-flake-file`, which fails when the committed file drifts from the declarations.
- nix-fleet is the authority for the pins the repositories share (`nixpkgs`, `flake-parts`, `import-tree`, `sops-nix`, `niks3`). They are declared here as follows aliases to `nix-fleet/<input>`, never as a URL, so adding a dependency never restates a shared pin. Local development against a sibling checkout uses `just dev nf-eval <host>`, `just dev nf-build <host>` and `just dev nf-check` (or `NIX_FLEET=<path>`); the override applies to the invocation and leaves the committed lock untouched.

### Shared Aspect Consumption

nix-fleet publishes the fleet's shared aspects (`tailscale`, `beszel-agent`, `builder-access`, `niks3-cache`, `niks3-publisher`, `notification-daemon`) in its own `flake.modules.nixos` namespace. This repository cannot select them directly — an input repository's aspects do not enter our namespace — so each consumed aspect keeps a local contributor under its domain directory that publishes our aspect name, imports the shared module, and supplies the fleet's conventions.

- The shared module owns the mechanism: service wiring, option declarations, fail-closed assertions, secret registration, unit ordering.
- The local contributor owns the fleet's conventions and policy: conventional secret paths (`secrets/hosts/<host>/system.yaml`), the values policy/globals.nix holds, and the host-facing bindings that keep host records unchanged. A host record never learns that the mechanism moved.
- The bridge is the whole file. Do not fork the shared module's body back in, and do not re-declare its options locally.
- Aspect names are ours: nix-fleet's file name does not constrain the name we publish, so host records and the scaffold contract keep the fleet's names (`cache-publisher`, `observability-agent`) regardless of the upstream file name.
- Equivalence is judged on structured observables per host (option values, `sops.secrets` entries, systemd unit wiring), never on derivation paths: the published source set moves whenever a file is added or removed.

### Shared Capability Registration

A capability that serves more than one service exposes a typed registry and provisions from it; the capability module names no participant, and a participant's own module registers itself. Three instances exist: `services.state-backups.services.<name>`, `services.notification-daemon.monitor.units.<unit>`, and `services.postgres.consumers.<instance>.<name>`.

- Register where provisioning happens: a same-host consumer registers from its own module; a cross-host consumer is registered by the host that provisions its role, because that is the only host that can create it.
- Registrations are fail-closed: a phantom unit, a host declaring two clusters, a password consumer without a credential, or a credential file that does not exist fails evaluation with a named error.
- A registration carries the consumer's own credential (`password = { file, key }`) and dependency contributions in the shared option's native shape (`extensions = ps: [ ps.pgvector ]`, a function of the instance's extension set). SQL that accompanies an extension belongs in `setupSQL`, which must be idempotent because it runs on every start.
- A capability that instead holds a participant list (a host name, a publisher, a monitored-unit list) is debt to convert, not a pattern to copy.

### Application vs Service Ownership

- **Application**: wraps multiple interacting services and shared feature behavior. Use only when real composition value exists (shared paths, assertions, secrets shared across services, multi-service tmpfiles/ACL logic, one operator-facing stack toggle).
- **Service**: single workload or well-defined leaf primitive. Singleton services do NOT get application wrappers just for taxonomy.

### Secret Ownership

- Applications and services own their `sops.secrets`, `sops.templates`, assertions, and runtime wiring for their own secret contracts.
- Leaf modules expose explicit contract inputs (`secretFiles.*`, `secretKeys.*`) rather than requiring callers to mutate raw `sops.secrets.<name>` internals.
- Hosts only provide host-scoped secret file paths and feature enables; they do not assemble internal secret templates.

### Namespace Canonical Forms

| Feature            | Current (pre-refactor)        | Target (post-refactor)                                                                                                                                    |
| ------------------ | ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Karakeep           | `services.karakeep-oci`       | `services.karakeep-pod`                                                                                                                                   |
| Music              | `applications.music`          | `applications.music` (enablement provided by the selected `music` aspect)                                                                                 |
| Admin              | `applications.admin`          | deleted (D-054): each admin workload owns its own namespace (`services.admin.<workload>.*`); Kanidm is owned by `identity-provider`, Cockpit by `cockpit` |
| Edge Ingress       | `applications."edge-ingress"` | `applications."edge-ingress"` (enablement provided by the selected `edge` aspect; `role` stays host-set)                                                  |
| Tailscale          | `services.tailscale`          | `services.tailscale` (no change)                                                                                                                          |
| Syncthing          | `services.syncthing`          | `services.syncthing` (no change)                                                                                                                          |
| Bifrost            | `services.bifrost-gateway`    | `services.bifrost-gateway` (no change)                                                                                                                    |
| Admin sub-services | `services.admin.*`            | `services.admin.*` (no change)                                                                                                                            |

### User Home Structure

The standard XDG base directories for operator users (`.config`, `.cache`, `.local`, `.local/share`, `.local/state`) are declared as tmpfiles rules in the `base` foundation aspect (`modules/flake/base/foundation.nix`), next to the user declaration. Service and application modules own ONLY their leaf directories under that chain and MUST NOT declare parent home directories.

Name-based home-path tmpfiles rules cannot resolve on the very first boot pass (the `users` activation has not run yet); that is benign and healed by the reboot already required by the host-initialization runbook.
