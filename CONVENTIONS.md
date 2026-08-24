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

**Profiles** are lightweight host/persona baseline modules. They import shared core, Tailscale, firewall, and operator UX defaults.

- Namespace: `modules/profiles/<name>.nix`
- Profiles are imported by hosts and do not require enable flags at the host layer.

**Hosts** are thin assembly layers. They declare identity, facts, provider/storage/profile imports, feature enables, secret source bindings, and narrow host-only overrides.

- Namespace: `hosts/<host>/default.nix`
- Host files MUST NOT own application-internal `sops.secrets`, `sops.templates`, tmpfiles, or cross-service wiring that belongs in application/service modules.

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

The standard XDG base directories for operator users (`.config`, `.cache`, `.local`, `.local/share`, `.local/state`) are declared as tmpfiles rules in `modules/core/users.nix`, next to the user declaration. Service and application modules own ONLY their leaf directories under that chain and MUST NOT declare parent home directories.

Name-based home-path tmpfiles rules cannot resolve on the very first boot pass (the `users` activation has not run yet); that is benign and healed by the reboot already required by the host-initialization runbook.
