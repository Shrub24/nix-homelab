# Proposal

## Why

Docs-mcp 3.1.0 cannot embed or search through the fleet's Voyage route: its OpenAI factory hardcodes `encoding_format: "float"`, which Voyage rejects with HTTP 400. The same model and input succeed through Bifrost when that field is omitted; the provider returns the existing 1024-dimensional vectors.

**Core Value:** Restore the existing OpenAI-compatible embedding endpoint without changing clients, exposing provider credentials to more hosts, or rebuilding the documentation index.

## What Changes

- Replace the gateway's runtime with nix-fleet's dynamic Bifrost build and load nix-fleet's Voyage plugin into it:
  - `inputs.nix-fleet.packages.<system>.bifrost` — the plugin-capable Bifrost v2.2.5 transport that provides `bin/bifrost-http`.
  - `inputs.nix-fleet.packages.<system>.bifrost-voyage-plugin` — a separate derivation providing `lib/bifrost/voyage.so`.
  - The two are built by nix-fleet from the same pinned source, Go toolchain, CGO setting, and vendored module graph, so the Go plugin loader's shared package hashes match. This change does not restate either derivation, its version, or its build graph.
- Declare the plugin once in the repo-owned Bifrost configuration:
  `{"enabled": true, "name": "voyage-normalizer", "path": "<plugin>/lib/bifrost/voyage.so", "placement": "post_builtin"}`.
  The plugin is the single owner of Voyage embedding normalization; this repository does not reimplement, wrap, or duplicate that transformation.
- Keep the fixed Voyage upstream, provider keys, model alias (`voyage/voyage-4`), 1024-dimensional store, client URLs, and existing vectors unchanged. Provider authorization stays in the existing `env.VOYAGE_API_KEY` binding and per-provider `network_config.extra_headers`; no new secret file, recipient, or credential flow is added. The document does change where 2.2.5 requires it: the admin account moves to `auth_config` (the binary no longer reads admin credentials from the environment) and provider blocks the new runtime rejects for standard providers are dropped.
- Add no adapter, proxy, sidecar, or middleware daemon: normalization happens inside the gateway process that already serves the endpoint.

### Constraints

- The prior `docker.io/maximhq/bifrost:v1.5.0-prerelease8` image is a static, non-plugin build; it cannot load an external Go plugin and is ABI-incompatible with the pinned build. It is removed as the runtime source, not adapted.
- The dependency is a published nix-fleet revision that exposes both package outputs. A local checkout, `--override-input`, or a path-pinned substitute is not an acceptable committed lock; if the published pin lacks either output, this change stops at that task.
- Upstream has demonstrated live plugin load on `x86_64` only. `aarch64-linux` is the fleet's first host; a build-and-live-load proof on `aarch64` is a required gate before any deployment.
- Keep this change separate from `telemetry-backends-home-forge`. That relocation is already applied and gated in the tree, and the standing arrangement is that a deploy carries the staged tree, so its artifacts are consumed here rather than deployed from an isolated source.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `ai-gateway`: Require provider-local Voyage embedding normalization delivered as a gateway plugin, unchanged consumer/store identity, a private plugin-loading boundary with no additional listener or daemon, and preserved upstream embedding observability. This extends `openspec/specs/ai-gateway/spec.md` without revising its unrelated configuration-store requirements.

## Impact

- Gateway runtime consumption in `modules/ai/bifrost/service.nix`: the container image pin becomes nix-fleet's native build — first as this repository's own unit (D-078), then as nix-fleet's published gateway aspect, which owns the unit, the service account, the application directory and the startup-configuration install (D-079) — and the plugin entry is registered through `services.bifrost.plugins`.
- Gateway configuration in `policy/bifrost-config.json`: the Voyage provider keeps its native HTTPS endpoint; one plugin entry is added with a path rendered from the nix-fleet plugin package (the built-in `otel` entry moves into the same registry, since the fleet module owns that configuration member, D-079); the admin account moves to `auth_config` and standard-provider blocks the new runtime rejects are dropped.
- Package plumbing in `modules/flake/packages.nix` (or the existing consumption helper) so the two nix-fleet outputs reach the gateway module without restating their build.
- Focused tests under `tests/` for the rendered plugin entry and route, integrated into the existing check surface.
- No changes to docs-mcp configuration, host aspect placement, encrypted secrets, nix-fleet, or backend-move artifacts.
