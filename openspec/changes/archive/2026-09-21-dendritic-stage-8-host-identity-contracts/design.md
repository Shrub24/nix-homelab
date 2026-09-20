## Context

Concrete hosts are still enumerated in `modules/flake/registry.nix` and excluded from import-tree discovery. Stable identity is repeated in host modules, deploy metadata, web origins, and two private cross-host endpoints. Identity/admin must first be directional so the discovered-host pattern does not canonize accidental coupling.

## Goals / Non-Goals

**Goals:**
- HIC-1: one typed authority for stable host identity;
- HIC-2: each host source registers itself through discovery;
- HIC-3: deploy and web metadata reference known host IDs;
- HIC-4: PostgreSQL and Niks3-write consumers use narrow typed contracts;
- HIC-5: source layout expresses feature ownership independently of aspect granularity.

**Non-Goals:**
- a scheduler, universal service registry, or automatic aspect introspection;
- internal DNS deployment;
- merging physical deploy metadata with web routing;
- converting all service leaves.

## Decisions

### HIC-1 — Canonical host records

Define a typed fleet host record keyed by stable host ID. It owns target system, Tailscale identity, and deferred NixOS composition. `networking.hostName` and Tailscale FQDN derive from this identity. Bootstrap metadata may remain host-owned optional fields.

### HIC-2 — Discover host contributors

Each host `default.nix` becomes a flake-parts contributor declaring its record. Hardware facts, disko, and host-private NixOS fragments move under underscore-private paths. The generic registry validates and materializes records; it names no concrete host.

### HIC-3 — Reference, do not merge, metadata concerns

Deploy topology retains SSH/deploy facts and web policy retains routing/exposure facts. Both use canonical host IDs and fail on unknown references. They do not become fields in a universal host object.

### HIC-4 — Two explicit internal transport contracts

Add typed PostgreSQL and Niks3-write contracts with provider host ID and port plus resolved host/FQDN/URL outputs. PostgreSQL consumers and Niks3 uploaders use those outputs. Cache reads remain the S3/public policy contract; identity and ntfy remain web-catalog contracts. A check asserts each provider host selects the corresponding aspect.

### HIC-5 — Semantic source paths

As settled concerns are touched, place discovered contributors in domain directories. `modules/flake/` retains registry, deploy, package, dev-shell, and output materialization. Underscore paths remain private implementations. No repo-wide path-only shuffle is included.

## Risks / Trade-offs

- **Recursive module evaluation cycle** → keep host records as deferred modules/data and materialize only after option merging; avoid deriving placement from evaluated NixOS configs.
- **Host rename becomes security-sensitive** → stable IDs are explicit keys; no automatic rename/migration.
- **Contract/provider drift** → add negative checks for unknown providers and missing provider aspect selection.
- **Web policy contains literal FQDNs not tied to hosts** → only host-backed internal origins are normalized; externally managed names remain explicit.

## Migration Plan

1. Freeze flake outputs, bootstrap projection, deploy topology, and per-host structured observables.
2. Add generic host schema and convert one host contributor at a time while preserving output names.
3. Switch deploy/web references to validated IDs and remove concrete registry entries.
4. Add and migrate the two internal contracts.
5. Remove `hosts` from the discovery exclusion; retain only `services`.

Rollback restores the centralized registry and literal endpoints; no runtime state or secret material migrates.
